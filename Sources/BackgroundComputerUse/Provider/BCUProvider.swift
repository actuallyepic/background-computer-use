import AppKit
import Foundation
import Network
@preconcurrency import WebKit

@MainActor
public final class BCUWebEnvironment {
    public static let shared = BCUWebEnvironment()

    public let websiteDataStore: WKWebsiteDataStore
    public let userAgent: String?

    public init(
        websiteDataStore: WKWebsiteDataStore = .default(),
        userAgent: String? = BrowserWebCompatibility.desktopSafariUserAgent
    ) {
        self.websiteDataStore = websiteDataStore
        self.userAgent = userAgent
    }

    public func makeConfiguration(
        installBootstrap: Bool = true,
        allowsJavaScriptOpenWindowsAutomatically: Bool = true
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowsJavaScriptOpenWindowsAutomatically

        if installBootstrap {
            configuration.userContentController.addUserScript(bootstrapUserScript())
        }
        return configuration
    }

    public func installBootstrap(on webView: WKWebView) {
        webView.configuration.userContentController.addUserScript(bootstrapUserScript())
        if (webView.customUserAgent ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let userAgent = resolvedUserAgent() {
            webView.customUserAgent = userAgent
        }
    }

    public func makeWebView(frame: CGRect = .zero) -> WKWebView {
        let webView = WKWebView(frame: frame, configuration: makeConfiguration())
        webView.customUserAgent = resolvedUserAgent()
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        return webView
    }

    private func resolvedUserAgent() -> String? {
        let trimmed = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func bootstrapUserScript() -> WKUserScript {
        WKUserScript(
            source: BrowserBootstrapScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}

public struct BCUProviderPageEvent: Sendable {
    public let providerID: String
    public let surfaceID: String
    public let type: String
    public let scriptID: String?
    public let payload: JSONValueDTO
}

@MainActor
public final class BCUProvider {
    public let providerID: String
    public let displayName: String
    public private(set) var surfaces: [BrowserRegisteredProviderSurfaceDTO] = []
    public private(set) var bridgeBaseURL: URL?
    public var pageEventHandler: (@MainActor (BCUProviderPageEvent) -> Void)?

    private var webSurfaces: [String: BCURegisteredWebViewSurface] = [:]
    private var bridgeServer: BCUProviderBridgeServer?
    private var controlPlaneBaseURL: URL?

    public init(providerID: String, displayName: String) {
        self.providerID = providerID
        self.displayName = displayName
    }

    public func register(
        webView: WKWebView,
        surfaceID: String,
        title: String? = nil,
        url: String? = nil,
        hostWindow: BrowserHostWindowDTO? = nil,
        capabilities: BrowserTargetCapabilitiesDTO = .defaultProviderWebView
    ) {
        BCUWebEnvironment.shared.installBootstrap(on: webView)
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        let handler = BCUWebSurfaceMessageHandler(provider: self, surfaceID: surfaceID)
        webView.configuration.userContentController.add(handler, name: "bcu")
        let surface = BCURegisteredWebViewSurface(
            surfaceID: surfaceID,
            explicitTitle: title,
            explicitURL: url,
            explicitHostWindow: hostWindow,
            capabilities: capabilities,
            webView: webView,
            messageHandler: handler
        )
        webSurfaces[surfaceID] = surface
        refreshSurfaceSummaries()

        Task { @MainActor in
            _ = try? await webView.evaluateJavaScript(BrowserBootstrapScript.source)
        }
    }

    public func startBridge() async throws -> URL {
        if let bridgeBaseURL {
            return bridgeBaseURL
        }

        let server = BCUProviderBridgeServer { [weak self] request in
            await self?.handleProviderRequest(request) ?? HTTPResponse.json(
                ErrorResponse(
                    error: "provider_unavailable",
                    message: "The BCU provider instance is no longer available.",
                    requestID: UUID().uuidString,
                    recovery: ["Restart the provider app and register again."]
                ),
                statusCode: 503,
                reasonPhrase: "Service Unavailable"
            )
        }
        let baseURL = try await server.start()
        bridgeServer = server
        bridgeBaseURL = baseURL
        return baseURL
    }

    public func makeRegistrationRequest(
        bridgeBaseURL: URL?,
        protocolVersion: Int = 1
    ) -> BrowserRegisterProviderRequest {
        refreshSurfaceSummaries()
        return BrowserRegisterProviderRequest(
            providerID: providerID,
            displayName: displayName,
            baseURL: bridgeBaseURL?.absoluteString,
            protocolVersion: protocolVersion,
            browserSurfaces: surfaces
        )
    }

    public func connect(
        to controlPlaneBaseURL: URL,
        bridgeBaseURL requestedBridgeBaseURL: URL? = nil,
        protocolVersion: Int = 1
    ) async throws -> BrowserRegisterProviderResponse {
        self.controlPlaneBaseURL = controlPlaneBaseURL
        let resolvedBridgeBaseURL: URL
        if let requestedBridgeBaseURL {
            resolvedBridgeBaseURL = requestedBridgeBaseURL
        } else {
            resolvedBridgeBaseURL = try await startBridge()
        }
        let request = makeRegistrationRequest(
            bridgeBaseURL: resolvedBridgeBaseURL,
            protocolVersion: protocolVersion
        )
        return try await post(
            request,
            to: appendingPath("/v1/browser/providers/register", to: controlPlaneBaseURL)
        )
    }

    public func disconnect(from controlPlaneBaseURL: URL) async throws -> BrowserUnregisterProviderResponse {
        let request = BrowserUnregisterProviderRequest(providerID: providerID)
        return try await post(
            request,
            to: appendingPath("/v1/browser/providers/unregister", to: controlPlaneBaseURL)
        )
    }

    func receivePageEvent(surfaceID: String, body: [String: Any]) {
        let type = (body["type"] as? String) ?? "event"
        let scriptID = body["scriptID"] as? String
        let payload = JSONValueDTO.from(any: body["payload"])
        let event = BCUProviderPageEvent(
            providerID: providerID,
            surfaceID: surfaceID,
            type: type,
            scriptID: scriptID,
            payload: payload
        )
        pageEventHandler?(event)

        guard let controlPlaneBaseURL else { return }
        Task {
            let source: ControlPlaneEventSourceDTO = switch type {
            case "browser_console":
                .console
            case "browser_page_error", "browser_unhandled_rejection":
                .page
            default:
                .script
            }
            let request = EmitControlPlaneEventRequest(
                providerID: providerID,
                surfaceID: surfaceID,
                source: source,
                type: type,
                scriptID: scriptID,
                payload: payload
            )
            let _: EmitControlPlaneEventResponse? = try? await self.post(
                request,
                to: self.appendingPath("/v1/events/emit", to: controlPlaneBaseURL)
            )
        }
    }

    private func handleProviderRequest(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.method == .post else {
            return providerError("method_not_allowed", "Provider bridge endpoints require POST.", statusCode: 405, reasonPhrase: "Method Not Allowed")
        }

        switch request.path {
        case "/bcu/v1/browser/navigate":
            return await providerResponse(BrowserNavigateRequest.self, BrowserGetStateResponse.self, request: request) { envelope in
                try await self.navigate(envelope)
            }
        case "/bcu/v1/browser/get_state":
            return await providerResponse(BrowserGetStateRequest.self, BrowserGetStateResponse.self, request: request) { envelope in
                try await self.getState(envelope)
            }
        case "/bcu/v1/browser/resolve":
            return await providerResponse(BrowserActionTargetRequestDTO.self, BrowserInteractableDTO.self, request: request) { envelope in
                try await self.resolve(envelope)
            }
        case "/bcu/v1/browser/evaluate_js":
            return await providerResponse(BrowserEvaluateJavaScriptRequest.self, BrowserEvaluateJavaScriptResponse.self, request: request) { envelope in
                try await self.evaluateJavaScript(envelope)
            }
        case "/bcu/v1/browser/inject_js":
            return await providerResponse(BrowserInjectJavaScriptRequest.self, BrowserInjectJavaScriptResponse.self, request: request) { envelope in
                try await self.injectJavaScript(envelope)
            }
        case "/bcu/v1/browser/remove_injected_js":
            return await providerResponse(BrowserRemoveInjectedJavaScriptRequest.self, BrowserRemoveInjectedJavaScriptResponse.self, request: request) { envelope in
                try await self.removeInjectedJavaScript(envelope)
            }
        case "/bcu/v1/browser/list_injected_js":
            return await providerResponse(BrowserListInjectedJavaScriptRequest.self, BrowserListInjectedJavaScriptResponse.self, request: request) { envelope in
                try self.listInjectedJavaScript(envelope)
            }
        case "/bcu/v1/browser/click":
            return await providerResponse(BrowserClickRequest.self, BrowserActionResponse.self, request: request) { envelope in
                try await self.click(envelope)
            }
        case "/bcu/v1/browser/type_text":
            return await providerResponse(BrowserTypeTextRequest.self, BrowserActionResponse.self, request: request) { envelope in
                try await self.typeText(envelope)
            }
        case "/bcu/v1/browser/scroll":
            return await providerResponse(BrowserScrollRequest.self, BrowserActionResponse.self, request: request) { envelope in
                try await self.scroll(envelope)
            }
        case "/bcu/v1/browser/reload":
            return await providerResponse(BrowserReloadRequest.self, BrowserGetStateResponse.self, request: request) { envelope in
                try await self.reload(envelope)
            }
        case "/bcu/v1/browser/close":
            return await providerResponse(BrowserCloseRequest.self, BrowserCloseResponse.self, request: request) { envelope in
                try self.close(envelope)
            }
        default:
            return providerError("route_not_found", "No provider bridge route matched \(request.path).", statusCode: 404, reasonPhrase: "Not Found")
        }
    }

    private func providerResponse<Request: Codable & Sendable, Response: Encodable>(
        _ requestType: Request.Type,
        _ responseType: Response.Type,
        request: HTTPRequest,
        work: (BrowserProviderCommandEnvelopeDTO<Request>) async throws -> Response
    ) async -> HTTPResponse {
        do {
            let envelope = try JSONSupport.decoder.decode(BrowserProviderCommandEnvelopeDTO<Request>.self, from: request.body)
            guard envelope.providerID == providerID else {
                return providerError("provider_mismatch", "Envelope providerID '\(envelope.providerID)' does not match provider '\(providerID)'.", statusCode: 400, reasonPhrase: "Bad Request")
            }
            return .json(try await work(envelope))
        } catch {
            return providerError("provider_command_failed", "\(error)", statusCode: 500, reasonPhrase: "Internal Server Error")
        }
    }

    private func navigate(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserNavigateRequest>) async throws -> BrowserGetStateResponse {
        let surface = try surface(for: envelope.surfaceID)
        guard let url = URL(string: envelope.request.url) ?? URL(string: "https://\(envelope.request.url)") else {
            throw BCUProviderError.invalidRequest("Invalid URL '\(envelope.request.url)'.")
        }
        surface.webView.load(URLRequest(url: url))
        if envelope.request.waitUntilLoaded ?? true {
            try await waitUntilLoaded(surface.webView, timeoutMs: envelope.request.timeoutMs)
        }
        return try await getState(
            BrowserProviderCommandEnvelopeDTO(
                providerID: envelope.providerID,
                providerDisplayName: envelope.providerDisplayName,
                protocolVersion: envelope.protocolVersion,
                surfaceID: envelope.surfaceID,
                targetID: envelope.targetID,
                command: "get_state",
                request: BrowserGetStateRequest(
                    browser: envelope.request.browser,
                    maxElements: 500,
                    includeRawText: false,
                    imageMode: envelope.request.imageMode ?? .path,
                    debug: envelope.request.debug
                )
            )
        )
    }

    private func getState(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserGetStateRequest>) async throws -> BrowserGetStateResponse {
        let started = Date()
        let surface = try surface(for: envelope.surfaceID)
        let snapshotValue = try await surface.webView.callAsyncJavaScript(
            "return window.__bcu.snapshot(maxElements, includeRawText);",
            arguments: [
                "maxElements": max(1, min(envelope.request.maxElements ?? 500, 5_000)),
                "includeRawText": envelope.request.includeRawText ?? false
            ],
            in: nil,
            contentWorld: .page
        )
        let domEnded = Date()
        var snapshot: BrowserDOMSnapshotDTO = try decodeJavaScriptValue(snapshotValue)
        snapshot = BrowserDOMSnapshotDTO(
            viewport: snapshot.viewport,
            focusedElement: snapshot.focusedElement,
            interactables: snapshot.interactables.map { mapInteractableToAppKit($0, surface: surface) },
            rawText: snapshot.rawText,
            nodeCount: snapshot.nodeCount
        )
        let target = targetSummary(for: surface, targetID: envelope.targetID)
        let window = resolvedWindowDTO(for: surface)
        let stateToken = BrowserStateToken.make(target: target, window: window, dom: snapshot)
        let screenshotStarted = Date()
        let screenshot = ScreenshotCaptureService.capture(
            window: window,
            stateToken: stateToken,
            imageMode: envelope.request.imageMode ?? .path,
            includeRawRetinaCapture: envelope.request.debug == true,
            includeCursorOverlay: true
        )
        let finished = Date()
        return BrowserGetStateResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            stateToken: stateToken,
            target: target,
            screenshot: screenshot,
            dom: snapshot,
            performance: BrowserPerformanceDTO(
                resolveMs: 0,
                domMs: domEnded.timeIntervalSince(started) * 1_000,
                screenshotMs: finished.timeIntervalSince(screenshotStarted) * 1_000,
                totalMs: finished.timeIntervalSince(started) * 1_000
            ),
            warnings: [],
            notes: ["Read provider-owned WKWebView state through BCUProvider."]
        )
    }

    private func resolve(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserActionTargetRequestDTO>) async throws -> BrowserInteractableDTO {
        let surface = try surface(for: envelope.surfaceID)
        let value = try await surface.webView.callAsyncJavaScript(
            "return window.__bcu.resolve(target);",
            arguments: ["target": ["kind": envelope.request.kind.rawValue, "value": envelope.request.value]],
            in: nil,
            contentWorld: .page
        )
        let result: BCUProviderResolveResult = try decodeJavaScriptValue(value)
        guard result.ok, let element = result.element else {
            throw BCUProviderError.invalidRequest(result.message ?? result.error ?? "Provider target did not resolve.")
        }
        return mapInteractableToAppKit(element, surface: surface)
    }

    private func evaluateJavaScript(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserEvaluateJavaScriptRequest>) async throws -> BrowserEvaluateJavaScriptResponse {
        let surface = try surface(for: envelope.surfaceID)
        let value = try await surface.webView.callAsyncJavaScript(
            """
            const value = await eval(source);
            if (window.__bcu && window.__bcu.serialize) {
              return window.__bcu.serialize(value);
            }
            return value;
            """,
            arguments: ["source": envelope.request.javaScript],
            in: nil,
            contentWorld: .page
        )
        return BrowserEvaluateJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            target: targetSummary(for: surface, targetID: envelope.targetID),
            result: JSONValueDTO.from(any: value),
            resultDescription: value.map(String.init(describing:)),
            error: nil,
            notes: ["Executed JavaScript in provider-owned WKWebView surface \(envelope.surfaceID)."]
        )
    }

    private func injectJavaScript(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserInjectJavaScriptRequest>) async throws -> BrowserInjectJavaScriptResponse {
        let surface = try surface(for: envelope.surfaceID)
        let request = envelope.request
        let runAt = request.runAt ?? .documentIdle
        let dto = BrowserInjectedScriptDTO(
            scriptID: request.scriptID,
            targetID: request.browser,
            urlMatch: request.urlMatch,
            runAt: runAt,
            persistAcrossReloads: request.persistAcrossReloads ?? true,
            sourceLength: request.javaScript.count,
            installedAt: Time.iso8601String(from: Date())
        )
        surface.scripts[request.scriptID] = BCUInstalledWebScript(dto: dto, javaScript: request.javaScript)
        rebuildUserScripts(surface)

        let immediateResult: BrowserEvaluateJavaScriptResponse?
        if request.injectImmediately ?? true {
            immediateResult = try await evaluateJavaScript(
                BrowserProviderCommandEnvelopeDTO(
                    providerID: envelope.providerID,
                    providerDisplayName: envelope.providerDisplayName,
                    protocolVersion: envelope.protocolVersion,
                    surfaceID: envelope.surfaceID,
                    targetID: envelope.targetID,
                    command: "evaluate_js",
                    request: BrowserEvaluateJavaScriptRequest(
                        browser: request.browser ?? envelope.targetID,
                        javaScript: request.javaScript,
                        timeoutMs: nil,
                        debug: request.debug
                    )
                )
            )
        } else {
            immediateResult = nil
        }

        return BrowserInjectJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            script: dto,
            immediateResult: immediateResult,
            notes: ["Installed provider script '\(request.scriptID)' on surface \(envelope.surfaceID)."]
        )
    }

    private func removeInjectedJavaScript(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserRemoveInjectedJavaScriptRequest>) async throws -> BrowserRemoveInjectedJavaScriptResponse {
        let surface = try surface(for: envelope.surfaceID)
        let removed = surface.scripts.removeValue(forKey: envelope.request.scriptID) != nil
        rebuildUserScripts(surface)
        return BrowserRemoveInjectedJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            removed: removed,
            remainingScripts: surface.scripts.values.map(\.dto).sorted { $0.scriptID < $1.scriptID },
            notes: [removed ? "Removed provider script '\(envelope.request.scriptID)'." : "No provider script matched '\(envelope.request.scriptID)'."]
        )
    }

    private func listInjectedJavaScript(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserListInjectedJavaScriptRequest>) throws -> BrowserListInjectedJavaScriptResponse {
        let surface = try surface(for: envelope.surfaceID)
        return BrowserListInjectedJavaScriptResponse(
            contractVersion: ContractVersion.current,
            scripts: surface.scripts.values.map(\.dto).sorted { $0.scriptID < $1.scriptID },
            notes: ["Listed provider scripts for surface \(envelope.surfaceID)."]
        )
    }

    private func click(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserClickRequest>) async throws -> BrowserActionResponse {
        let surface = try surface(for: envelope.surfaceID)
        let request = envelope.request
        let target = request.target.map { ["kind": $0.kind.rawValue, "value": $0.value] } as Any? ?? NSNull()
        let result = try await surface.webView.callAsyncJavaScript(
            request.target == nil
                ? "return window.__bcu.clickPoint(x, y, clickCount);"
                : "return window.__bcu.click(target, clickCount);",
            arguments: [
                "target": target,
                "x": request.x ?? 0,
                "y": request.y ?? 0,
                "clickCount": max(1, min(request.clickCount ?? 1, 2))
            ],
            in: nil,
            contentWorld: .page
        )
        return try await actionResponse(
            envelope: envelope,
            ok: jsonIndicatesSuccess(JSONValueDTO.from(any: result)),
            summary: "Provider click dispatched through DOM events.",
            requestedTarget: request.target,
            dispatchResult: JSONValueDTO.from(any: result),
            imageMode: request.imageMode,
            debug: request.debug
        )
    }

    private func typeText(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserTypeTextRequest>) async throws -> BrowserActionResponse {
        let surface = try surface(for: envelope.surfaceID)
        let request = envelope.request
        let target = request.target.map { ["kind": $0.kind.rawValue, "value": $0.value] } as Any? ?? NSNull()
        let result = try await surface.webView.callAsyncJavaScript(
            "return window.__bcu.typeText(target, text, append);",
            arguments: [
                "target": target,
                "text": request.text,
                "append": request.append ?? false
            ],
            in: nil,
            contentWorld: .page
        )
        return try await actionResponse(
            envelope: envelope,
            ok: jsonIndicatesSuccess(JSONValueDTO.from(any: result)),
            summary: "Provider type_text dispatched through DOM input events.",
            requestedTarget: request.target,
            dispatchResult: JSONValueDTO.from(any: result),
            imageMode: request.imageMode,
            debug: request.debug
        )
    }

    private func scroll(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserScrollRequest>) async throws -> BrowserActionResponse {
        let surface = try surface(for: envelope.surfaceID)
        let request = envelope.request
        let target = request.target.map { ["kind": $0.kind.rawValue, "value": $0.value] } as Any? ?? NSNull()
        let result = try await surface.webView.callAsyncJavaScript(
            "return window.__bcu.scroll(target, direction, pages);",
            arguments: [
                "target": target,
                "direction": request.direction.rawValue,
                "pages": max(1, min(request.pages ?? 1, 10))
            ],
            in: nil,
            contentWorld: .page
        )
        return try await actionResponse(
            envelope: envelope,
            ok: jsonIndicatesSuccess(JSONValueDTO.from(any: result)),
            summary: "Provider scroll dispatched through DOM scroll primitives.",
            requestedTarget: request.target,
            dispatchResult: JSONValueDTO.from(any: result),
            imageMode: request.imageMode,
            debug: request.debug
        )
    }

    private func reload(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserReloadRequest>) async throws -> BrowserGetStateResponse {
        let surface = try surface(for: envelope.surfaceID)
        surface.webView.reload()
        if envelope.request.waitUntilLoaded ?? true {
            try await waitUntilLoaded(surface.webView, timeoutMs: envelope.request.timeoutMs)
        }
        return try await getState(
            BrowserProviderCommandEnvelopeDTO(
                providerID: envelope.providerID,
                providerDisplayName: envelope.providerDisplayName,
                protocolVersion: envelope.protocolVersion,
                surfaceID: envelope.surfaceID,
                targetID: envelope.targetID,
                command: "get_state",
                request: BrowserGetStateRequest(
                    browser: envelope.request.browser,
                    maxElements: 500,
                    includeRawText: false,
                    imageMode: envelope.request.imageMode ?? .path,
                    debug: envelope.request.debug
                )
            )
        )
    }

    private func close(_ envelope: BrowserProviderCommandEnvelopeDTO<BrowserCloseRequest>) throws -> BrowserCloseResponse {
        let surface = try surface(for: envelope.surfaceID)
        surface.webView.window?.close()
        return BrowserCloseResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            closed: true,
            notes: ["Closed provider host window for surface \(envelope.surfaceID)."]
        )
    }

    private func actionResponse<Request: Codable & Sendable>(
        envelope: BrowserProviderCommandEnvelopeDTO<Request>,
        ok: Bool,
        summary: String,
        requestedTarget: BrowserActionTargetRequestDTO?,
        dispatchResult: JSONValueDTO,
        imageMode: ImageMode?,
        debug: Bool?
    ) async throws -> BrowserActionResponse {
        let state = try await getState(
            BrowserProviderCommandEnvelopeDTO(
                providerID: envelope.providerID,
                providerDisplayName: envelope.providerDisplayName,
                protocolVersion: envelope.protocolVersion,
                surfaceID: envelope.surfaceID,
                targetID: envelope.targetID,
                command: "get_state",
                request: BrowserGetStateRequest(
                    browser: envelope.targetID,
                    maxElements: 500,
                    includeRawText: false,
                    imageMode: imageMode ?? .path,
                    debug: debug
                )
            )
        )
        return BrowserActionResponse(
            contractVersion: ContractVersion.current,
            ok: ok,
            classification: ok ? .success : .effectNotVerified,
            failureDomain: ok ? nil : .transport,
            summary: summary,
            target: state.target,
            requestedTarget: requestedTarget,
            preStateToken: nil,
            postStateToken: state.stateToken,
            cursor: disabledCursor(),
            screenshot: state.screenshot,
            warnings: [],
            notes: ["Provider-owned surface dispatched the action locally; BCU central route still owns target selection and event flow."],
            debug: BrowserActionDebugDTO(
                resolvedRectViewport: nil,
                resolvedCenterViewport: nil,
                resolvedRectAppKit: nil,
                resolvedCenterAppKit: nil,
                hostWindowFrameAppKit: resolvedWindowDTO(for: try surface(for: envelope.surfaceID)).frameAppKit,
                cursorPositionBeforeAppKit: nil,
                dispatchResult: dispatchResult
            )
        )
    }

    private func disabledCursor() -> ActionCursorTargetResponseDTO {
        ActionCursorTargetResponseDTO(
            session: CursorResponseDTO(id: "provider", name: "Provider", color: "#4B8BFF", reused: true),
            targetPointAppKit: nil,
            targetPointSource: nil,
            moved: false,
            moveDurationMs: nil,
            movement: "provider_dispatched_without_local_cursor",
            warnings: []
        )
    }

    private func refreshSurfaceSummaries() {
        surfaces = webSurfaces.values
            .map { surface in
                BrowserRegisteredProviderSurfaceDTO(
                    surfaceID: surface.surfaceID,
                    title: surface.explicitTitle ?? surface.webView.title ?? surface.webView.window?.title ?? surface.surfaceID,
                    url: surface.explicitURL ?? surface.webView.url?.absoluteString,
                    hostWindow: surface.explicitHostWindow ?? Self.hostWindowDTO(for: surface.webView),
                    capabilities: surface.capabilities
                )
            }
            .sorted { $0.surfaceID < $1.surfaceID }
    }

    private func surface(for surfaceID: String) throws -> BCURegisteredWebViewSurface {
        guard let surface = webSurfaces[surfaceID] else {
            throw BCUProviderError.invalidRequest("No provider surface matched '\(surfaceID)'.")
        }
        return surface
    }

    private func targetSummary(for surface: BCURegisteredWebViewSurface, targetID: String) -> BrowserTargetSummaryDTO {
        BrowserTargetSummaryDTO(
            targetID: targetID,
            kind: .registeredBrowserSurface,
            ownerApp: displayName,
            title: surface.explicitTitle ?? surface.webView.title ?? surface.webView.window?.title ?? surface.surfaceID,
            url: surface.explicitURL ?? surface.webView.url?.absoluteString,
            isLoading: surface.webView.isLoading,
            parentTargetID: nil,
            hostWindow: surface.explicitHostWindow ?? Self.hostWindowDTO(for: surface.webView),
            capabilities: surface.capabilities
        )
    }

    private func resolvedWindowDTO(for surface: BCURegisteredWebViewSurface) -> ResolvedWindowDTO {
        let window = surface.webView.window
        let frame = window?.frame ?? surface.webView.frame
        let windowNumber = window?.windowNumber ?? 0
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let launchDate = NSRunningApplication.current.launchDate
        let windowID = WindowID.make(
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate,
            windowNumber: windowNumber
        )
        return ResolvedWindowDTO(
            windowID: windowID,
            title: window?.title ?? surface.surfaceID,
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate.map(Time.iso8601String),
            windowNumber: windowNumber,
            frameAppKit: RectDTO(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
            resolutionStrategy: "provider_wkwebview"
        )
    }

    private func mapInteractableToAppKit(_ interactable: BrowserInteractableDTO, surface: BCURegisteredWebViewSurface) -> BrowserInteractableDTO {
        let rectAppKit = viewportRectToAppKit(interactable.rectViewport, surface: surface)
        let centerAppKit = viewportPointToAppKit(interactable.centerViewport, surface: surface)
        return BrowserInteractableDTO(
            displayIndex: interactable.displayIndex,
            nodeID: interactable.nodeID,
            role: interactable.role,
            tagName: interactable.tagName,
            text: interactable.text,
            accessibleName: interactable.accessibleName,
            valuePreview: interactable.valuePreview,
            selectorCandidates: interactable.selectorCandidates,
            rectViewport: interactable.rectViewport,
            centerViewport: interactable.centerViewport,
            rectAppKit: RectDTO(x: rectAppKit.minX, y: rectAppKit.minY, width: rectAppKit.width, height: rectAppKit.height),
            centerAppKit: PointDTO(x: centerAppKit.x, y: centerAppKit.y),
            isVisible: interactable.isVisible,
            isEnabled: interactable.isEnabled,
            isEditable: interactable.isEditable
        )
    }

    private func viewportPointToAppKit(_ point: PointDTO, surface: BCURegisteredWebViewSurface) -> CGPoint {
        BrowserWebViewGeometry.appKitPoint(forViewportPoint: point, in: surface.webView)
    }

    private func viewportRectToAppKit(_ rect: RectDTO, surface: BCURegisteredWebViewSurface) -> CGRect {
        BrowserWebViewGeometry.appKitRect(forViewportRect: rect, in: surface.webView)
    }

    private func rebuildUserScripts(_ surface: BCURegisteredWebViewSurface) {
        let controller = surface.webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(
                source: BrowserBootstrapScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        for script in surface.scripts.values.sorted(by: { $0.dto.scriptID < $1.dto.scriptID }) where script.dto.persistAcrossReloads {
            controller.addUserScript(
                WKUserScript(
                    source: script.javaScript,
                    injectionTime: injectionTime(for: script.dto.runAt),
                    forMainFrameOnly: false
                )
            )
        }
    }

    private func injectionTime(for runAt: BrowserScriptRunAtDTO) -> WKUserScriptInjectionTime {
        switch runAt {
        case .documentStart:
            return .atDocumentStart
        case .documentEnd, .documentIdle:
            return .atDocumentEnd
        }
    }

    private func waitUntilLoaded(_ webView: WKWebView, timeoutMs: Int?) async throws {
        let timeout = TimeInterval(max(100, timeoutMs ?? 8_000)) / 1_000
        let start = Date()
        while webView.isLoading {
            if Date().timeIntervalSince(start) > timeout {
                throw BCUProviderError.invalidRequest("Timed out waiting for provider webview to finish loading.")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func decodeJavaScriptValue<T: Decodable>(_ value: Any?) throws -> T {
        let jsonValue = JSONValueDTO.from(any: value)
        let data = try JSONSupport.encoder.encode(jsonValue)
        return try JSONSupport.decoder.decode(T.self, from: data)
    }

    private func jsonIndicatesSuccess(_ value: JSONValueDTO) -> Bool {
        guard case .object(let object) = value,
              case .bool(let ok)? = object["ok"] else {
            return true
        }
        return ok
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ request: Request,
        to url: URL
    ) async throws -> Response {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONSupport.encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let preview = String(data: data.prefix(1_000), encoding: .utf8) ?? "<non-utf8 body>"
            throw BCUProviderError.requestFailed(statusCode: statusCode, bodyPreview: preview)
        }
        return try JSONSupport.decoder.decode(Response.self, from: data)
    }

    private func appendingPath(_ path: String, to baseURL: URL) -> URL {
        path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    private static func hostWindowDTO(for webView: WKWebView) -> BrowserHostWindowDTO? {
        guard let window = webView.window else { return nil }
        let frame = window.frame
        return BrowserHostWindowDTO(
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            pid: getpid(),
            windowNumber: window.windowNumber,
            windowID: nil,
            title: window.title,
            frameAppKit: RectDTO(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        )
    }

    private func providerError(
        _ code: String,
        _ message: String,
        statusCode: Int,
        reasonPhrase: String
    ) -> HTTPResponse {
        .json(
            ErrorResponse(
                error: code,
                message: message,
                requestID: UUID().uuidString,
                recovery: ["Check the provider bridge route, envelope, and registered surfaceID."]
            ),
            statusCode: statusCode,
            reasonPhrase: reasonPhrase
        )
    }
}

public enum BCUProviderError: Error, Sendable, CustomStringConvertible {
    case requestFailed(statusCode: Int, bodyPreview: String)
    case invalidRequest(String)

    public var description: String {
        switch self {
        case .requestFailed(let statusCode, let bodyPreview):
            return "Provider request failed with HTTP \(statusCode): \(bodyPreview)"
        case .invalidRequest(let message):
            return message
        }
    }
}

public extension BrowserTargetCapabilitiesDTO {
    static let defaultProviderWebView = BrowserTargetCapabilitiesDTO(
        readDom: true,
        evaluateJavaScript: true,
        injectJavaScript: true,
        emitPageEvents: true,
        dispatchDomEvents: true,
        nativeClickFallback: false,
        screenshot: true,
        hostWindowMetadata: true
    )
}

private final class BCURegisteredWebViewSurface {
    let surfaceID: String
    let explicitTitle: String?
    let explicitURL: String?
    let explicitHostWindow: BrowserHostWindowDTO?
    let capabilities: BrowserTargetCapabilitiesDTO
    let webView: WKWebView
    let messageHandler: BCUWebSurfaceMessageHandler
    var scripts: [String: BCUInstalledWebScript] = [:]

    init(
        surfaceID: String,
        explicitTitle: String?,
        explicitURL: String?,
        explicitHostWindow: BrowserHostWindowDTO?,
        capabilities: BrowserTargetCapabilitiesDTO,
        webView: WKWebView,
        messageHandler: BCUWebSurfaceMessageHandler
    ) {
        self.surfaceID = surfaceID
        self.explicitTitle = explicitTitle
        self.explicitURL = explicitURL
        self.explicitHostWindow = explicitHostWindow
        self.capabilities = capabilities
        self.webView = webView
        self.messageHandler = messageHandler
    }
}

private struct BCUInstalledWebScript {
    let dto: BrowserInjectedScriptDTO
    let javaScript: String
}

private struct BCUProviderResolveResult: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let message: String?
    let element: BrowserInteractableDTO?
}

private final class BCUWebSurfaceMessageHandler: NSObject, WKScriptMessageHandler {
    weak var provider: BCUProvider?
    let surfaceID: String

    init(provider: BCUProvider, surfaceID: String) {
        self.provider = provider
        self.surfaceID = surfaceID
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bcu",
              let body = message.body as? [String: Any],
              body["kind"] as? String == "event" else {
            return
        }
        Task { @MainActor [weak provider, surfaceID] in
            provider?.receivePageEvent(surfaceID: surfaceID, body: body)
        }
    }
}

private final class BCUProviderBridgeServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "BackgroundComputerUse.ProviderBridge", qos: .userInitiated, attributes: .concurrent)
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private var listener: NWListener?
    private(set) var baseURL: URL?

    init(handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.handler = handler
    }

    func start() async throws -> URL {
        if let baseURL {
            return baseURL
        }
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            let gate = BCUProviderResumeGate()
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let port = listener.port else { return }
                    let baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)")!
                    self?.baseURL = baseURL
                    gate.resumeIfNeeded {
                        continuation.resume(returning: baseURL)
                    }
                case .failed(let error):
                    gate.resumeIfNeeded {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func handle(connection: NWConnection) {
        let connectionQueue = DispatchQueue(label: "BackgroundComputerUse.ProviderBridge.Connection.\(UUID().uuidString)", qos: .userInitiated)
        connection.start(queue: connectionQueue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var updatedBuffer = buffer
            if let data {
                updatedBuffer.append(data)
            }
            if error != nil {
                self.send(.text("Provider bridge failed to read request.", statusCode: 400, reasonPhrase: "Bad Request"), on: connection)
                return
            }
            switch HTTPRequest.parse(updatedBuffer) {
            case .complete(let request):
                Task {
                    let response = await self.handler(request)
                    self.send(response, on: connection)
                }
            case .incomplete:
                guard isComplete == false else {
                    self.send(.text("Incomplete provider request.", statusCode: 400, reasonPhrase: "Bad Request"), on: connection)
                    return
                }
                self.receiveRequest(on: connection, buffer: updatedBuffer)
            case .invalid:
                self.send(.text("Invalid provider request.", statusCode: 400, reasonPhrase: "Bad Request"), on: connection)
            case .tooLarge:
                self.send(.text("Provider request too large.", statusCode: 413, reasonPhrase: "Payload Too Large"), on: connection)
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private final class BCUProviderResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resumeIfNeeded(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard resumed == false else { return }
        resumed = true
        body()
    }
}
