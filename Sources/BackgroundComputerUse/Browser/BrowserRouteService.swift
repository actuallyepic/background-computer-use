import AppKit
import Foundation

struct BrowserRouteService {
    private let executionOptions: ActionExecutionOptions

    init(executionOptions: ActionExecutionOptions = .visualCursorEnabled) {
        self.executionOptions = executionOptions
    }

    func createWindow(_ request: BrowserCreateWindowRequest) throws -> BrowserCreateWindowResponse {
        let surface = try BrowserMainActor.sync {
            try BrowserSurfaceRegistry.shared.createWindow(request: request)
        }
        try? BrowserMainActor.runBlocking(timeout: 4) {
            try await surface.waitUntilLoaded(timeoutMs: 3_000)
        }
        let target = try BrowserMainActor.sync {
            surface.tabSummary()
        }
        let state = try getState(
            BrowserGetStateRequest(
                browser: target.targetID,
                maxElements: 500,
                includeRawText: false,
                imageMode: request.imageMode ?? .omit,
                debug: request.debug
            )
        )
        return BrowserCreateWindowResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            target: target,
            state: state,
            notes: [
                "Created BCU-owned WKWebView browser target \(target.targetID).",
                "Use existing native window routes with target.hostWindow.windowID when shell movement is needed."
            ]
        )
    }

    func listTargets(_ request: BrowserListTargetsRequest) throws -> BrowserListTargetsResponse {
        let targets = try BrowserMainActor.sync {
            BrowserSurfaceRegistry.shared.listTargets(includeRegistered: request.includeRegistered ?? true)
        }
        return BrowserListTargetsResponse(
            contractVersion: ContractVersion.current,
            targets: targets,
            notes: ["Listed BCU-owned and registered browser surfaces."]
        )
    }

    func navigate(_ request: BrowserNavigateRequest) throws -> BrowserGetStateResponse {
        let surface = try ownedSurface(request.browser)
        try BrowserMainActor.sync {
            try surface.navigate(request.url)
        }
        if request.waitUntilLoaded ?? true {
            try BrowserMainActor.runBlocking(timeout: TimeInterval(max(request.timeoutMs ?? 8_000, 100)) / 1_000 + 1) {
                try await surface.waitUntilLoaded(timeoutMs: request.timeoutMs)
            }
        }
        return try getState(
            BrowserGetStateRequest(
                browser: request.browser,
                maxElements: 500,
                includeRawText: false,
                imageMode: request.imageMode ?? .path,
                debug: request.debug
            )
        )
    }

    func getState(_ request: BrowserGetStateRequest) throws -> BrowserGetStateResponse {
        let started = Date()
        let surface = try ownedSurface(request.browser)
        let resolveEnded = Date()
        let snapshot = try BrowserMainActor.runBlocking {
            try await surface.snapshot(
                maxElements: request.maxElements,
                includeRawText: request.includeRawText
            )
        }
        let domEnded = Date()
        let target = try BrowserMainActor.sync {
            try BrowserSurfaceRegistry.shared.summary(for: request.browser)
        }
        let window = try BrowserMainActor.sync {
            surface.resolvedWindowDTO()
        }
        let stateToken = BrowserStateToken.make(target: target, window: window, dom: snapshot)
        let screenshotStarted = Date()
        let screenshot = ScreenshotCaptureService.capture(
            window: window,
            stateToken: stateToken,
            imageMode: request.imageMode ?? .path,
            includeRawRetinaCapture: request.debug == true,
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
                resolveMs: resolveEnded.timeIntervalSince(started) * 1_000,
                domMs: domEnded.timeIntervalSince(resolveEnded) * 1_000,
                screenshotMs: finished.timeIntervalSince(screenshotStarted) * 1_000,
                totalMs: finished.timeIntervalSince(started) * 1_000
            ),
            warnings: [],
            notes: [
                "Read live DOM state through the owned WKWebView bootstrap script.",
                "Interactable rectAppKit/centerAppKit map DOM viewport coordinates into the same AppKit screen coordinate space used by the native cursor."
            ]
        )
    }

    func evaluateJavaScript(_ request: BrowserEvaluateJavaScriptRequest) throws -> BrowserEvaluateJavaScriptResponse {
        let surface = try ownedSurface(request.browser)
        return try BrowserMainActor.runBlocking(timeout: TimeInterval(max(request.timeoutMs ?? 8_000, 100)) / 1_000 + 1) {
            try await surface.evaluateJavaScript(request.javaScript)
        }
    }

    func injectJavaScript(_ request: BrowserInjectJavaScriptRequest) throws -> BrowserInjectJavaScriptResponse {
        guard request.scriptID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw BrowserSurfaceError.invalidRequest("scriptID must be non-empty.")
        }
        guard request.javaScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw BrowserSurfaceError.invalidRequest("javaScript must be non-empty.")
        }
        guard let browser = request.browser else {
            throw BrowserSurfaceError.invalidRequest("browser is required for injected scripts in this implementation.")
        }
        let surface = try ownedSurface(browser)
        return try BrowserMainActor.runBlocking {
            try await surface.installScript(request: request)
        }
    }

    func removeInjectedJavaScript(_ request: BrowserRemoveInjectedJavaScriptRequest) throws -> BrowserRemoveInjectedJavaScriptResponse {
        guard let browser = request.browser else {
            throw BrowserSurfaceError.invalidRequest("browser is required when removing injected scripts.")
        }
        let surface = try ownedSurface(browser)
        return try BrowserMainActor.sync {
            surface.removeScript(scriptID: request.scriptID)
        }
    }

    func listInjectedJavaScript(_ request: BrowserListInjectedJavaScriptRequest) throws -> BrowserListInjectedJavaScriptResponse {
        guard let browser = request.browser else {
            let scripts = try BrowserMainActor.sync {
                BrowserSurfaceRegistry.shared.listTargets(includeRegistered: false)
                    .compactMap { target -> [BrowserInjectedScriptDTO]? in
                        guard target.kind == .ownedBrowserTab,
                              let surface = try? BrowserSurfaceRegistry.shared.ownedSurface(for: target.targetID) else {
                            return nil
                        }
                        return surface.listScripts()
                    }
                    .flatMap { $0 }
            }
            return BrowserListInjectedJavaScriptResponse(
                contractVersion: ContractVersion.current,
                scripts: scripts,
                notes: ["Listed injected scripts for all owned browser targets."]
            )
        }

        let surface = try ownedSurface(browser)
        let scripts = try BrowserMainActor.sync {
            surface.listScripts()
        }
        return BrowserListInjectedJavaScriptResponse(
            contractVersion: ContractVersion.current,
            scripts: scripts,
            notes: ["Listed injected scripts for browser target \(browser)."]
        )
    }

    func click(_ request: BrowserClickRequest) throws -> BrowserActionResponse {
        let started = Date()
        let surface = try ownedSurface(request.browser)
        let preState = try getState(
            BrowserGetStateRequest(
                browser: request.browser,
                maxElements: 500,
                includeRawText: false,
                imageMode: .omit,
                debug: request.debug
            )
        )
        let stateWarnings = staleStateWarnings(supplied: request.stateToken, live: preState.stateToken)
        guard stateWarnings.isEmpty else {
            return rejectedActionResponse(
                summary: "Supplied stateToken did not match the live browser state; refusing to click a potentially stale DOM target.",
                requestBrowser: request.browser,
                requestedTarget: request.target,
                preStateToken: preState.stateToken,
                cursor: BrowserCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the request stateToken was stale.",
                    options: executionOptions
                ),
                warnings: stateWarnings,
                started: started
            )
        }

        let clickCount = max(1, min(request.clickCount ?? 1, 2))
        let resolved: BrowserInteractableDTO?
        let viewportPoint: PointDTO
        let pointSource: String
        if let target = request.target {
            resolved = try BrowserMainActor.runBlocking {
                try await surface.resolve(target: target)
            }
            guard let center = resolved?.centerAppKit else {
                throw BrowserSurfaceError.invalidRequest("Resolved DOM target did not include an AppKit center point.")
            }
            viewportPoint = resolved?.centerViewport ?? PointDTO(x: 0, y: 0)
            pointSource = target.kind.rawValue
            let point = CGPoint(x: center.x, y: center.y)
            return try performClick(
                request: request,
                surface: surface,
                appKitPoint: point,
                viewportPoint: viewportPoint,
                pointSource: pointSource,
                resolved: resolved,
                clickCount: clickCount,
                preStateToken: preState.stateToken,
                warnings: stateWarnings,
                started: started
            )
        }

        guard let x = request.x, let y = request.y else {
            throw BrowserSurfaceError.invalidRequest("Supply either target or both x and y for browser click.")
        }
        resolved = nil
        viewportPoint = PointDTO(x: x, y: y)
        pointSource = "browser_viewport_coordinate"
        let appKitPoint = try BrowserMainActor.sync {
            surface.viewportPointToAppKit(viewportPoint)
        }
        return try performClick(
            request: request,
            surface: surface,
            appKitPoint: appKitPoint,
            viewportPoint: viewportPoint,
            pointSource: pointSource,
            resolved: resolved,
            clickCount: clickCount,
            preStateToken: preState.stateToken,
            warnings: stateWarnings,
            started: started
        )
    }

    func typeText(_ request: BrowserTypeTextRequest) throws -> BrowserActionResponse {
        let started = Date()
        let surface = try ownedSurface(request.browser)
        let preState = try getState(
            BrowserGetStateRequest(
                browser: request.browser,
                maxElements: 500,
                includeRawText: false,
                imageMode: .omit,
                debug: request.debug
            )
        )
        let stateWarnings = staleStateWarnings(supplied: request.stateToken, live: preState.stateToken)
        guard stateWarnings.isEmpty else {
            return rejectedActionResponse(
                summary: "Supplied stateToken did not match the live browser state; refusing to type into a potentially stale DOM target.",
                requestBrowser: request.browser,
                requestedTarget: request.target,
                preStateToken: preState.stateToken,
                cursor: BrowserCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the request stateToken was stale.",
                    options: executionOptions
                ),
                warnings: stateWarnings,
                started: started
            )
        }

        let resolved: BrowserInteractableDTO?
        if let target = request.target {
            resolved = try BrowserMainActor.runBlocking {
                try await surface.resolve(target: target)
            }
        } else {
            resolved = preState.dom.interactables.first(where: \.isEditable)
        }
        guard let center = resolved?.centerAppKit else {
            throw BrowserSurfaceError.invalidRequest("No editable browser target was supplied or focused.")
        }
        let point = CGPoint(x: center.x, y: center.y)
        let cursorBefore = CursorRuntime.currentPosition(cursorID: request.cursor?.id ?? "codex")
        let window = try BrowserMainActor.sync { surface.resolvedWindowDTO() }
        let cursor = BrowserCursorTargeting.prepareTypeText(
            requested: request.cursor,
            point: point,
            pointSource: request.target?.kind.rawValue ?? "first_editable",
            windowNumber: window.windowNumber,
            options: executionOptions
        )
        let dispatchResult = try BrowserMainActor.runBlocking {
            try await surface.dispatchTypeText(
                target: request.target,
                text: request.text,
                append: request.append ?? false
            )
        }
        BrowserCursorTargeting.finishTypeText(cursor: cursor, text: request.text)
        sleepRunLoop(0.12)
        let postState = try getState(
            BrowserGetStateRequest(
                browser: request.browser,
                maxElements: 500,
                includeRawText: false,
                imageMode: request.imageMode ?? .path,
                debug: request.debug
            )
        )
        return actionResponse(
            ok: jsonIndicatesSuccess(dispatchResult),
            summary: "Browser type_text dispatched through DOM focus/input events.",
            target: postState.target,
            requestedTarget: request.target,
            preStateToken: preState.stateToken,
            postStateToken: postState.stateToken,
            cursor: cursor,
            screenshot: postState.screenshot,
            warnings: stateWarnings,
            notes: ["Reused existing cursor type-text choreography and dispatched text through the owned WKWebView DOM bridge."],
            debug: makeDebug(
                resolved: resolved,
                cursorBefore: cursorBefore,
                window: window,
                dispatchResult: dispatchResult
            )
        )
    }

    func scroll(_ request: BrowserScrollRequest) throws -> BrowserActionResponse {
        let started = Date()
        let surface = try ownedSurface(request.browser)
        let preState = try getState(
            BrowserGetStateRequest(
                browser: request.browser,
                maxElements: 500,
                includeRawText: false,
                imageMode: .omit,
                debug: request.debug
            )
        )
        let stateWarnings = staleStateWarnings(supplied: request.stateToken, live: preState.stateToken)
        guard stateWarnings.isEmpty else {
            return rejectedActionResponse(
                summary: "Supplied stateToken did not match the live browser state; refusing to scroll a potentially stale DOM target.",
                requestBrowser: request.browser,
                requestedTarget: request.target,
                preStateToken: preState.stateToken,
                cursor: BrowserCursorTargeting.notAttempted(
                    requested: request.cursor,
                    reason: "Cursor movement was not attempted because the request stateToken was stale.",
                    options: executionOptions
                ),
                warnings: stateWarnings,
                started: started
            )
        }

        let resolved = try request.target.map { target in
            try BrowserMainActor.runBlocking {
                try await surface.resolve(target: target)
            }
        }
        let viewportPoint = resolved?.centerViewport ?? PointDTO(
            x: max(preState.dom.viewport.width / 2, 1),
            y: max(preState.dom.viewport.height / 2, 1)
        )
        let appKitPoint = try BrowserMainActor.sync {
            if let center = resolved?.centerAppKit {
                return CGPoint(x: center.x, y: center.y)
            }
            return surface.viewportPointToAppKit(viewportPoint)
        }
        let cursorBefore = CursorRuntime.currentPosition(cursorID: request.cursor?.id ?? "codex")
        let window = try BrowserMainActor.sync { surface.resolvedWindowDTO() }
        let cursor = BrowserCursorTargeting.prepareScroll(
            requested: request.cursor,
            point: appKitPoint,
            pointSource: request.target?.kind.rawValue ?? "viewport_center",
            direction: request.direction,
            windowNumber: window.windowNumber,
            options: executionOptions
        )
        let dispatchResult = try BrowserMainActor.runBlocking {
            try await surface.dispatchScroll(
                target: request.target,
                direction: request.direction,
                pages: request.pages ?? 1
            )
        }
        BrowserCursorTargeting.finishScroll(cursor: cursor)
        sleepRunLoop(0.18)
        let postState = try getState(
            BrowserGetStateRequest(
                browser: request.browser,
                maxElements: 500,
                includeRawText: false,
                imageMode: request.imageMode ?? .path,
                debug: request.debug
            )
        )
        return actionResponse(
            ok: jsonIndicatesSuccess(dispatchResult),
            summary: "Browser scroll dispatched through DOM scroll primitives.",
            target: postState.target,
            requestedTarget: request.target,
            preStateToken: preState.stateToken,
            postStateToken: postState.stateToken,
            cursor: cursor,
            screenshot: postState.screenshot,
            warnings: stateWarnings,
            notes: ["Reused existing cursor scroll choreography and dispatched scrolling through the owned WKWebView DOM bridge."],
            debug: makeDebug(
                resolved: resolved,
                cursorBefore: cursorBefore,
                window: window,
                dispatchResult: dispatchResult
            )
        )
    }

    func reload(_ request: BrowserReloadRequest) throws -> BrowserGetStateResponse {
        let surface = try ownedSurface(request.browser)
        try BrowserMainActor.sync {
            surface.reload()
        }
        if request.waitUntilLoaded ?? true {
            try BrowserMainActor.runBlocking(timeout: TimeInterval(max(request.timeoutMs ?? 8_000, 100)) / 1_000 + 1) {
                try await surface.waitUntilLoaded(timeoutMs: request.timeoutMs)
            }
        }
        return try getState(
            BrowserGetStateRequest(
                browser: request.browser,
                maxElements: 500,
                includeRawText: false,
                imageMode: request.imageMode ?? .path,
                debug: request.debug
            )
        )
    }

    func close(_ request: BrowserCloseRequest) throws -> BrowserCloseResponse {
        let closed = try BrowserMainActor.sync {
            try BrowserSurfaceRegistry.shared.close(targetID: request.browser)
        }
        return BrowserCloseResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            closed: closed,
            notes: ["Closed browser target \(request.browser)."]
        )
    }

    func emitEvent(_ request: BrowserEmitEventRequest) -> BrowserEmitEventResponse {
        let event = BrowserEventStore.shared.emit(
            targetID: request.browser,
            scriptID: request.scriptID,
            type: request.type,
            payload: request.payload
        )
        return BrowserEmitEventResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            event: event
        )
    }

    func pollEvents(_ request: BrowserPollEventsRequest) -> BrowserPollEventsResponse {
        let events = BrowserEventStore.shared.poll(
            sinceEventID: request.sinceEventID,
            targetID: request.browser,
            limit: request.limit
        )
        return BrowserPollEventsResponse(
            contractVersion: ContractVersion.current,
            events: events,
            latestEventID: events.last?.eventID ?? BrowserEventStore.shared.latestEventID()
        )
    }

    func clearEvents(_ request: BrowserClearEventsRequest) -> BrowserClearEventsResponse {
        BrowserClearEventsResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            removedCount: BrowserEventStore.shared.clear(targetID: request.browser)
        )
    }

    func registerProvider(_ request: BrowserRegisterProviderRequest) throws -> BrowserRegisterProviderResponse {
        try BrowserMainActor.sync {
            try BrowserSurfaceRegistry.shared.registerProvider(request: request)
        }
    }

    func unregisterProvider(_ request: BrowserUnregisterProviderRequest) throws -> BrowserUnregisterProviderResponse {
        try BrowserMainActor.sync {
            BrowserSurfaceRegistry.shared.unregisterProvider(request: request)
        }
    }

    private func performClick(
        request: BrowserClickRequest,
        surface: OwnedBrowserSurface,
        appKitPoint: CGPoint,
        viewportPoint: PointDTO,
        pointSource: String,
        resolved: BrowserInteractableDTO?,
        clickCount: Int,
        preStateToken: String,
        warnings: [String],
        started: Date
    ) throws -> BrowserActionResponse {
        let cursorBefore = CursorRuntime.currentPosition(cursorID: request.cursor?.id ?? "codex")
        let window = try BrowserMainActor.sync { surface.resolvedWindowDTO() }
        let cursor = BrowserCursorTargeting.prepareClick(
            requested: request.cursor,
            point: appKitPoint,
            pointSource: pointSource,
            windowNumber: window.windowNumber,
            options: executionOptions
        )
        let dispatchResult = try BrowserMainActor.runBlocking {
            if let target = request.target {
                return try await surface.dispatchClick(target: target, clickCount: clickCount)
            }
            return try await surface.dispatchClickPoint(point: viewportPoint, clickCount: clickCount)
        }
        BrowserCursorTargeting.finishClick(cursor: cursor)
        sleepRunLoop(0.16)
        let postState = try getState(
            BrowserGetStateRequest(
                browser: request.browser,
                maxElements: 500,
                includeRawText: false,
                imageMode: request.imageMode ?? .path,
                debug: request.debug
            )
        )
        return actionResponse(
            ok: jsonIndicatesSuccess(dispatchResult),
            summary: "Browser click dispatched through DOM pointer/mouse/click events.",
            target: postState.target,
            requestedTarget: request.target,
            preStateToken: preStateToken,
            postStateToken: postState.stateToken,
            cursor: cursor,
            screenshot: postState.screenshot,
            warnings: warnings,
            notes: [
                "Reused existing cursor click choreography and dispatched the DOM action after the cursor reached the resolved element center.",
                "Action elapsed \(Int(Date().timeIntervalSince(started) * 1_000))ms."
            ],
            debug: makeDebug(
                resolved: resolved,
                cursorBefore: cursorBefore,
                window: window,
                dispatchResult: dispatchResult
            )
        )
    }

    private func ownedSurface(_ targetID: String) throws -> OwnedBrowserSurface {
        try BrowserMainActor.sync {
            try BrowserSurfaceRegistry.shared.ownedSurface(for: targetID)
        }
    }

    private func staleStateWarnings(supplied: String?, live: String) -> [String] {
        guard let supplied, supplied != live else { return [] }
        return ["Supplied browser stateToken '\(supplied)' did not match live token '\(live)'."]
    }

    private func rejectedActionResponse(
        summary: String,
        requestBrowser: String,
        requestedTarget: BrowserActionTargetRequestDTO?,
        preStateToken: String?,
        cursor: ActionCursorTargetResponseDTO,
        warnings: [String],
        started: Date
    ) -> BrowserActionResponse {
        BrowserActionResponse(
            contractVersion: ContractVersion.current,
            ok: false,
            classification: .verifierAmbiguous,
            failureDomain: .targeting,
            summary: summary,
            target: try? BrowserMainActor.sync {
                try BrowserSurfaceRegistry.shared.summary(for: requestBrowser)
            },
            requestedTarget: requestedTarget,
            preStateToken: preStateToken,
            postStateToken: nil,
            cursor: cursor,
            screenshot: nil,
            warnings: warnings,
            notes: ["Rejected before dispatch in \(Int(Date().timeIntervalSince(started) * 1_000))ms."],
            debug: nil
        )
    }

    private func actionResponse(
        ok: Bool,
        summary: String,
        target: BrowserTargetSummaryDTO?,
        requestedTarget: BrowserActionTargetRequestDTO?,
        preStateToken: String?,
        postStateToken: String?,
        cursor: ActionCursorTargetResponseDTO,
        screenshot: ScreenshotDTO?,
        warnings: [String],
        notes: [String],
        debug: BrowserActionDebugDTO?
    ) -> BrowserActionResponse {
        BrowserActionResponse(
            contractVersion: ContractVersion.current,
            ok: ok,
            classification: ok ? .success : .effectNotVerified,
            failureDomain: ok ? nil : .transport,
            summary: summary,
            target: target,
            requestedTarget: requestedTarget,
            preStateToken: preStateToken,
            postStateToken: postStateToken,
            cursor: cursor,
            screenshot: screenshot,
            warnings: warnings + cursor.warnings,
            notes: notes,
            debug: debug
        )
    }

    private func makeDebug(
        resolved: BrowserInteractableDTO?,
        cursorBefore: CGPoint?,
        window: ResolvedWindowDTO,
        dispatchResult: JSONValueDTO?
    ) -> BrowserActionDebugDTO {
        BrowserActionDebugDTO(
            resolvedRectViewport: resolved?.rectViewport,
            resolvedCenterViewport: resolved?.centerViewport,
            resolvedRectAppKit: resolved?.rectAppKit,
            resolvedCenterAppKit: resolved?.centerAppKit,
            hostWindowFrameAppKit: window.frameAppKit,
            cursorPositionBeforeAppKit: cursorBefore.map { PointDTO(x: $0.x, y: $0.y) },
            dispatchResult: dispatchResult
        )
    }

    private func jsonIndicatesSuccess(_ value: JSONValueDTO) -> Bool {
        guard case .object(let object) = value,
              case .bool(let ok)? = object["ok"] else {
            return true
        }
        return ok
    }
}
