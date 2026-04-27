import AppKit
import Foundation
@preconcurrency import WebKit

private struct InstalledBrowserScript {
    let dto: BrowserInjectedScriptDTO
    let javaScript: String
}

private struct RegisteredBrowserProvider {
    let providerID: String
    let displayName: String
    let baseURL: String?
    let protocolVersion: Int
    let targets: [BrowserTargetSummaryDTO]
}

private struct BrowserResolveResult: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let message: String?
    let element: BrowserInteractableDTO?
    let candidates: [BrowserInteractableDTO]?
}

@MainActor
final class BrowserSurfaceRegistry {
    static let shared = BrowserSurfaceRegistry()

    private var ownedSurfacesByWindowID: [String: OwnedBrowserSurface] = [:]
    private var ownedSurfacesByTabID: [String: OwnedBrowserSurface] = [:]
    private var ownedSurfacesByHostWindowID: [String: OwnedBrowserSurface] = [:]
    private var registeredProviders: [String: RegisteredBrowserProvider] = [:]
    private var registeredTargets: [String: BrowserTargetSummaryDTO] = [:]

    private init() {}

    func createWindow(request: BrowserCreateWindowRequest) throws -> OwnedBrowserSurface {
        let surface = try OwnedBrowserSurface(request: request)
        ownedSurfacesByWindowID[surface.windowTargetID] = surface
        ownedSurfacesByTabID[surface.tabTargetID] = surface
        ownedSurfacesByHostWindowID[surface.hostWindowID()] = surface
        return surface
    }

    func listTargets(includeRegistered: Bool = true) -> [BrowserTargetSummaryDTO] {
        let owned = ownedSurfacesByTabID.values
            .sorted { $0.tabTargetID < $1.tabTargetID }
            .flatMap { [$0.windowSummary(), $0.tabSummary()] }
        guard includeRegistered else {
            return owned
        }
        return owned + registeredTargets.values.sorted { $0.targetID < $1.targetID }
    }

    func ownedSurface(for targetID: String) throws -> OwnedBrowserSurface {
        if let surface = ownedSurfacesByTabID[targetID] ?? ownedSurfacesByWindowID[targetID] {
            return surface
        }
        if registeredTargets[targetID] != nil {
            throw BrowserSurfaceError.unsupportedRegisteredProvider(targetID)
        }
        throw BrowserSurfaceError.targetNotFound(targetID)
    }

    func summary(for targetID: String) throws -> BrowserTargetSummaryDTO {
        if let surface = ownedSurfacesByTabID[targetID] ?? ownedSurfacesByWindowID[targetID] {
            return targetID == surface.windowTargetID ? surface.windowSummary() : surface.tabSummary()
        }
        if let target = registeredTargets[targetID] {
            return target
        }
        throw BrowserSurfaceError.targetNotFound(targetID)
    }

    func close(targetID: String) throws -> Bool {
        let surface = try ownedSurface(for: targetID)
        ownedSurfacesByWindowID.removeValue(forKey: surface.windowTargetID)
        ownedSurfacesByTabID.removeValue(forKey: surface.tabTargetID)
        ownedSurfacesByHostWindowID.removeValue(forKey: surface.hostWindowID())
        surface.close()
        return true
    }

    func setOwnedHostWindowFrame(
        windowID: String,
        frame: CGRect,
        animate: Bool
    ) -> (before: ResolvedWindowDTO, after: ResolvedWindowDTO)? {
        let surface = ownedSurfacesByHostWindowID[windowID] ?? ownedSurfacesByTabID.values.first {
            $0.hostWindowID() == windowID
        }
        guard let surface else {
            return nil
        }
        ownedSurfacesByHostWindowID[surface.hostWindowID()] = surface
        let before = surface.resolvedWindowDTO()
        surface.setHostFrame(frame, animate: animate)
        let after = surface.resolvedWindowDTO()
        ownedSurfacesByHostWindowID[after.windowID] = surface
        return (before, after)
    }

    func registerProvider(request: BrowserRegisterProviderRequest) throws -> BrowserRegisterProviderResponse {
        guard request.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw BrowserSurfaceError.invalidRequest("providerID must be non-empty.")
        }
        guard request.protocolVersion >= 1 else {
            throw BrowserSurfaceError.invalidRequest("protocolVersion must be at least 1.")
        }

        let targets = request.browserSurfaces.map { surface in
            BrowserTargetSummaryDTO(
                targetID: registeredTargetID(providerID: request.providerID, surfaceID: surface.surfaceID),
                kind: .registeredBrowserSurface,
                ownerApp: request.displayName,
                title: surface.title,
                url: surface.url,
                isLoading: false,
                parentTargetID: nil,
                hostWindow: surface.hostWindow,
                capabilities: surface.capabilities
            )
        }

        let existingTargetIDs = Set(registeredProviders[request.providerID]?.targets.map(\.targetID) ?? [])
        for targetID in existingTargetIDs {
            registeredTargets.removeValue(forKey: targetID)
        }

        let provider = RegisteredBrowserProvider(
            providerID: request.providerID,
            displayName: request.displayName,
            baseURL: request.baseURL,
            protocolVersion: request.protocolVersion,
            targets: targets
        )
        registeredProviders[request.providerID] = provider
        for target in targets {
            registeredTargets[target.targetID] = target
        }

        return BrowserRegisterProviderResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            providerID: request.providerID,
            targets: targets,
            notes: [
                "Registered browser surfaces are discoverable through /v1/browser/list_targets.",
                "This runtime records provider metadata; control calls require a provider bridge that implements the browser-provider protocol."
            ]
        )
    }

    func unregisterProvider(request: BrowserUnregisterProviderRequest) -> BrowserUnregisterProviderResponse {
        let provider = registeredProviders.removeValue(forKey: request.providerID)
        let targetIDs = Set(provider?.targets.map(\.targetID) ?? [])
        let before = registeredTargets.count
        registeredTargets = registeredTargets.filter { targetIDs.contains($0.key) == false }
        let removed = before - registeredTargets.count
        return BrowserUnregisterProviderResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            removedTargetCount: removed,
            notes: ["Unregistered provider '\(request.providerID)'."]
        )
    }

    private func registeredTargetID(providerID: String, surfaceID: String) -> String {
        let raw = "\(providerID)-\(surfaceID)"
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
        return "rb_\(String(raw).prefix(56))"
    }
}

@MainActor
final class OwnedBrowserSurface: NSObject, @unchecked Sendable, WKNavigationDelegate, WKScriptMessageHandler, NSToolbarDelegate, NSTextFieldDelegate {
    let windowTargetID: String
    let tabTargetID: String

    private let window: NSWindow
    private let webView: WKWebView
    private var scripts: [String: InstalledBrowserScript] = [:]
    private var urlField: NSTextField?
    private var statusItem: NSToolbarItem?
    private var lastNavigationError: String?

    init(request: BrowserCreateWindowRequest) throws {
        windowTargetID = "bw_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        tabTargetID = "bt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"

        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.addUserScript(
            WKUserScript(
                source: BrowserBootstrapScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController = userContentController
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let initialFrame = NSRect(
            x: request.x ?? 120,
            y: request.y ?? 120,
            width: max(request.width ?? 1120, 420),
            height: max(request.height ?? 760, 320)
        )
        window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        userContentController.add(self, name: "bcu")
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.autoresizingMask = [.width, .height]

        window.title = request.title ?? "Browser Surface"
        window.contentView = webView
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.toolbar = makeToolbar()
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        if request.activate ?? true {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        rememberHostWindow()

        if let rawURL = request.url, rawURL.isEmpty == false {
            try navigate(rawURL)
        } else {
            webView.loadHTMLString(defaultHTML, baseURL: nil)
        }
        updateToolbarState()
    }

    func windowSummary() -> BrowserTargetSummaryDTO {
        BrowserTargetSummaryDTO(
            targetID: windowTargetID,
            kind: .ownedBrowserWindow,
            ownerApp: "BackgroundComputerUse",
            title: window.title,
            url: webView.url?.absoluteString,
            isLoading: webView.isLoading,
            parentTargetID: nil,
            hostWindow: hostWindowDTO(),
            capabilities: ownedCapabilities
        )
    }

    func tabSummary() -> BrowserTargetSummaryDTO {
        BrowserTargetSummaryDTO(
            targetID: tabTargetID,
            kind: .ownedBrowserTab,
            ownerApp: "BackgroundComputerUse",
            title: webView.title ?? window.title,
            url: webView.url?.absoluteString,
            isLoading: webView.isLoading,
            parentTargetID: windowTargetID,
            hostWindow: hostWindowDTO(),
            capabilities: ownedCapabilities
        )
    }

    func navigate(_ rawURL: String) throws {
        let url = try normalizedURL(rawURL)
        urlField?.stringValue = url.absoluteString
        webView.load(URLRequest(url: url))
        updateToolbarState()
    }

    func reload() {
        webView.reload()
        updateToolbarState()
    }

    func close() {
        window.close()
    }

    func waitUntilLoaded(timeoutMs: Int?) async throws {
        let timeout = TimeInterval(max(100, timeoutMs ?? 8_000)) / 1_000
        let start = Date()
        while webView.isLoading {
            if Date().timeIntervalSince(start) > timeout {
                throw BrowserSurfaceError.timedOut("Timed out waiting for browser target \(tabTargetID) to finish loading.")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func evaluateJavaScript(_ source: String) async throws -> BrowserEvaluateJavaScriptResponse {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            """
            const value = await eval(source);
            if (window.__bcu && window.__bcu.serialize) {
              return window.__bcu.serialize(value);
            }
            return value;
            """,
            arguments: ["source": source],
            in: nil,
            contentWorld: .page
        )
        return BrowserEvaluateJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            target: tabSummary(),
            result: JSONValueDTO.from(any: value),
            resultDescription: value.map(String.init(describing:)),
            error: nil,
            notes: ["Executed JavaScript in owned WKWebView target \(tabTargetID)."]
        )
    }

    func installScript(request: BrowserInjectJavaScriptRequest) async throws -> BrowserInjectJavaScriptResponse {
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
        scripts[request.scriptID] = InstalledBrowserScript(dto: dto, javaScript: request.javaScript)
        rebuildUserScripts()

        let immediateResult: BrowserEvaluateJavaScriptResponse?
        if request.injectImmediately ?? true {
            immediateResult = try await evaluateJavaScript(request.javaScript)
        } else {
            immediateResult = nil
        }

        return BrowserInjectJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            script: dto,
            immediateResult: immediateResult,
            notes: [
                "Installed script '\(request.scriptID)' for owned browser target \(tabTargetID).",
                "document_start scripts run on the next navigation/reload; injectImmediately also evaluates the source in the current page."
            ]
        )
    }

    func removeScript(scriptID: String) -> BrowserRemoveInjectedJavaScriptResponse {
        let removed = scripts.removeValue(forKey: scriptID) != nil
        rebuildUserScripts()
        return BrowserRemoveInjectedJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            removed: removed,
            remainingScripts: listScripts(),
            notes: [removed ? "Removed injected script '\(scriptID)'." : "No injected script matched '\(scriptID)'."]
        )
    }

    func listScripts() -> [BrowserInjectedScriptDTO] {
        scripts.values
            .map(\.dto)
            .sorted { $0.scriptID < $1.scriptID }
    }

    func snapshot(maxElements: Int?, includeRawText: Bool?) async throws -> BrowserDOMSnapshotDTO {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.snapshot(maxElements, includeRawText);",
            arguments: [
                "maxElements": max(1, min(maxElements ?? 500, 5_000)),
                "includeRawText": includeRawText ?? false
            ],
            in: nil,
            contentWorld: .page
        )
        var snapshot: BrowserDOMSnapshotDTO = try decodeJavaScriptValue(value)
        snapshot = BrowserDOMSnapshotDTO(
            viewport: snapshot.viewport,
            focusedElement: snapshot.focusedElement,
            interactables: snapshot.interactables.map(mapInteractableToAppKit),
            rawText: snapshot.rawText,
            nodeCount: snapshot.nodeCount
        )
        return snapshot
    }

    func resolve(target: BrowserActionTargetRequestDTO) async throws -> BrowserInteractableDTO {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.resolve(target);",
            arguments: ["target": ["kind": target.kind.rawValue, "value": target.value]],
            in: nil,
            contentWorld: .page
        )
        let result: BrowserResolveResult = try decodeJavaScriptValue(value)
        guard result.ok, let element = result.element else {
            if result.error == "ambiguous_target" {
                throw BrowserSurfaceError.targetAmbiguous(result.message ?? "Browser target was ambiguous.")
            }
            throw BrowserSurfaceError.invalidRequest(result.message ?? result.error ?? "Browser target did not resolve.")
        }
        return mapInteractableToAppKit(element)
    }

    func dispatchClick(target: BrowserActionTargetRequestDTO, clickCount: Int) async throws -> JSONValueDTO {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.click(target, clickCount);",
            arguments: [
                "target": ["kind": target.kind.rawValue, "value": target.value],
                "clickCount": max(1, min(clickCount, 2))
            ],
            in: nil,
            contentWorld: .page
        )
        return JSONValueDTO.from(any: value)
    }

    func dispatchClickPoint(point: PointDTO, clickCount: Int) async throws -> JSONValueDTO {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.clickPoint(x, y, clickCount);",
            arguments: [
                "x": point.x,
                "y": point.y,
                "clickCount": max(1, min(clickCount, 2))
            ],
            in: nil,
            contentWorld: .page
        )
        return JSONValueDTO.from(any: value)
    }

    func dispatchTypeText(target: BrowserActionTargetRequestDTO?, text: String, append: Bool) async throws -> JSONValueDTO {
        try await ensureBootstrap()
        let encodedTarget: Any = target.map { ["kind": $0.kind.rawValue, "value": $0.value] } ?? NSNull()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.typeText(target, text, append);",
            arguments: [
                "target": encodedTarget,
                "text": text,
                "append": append
            ],
            in: nil,
            contentWorld: .page
        )
        return JSONValueDTO.from(any: value)
    }

    func dispatchScroll(target: BrowserActionTargetRequestDTO?, direction: ScrollDirectionDTO, pages: Int) async throws -> JSONValueDTO {
        try await ensureBootstrap()
        let encodedTarget: Any = target.map { ["kind": $0.kind.rawValue, "value": $0.value] } ?? NSNull()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.scroll(target, direction, pages);",
            arguments: [
                "target": encodedTarget,
                "direction": direction.rawValue,
                "pages": max(1, min(pages, 10))
            ],
            in: nil,
            contentWorld: .page
        )
        return JSONValueDTO.from(any: value)
    }

    func viewportPointToAppKit(_ point: PointDTO) -> CGPoint {
        let viewportWidth = max(webView.bounds.width, 1)
        let viewportHeight = max(webView.bounds.height, 1)
        let localPoint = NSPoint(
            x: CGFloat(point.x) * viewportWidth / max(viewportWidth, 1),
            y: viewportHeight - (CGFloat(point.y) * viewportHeight / max(viewportHeight, 1))
        )
        let windowPoint = webView.convert(localPoint, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

    func viewportRectToAppKit(_ rect: RectDTO) -> CGRect {
        let topLeft = viewportPointToAppKit(PointDTO(x: rect.x, y: rect.y))
        let bottomRight = viewportPointToAppKit(PointDTO(x: rect.x + rect.width, y: rect.y + rect.height))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    func resolvedWindowDTO() -> ResolvedWindowDTO {
        let frame = window.frame
        let bundleID = Bundle.main.bundleIdentifier ?? "xyz.dubdub.backgroundcomputeruse"
        let launchDate = NSRunningApplication.current.launchDate
        let windowID = WindowID.make(
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate,
            windowNumber: window.windowNumber
        )
        WindowTargetCache.shared.remember(
            windowID: windowID,
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate,
            windowNumber: window.windowNumber,
            title: window.title
        )
        return ResolvedWindowDTO(
            windowID: windowID,
            title: window.title,
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate.map(Time.iso8601String),
            windowNumber: window.windowNumber,
            frameAppKit: RectDTO(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
            resolutionStrategy: "owned_browser_window"
        )
    }

    func hostWindowID() -> String {
        resolvedWindowDTO().windowID
    }

    func setHostFrame(_ frame: CGRect, animate: Bool) {
        window.setFrame(frame, display: true, animate: animate)
        rememberHostWindow()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bcu",
              let body = message.body as? [String: Any],
              body["kind"] as? String == "event" else {
            return
        }

        let type = (body["type"] as? String) ?? "event"
        let scriptID = body["scriptID"] as? String
        let payload = JSONValueDTO.from(any: body["payload"])
        BrowserEventStore.shared.emit(
            targetID: tabTargetID,
            scriptID: scriptID,
            type: type,
            payload: payload
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastNavigationError = nil
        updateToolbarState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        lastNavigationError = error.localizedDescription
        updateToolbarState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        lastNavigationError = error.localizedDescription
        updateToolbarState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateToolbarState()
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .browserBack:
            return buttonItem(identifier: itemIdentifier, symbol: "chevron.left", label: "Back", action: #selector(goBack))
        case .browserForward:
            return buttonItem(identifier: itemIdentifier, symbol: "chevron.right", label: "Forward", action: #selector(goForward))
        case .browserReload:
            return buttonItem(identifier: itemIdentifier, symbol: "arrow.clockwise", label: "Reload", action: #selector(reloadFromToolbar))
        case .browserURL:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let field = NSTextField(string: webView.url?.absoluteString ?? "")
            field.placeholderString = "Enter URL"
            field.delegate = self
            field.target = self
            field.action = #selector(navigateFromToolbar)
            field.controlSize = .regular
            field.bezelStyle = .roundedBezel
            field.lineBreakMode = .byTruncatingMiddle
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
            item.view = field
            item.label = "URL"
            item.paletteLabel = "URL"
            urlField = field
            return item
        case .browserStatus:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Status"
            item.paletteLabel = "Status"
            item.view = NSProgressIndicator()
            statusItem = item
            return item
        default:
            return nil
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.browserBack, .browserForward, .browserReload, .flexibleSpace, .browserURL, .browserStatus]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.browserBack, .browserForward, .browserReload, .browserURL, .browserStatus]
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        navigateFromToolbar()
    }

    @objc private func navigateFromToolbar() {
        guard let rawURL = urlField?.stringValue, rawURL.isEmpty == false else { return }
        try? navigate(rawURL)
    }

    @objc private func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    @objc private func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    @objc private func reloadFromToolbar() {
        reload()
    }

    private var ownedCapabilities: BrowserTargetCapabilitiesDTO {
        BrowserTargetCapabilitiesDTO(
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

    private func hostWindowDTO() -> BrowserHostWindowDTO {
        let resolved = resolvedWindowDTO()
        return BrowserHostWindowDTO(
            bundleID: resolved.bundleID,
            pid: resolved.pid,
            windowNumber: resolved.windowNumber,
            windowID: resolved.windowID,
            title: resolved.title,
            frameAppKit: resolved.frameAppKit
        )
    }

    private func rememberHostWindow() {
        _ = resolvedWindowDTO()
    }

    private func ensureBootstrap() async throws {
        let value = try await webView.callAsyncJavaScript(
            """
            if (!window.__bcu || window.__bcu.version !== 1) {
              return false;
            }
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard (value as? Bool) == true else {
            throw BrowserSurfaceError.javascriptFailed("BCU browser bootstrap script is not available in the page.")
        }
    }

    private func rebuildUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(
                source: BrowserBootstrapScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        for script in scripts.values.sorted(by: { $0.dto.scriptID < $1.dto.scriptID }) where script.dto.persistAcrossReloads {
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

    private func mapInteractableToAppKit(_ interactable: BrowserInteractableDTO) -> BrowserInteractableDTO {
        let rectAppKit = viewportRectToAppKit(interactable.rectViewport)
        let centerAppKit = viewportPointToAppKit(interactable.centerViewport)
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

    private func decodeJavaScriptValue<T: Decodable>(_ value: Any?) throws -> T {
        let jsonValue = JSONValueDTO.from(any: value)
        let data = try JSONSupport.encoder.encode(jsonValue)
        return try JSONSupport.decoder.decode(T.self, from: data)
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "BrowserSurfaceToolbar.\(tabTargetID)")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    private func buttonItem(
        identifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        item.view = button
        return item
    }

    private func updateToolbarState() {
        window.title = webView.title ?? "Browser Surface"
        urlField?.stringValue = webView.url?.absoluteString ?? urlField?.stringValue ?? ""
        if let indicator = statusItem?.view as? NSProgressIndicator {
            if webView.isLoading {
                indicator.style = .spinning
                indicator.startAnimation(nil)
            } else {
                indicator.stopAnimation(nil)
                indicator.isHidden = lastNavigationError == nil
            }
        }
    }

    private func normalizedURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "about:blank" {
            return URL(string: "about:blank")!
        }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if let url = URL(string: "https://\(trimmed)") {
            return url
        }
        throw BrowserSurfaceError.invalidURL(raw)
    }

    private var defaultHTML: String {
        """
        <!doctype html>
        <meta charset="utf-8">
        <title>Browser Surface</title>
        <style>
        html, body { margin: 0; height: 100%; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; color: #1f2328; }
        main { min-height: 100%; display: grid; place-items: center; background: color-mix(in srgb, Canvas 92%, #5a9 8%); }
        section { max-width: 520px; padding: 24px; }
        h1 { font-size: 22px; margin: 0 0 8px; }
        p { line-height: 1.5; margin: 0; color: #4b5563; }
        </style>
        <main><section><h1>Browser Surface</h1><p>Navigate with the toolbar or the /v1/browser/navigate API.</p></section></main>
        """
    }
}

private extension NSToolbarItem.Identifier {
    static let browserBack = NSToolbarItem.Identifier("BrowserSurface.Back")
    static let browserForward = NSToolbarItem.Identifier("BrowserSurface.Forward")
    static let browserReload = NSToolbarItem.Identifier("BrowserSurface.Reload")
    static let browserURL = NSToolbarItem.Identifier("BrowserSurface.URL")
    static let browserStatus = NSToolbarItem.Identifier("BrowserSurface.Status")
}
