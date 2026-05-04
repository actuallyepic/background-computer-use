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
        let fallbackNotes = request.visibility == .nonVisible && request.allowVisibleFallback == true && target.visibility == .visible
            ? ["Promoted non_visible browser creation to visible background mode because screenshot evidence was requested and allowVisibleFallback=true."]
            : []
        let focusNotes = request.activate == true
            ? ["Ignored activate=true because browser routes are background-safe and must not steal focus."]
            : []
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
            notes: fallbackNotes + focusNotes + [
                "Created BCU-owned WKWebView browser target \(target.targetID).",
                "Use existing native window routes with target.hostWindow.windowID when shell movement is needed."
            ]
        )
    }

    func createGrid(_ request: BrowserCreateGridRequest) throws -> BrowserCreateGridResponse {
        try BrowserMainActor.sync {
            let grid = try BrowserSurfaceRegistry.shared.createGrid(request: request)
            let response = grid.state(imageMode: request.imageMode ?? .omit, debug: request.debug)
            guard request.activate == true else { return response }
            return BrowserGridStateResponse(
                ok: response.ok,
                grid: response.grid,
                notes: response.notes + ["Ignored activate=true because browser routes are background-safe and must not steal focus."]
            )
        }
    }

    func updateGrid(_ request: BrowserUpdateGridRequest) throws -> BrowserUpdateGridResponse {
        try BrowserMainActor.sync {
            let grid = try BrowserSurfaceRegistry.shared.gridSurface(for: request.grid)
            try grid.update(request: request)
            return grid.state(imageMode: request.imageMode ?? .omit, debug: request.debug)
        }
    }

    func getGridState(_ request: BrowserGetGridStateRequest) throws -> BrowserGridStateResponse {
        try BrowserMainActor.sync {
            try BrowserSurfaceRegistry.shared.gridSurface(for: request.grid)
                .state(imageMode: request.imageMode ?? .omit, debug: request.debug)
        }
    }

    func listTargets(_ request: BrowserListTargetsRequest) throws -> BrowserListTargetsResponse {
        let targets = try BrowserMainActor.sync {
            BrowserSurfaceRegistry.shared.listTargets()
        }
        return BrowserListTargetsResponse(
            contractVersion: ContractVersion.current,
            targets: targets,
            notes: ["Listed BCU-owned browser surfaces."]
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
        try getState(request, activateTarget: true)
    }

    private func getState(_ request: BrowserGetStateRequest, activateTarget: Bool) throws -> BrowserGetStateResponse {
        let started = Date()
        let surface = try ownedSurface(request.browser, activateTarget: activateTarget)
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
        let windowAndCapture = try BrowserMainActor.sync {
            (surface.resolvedWindowDTO(), surface.screenshotCapable)
        }
        let window = windowAndCapture.0
        let screenshotCapable = windowAndCapture.1
        let stateToken = BrowserStateToken.make(target: target, window: window, dom: snapshot)
        let screenshotStarted = Date()
        let requestedImageMode = request.imageMode ?? .path
        let screenshotWarnings = screenshotCapable ? [] : [
            "Browser target \(request.browser) is \(target.visibility.rawValue); screenshots are omitted and DOM state is the source of truth."
        ]
        let screenshot = ScreenshotCaptureService.capture(
            window: window,
            stateToken: stateToken,
            imageMode: screenshotCapable ? requestedImageMode : .omit,
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
            warnings: screenshotWarnings,
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
                BrowserSurfaceRegistry.shared.listTargets()
                    .compactMap { target -> [BrowserInjectedScriptDTO]? in
                        guard (target.kind == .ownedBrowserTab || target.kind == .ownedBrowserGridCell),
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
        let dispatchTarget = request.target ?? resolved.map { BrowserActionTargetRequestDTO.browserNodeID($0.nodeID) }
        let screenshotCapable = try BrowserMainActor.sync { surface.screenshotCapable }
        guard let center = resolved?.centerAppKit else {
            if screenshotCapable {
                throw BrowserSurfaceError.invalidRequest("No editable browser target was supplied or focused.")
            }
            throw BrowserSurfaceError.invalidRequest("No editable browser target was supplied or focused; non-visible browser targets do not expose cursor coordinates.")
        }
        let point = CGPoint(x: center.x, y: center.y)
        let cursorBefore = CursorRuntime.currentPosition(cursorID: request.cursor?.id ?? "codex")
        let window = try BrowserMainActor.sync { surface.resolvedWindowDTO() }
        let cursor = screenshotCapable
            ? BrowserCursorTargeting.prepareTypeText(
                requested: request.cursor,
                point: point,
                pointSource: request.target?.kind.rawValue ?? "first_editable",
                windowNumber: window.windowNumber,
                options: executionOptions
            )
            : BrowserCursorTargeting.notAttempted(
                requested: request.cursor,
                reason: "Cursor movement was not attempted because this browser target is non-visible.",
                options: executionOptions
            )
        var cursorFinished = false
        defer {
            if cursorFinished == false {
                BrowserCursorTargeting.finishTypeText(cursor: cursor, text: request.text)
            }
        }
        let dispatchResult = try BrowserMainActor.runBlocking {
            try await surface.dispatchTypeText(
                target: dispatchTarget,
                text: request.text,
                append: request.append ?? false
            )
        }
        BrowserCursorTargeting.finishTypeText(cursor: cursor, text: request.text)
        cursorFinished = true
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
        let dispatchOK = jsonIndicatesSuccess(dispatchResult)
        let effectObserved = typeTextEffectObserved(
            dispatchResult: dispatchResult,
            text: request.text,
            preStateToken: preState.stateToken,
            postStateToken: postState.stateToken
        )
        return actionResponse(
            dispatchOK: dispatchOK,
            effectObserved: effectObserved,
            summary: "Browser type_text dispatched through DOM focus/input events.",
            target: postState.target,
            requestedTarget: request.target ?? dispatchTarget,
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
        let windowAndCapture = try BrowserMainActor.sync {
            (surface.resolvedWindowDTO(), surface.screenshotCapable)
        }
        let window = windowAndCapture.0
        let cursor = windowAndCapture.1
            ? BrowserCursorTargeting.prepareScroll(
                requested: request.cursor,
                point: appKitPoint,
                pointSource: request.target?.kind.rawValue ?? "viewport_center",
                direction: request.direction,
                windowNumber: window.windowNumber,
                options: executionOptions
            )
            : BrowserCursorTargeting.notAttempted(
                requested: request.cursor,
                reason: "Cursor movement was not attempted because this browser target is non-visible.",
                options: executionOptions
            )
        var cursorFinished = false
        defer {
            if cursorFinished == false {
                BrowserCursorTargeting.finishScroll(cursor: cursor)
            }
        }
        let dispatchResult = try BrowserMainActor.runBlocking {
            try await surface.dispatchScroll(
                target: request.target,
                direction: request.direction,
                pages: request.pages ?? 1
            )
        }
        BrowserCursorTargeting.finishScroll(cursor: cursor)
        cursorFinished = true
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
        let dispatchOK = jsonIndicatesSuccess(dispatchResult)
        let effectObserved = scrollEffectObserved(
            dispatchResult: dispatchResult,
            preStateToken: preState.stateToken,
            postStateToken: postState.stateToken
        )
        return actionResponse(
            dispatchOK: dispatchOK,
            effectObserved: effectObserved,
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
        let windowAndCapture = try BrowserMainActor.sync {
            (surface.resolvedWindowDTO(), surface.screenshotCapable)
        }
        let window = windowAndCapture.0
        let cursor = windowAndCapture.1
            ? BrowserCursorTargeting.prepareClick(
                requested: request.cursor,
                point: appKitPoint,
                pointSource: pointSource,
                windowNumber: window.windowNumber,
                options: executionOptions
            )
            : BrowserCursorTargeting.notAttempted(
                requested: request.cursor,
                reason: "Cursor movement was not attempted because this browser target is non-visible.",
                options: executionOptions
            )
        var cursorFinished = false
        defer {
            if cursorFinished == false {
                BrowserCursorTargeting.finishClick(cursor: cursor)
            }
        }
        var responseWarnings = warnings
        var dispatchRouteNote: String
        var dispatchSummary: String
        var dispatchResult: JSONValueDTO
        var usedNativeDispatch = false
        if windowAndCapture.1 {
            do {
                dispatchResult = try BrowserMainActor.sync {
                    try surface.dispatchNativeClick(appKitPoint: appKitPoint, clickCount: clickCount)
                }
                usedNativeDispatch = true
                dispatchRouteNote = "Reused existing cursor click choreography and dispatched a native background mouse click to the owned WKWebView host window."
                dispatchSummary = "Browser click dispatched through native background mouse events."
            } catch {
                responseWarnings.append("Native browser click failed and fell back to DOM dispatch: \(error).")
                dispatchResult = try BrowserMainActor.runBlocking {
                    if let target = request.target {
                        return try await surface.dispatchClick(target: target, clickCount: clickCount)
                    }
                    return try await surface.dispatchClickPoint(point: viewportPoint, clickCount: clickCount)
                }
                dispatchRouteNote = "Reused existing cursor click choreography, attempted native background click, then fell back to DOM pointer/mouse/click dispatch."
                dispatchSummary = "Browser click dispatched through DOM pointer/mouse/click events after native background click fallback failed."
            }
        } else {
            dispatchResult = try BrowserMainActor.runBlocking {
                if let target = request.target {
                    return try await surface.dispatchClick(target: target, clickCount: clickCount)
                }
                return try await surface.dispatchClickPoint(point: viewportPoint, clickCount: clickCount)
            }
            dispatchRouteNote = "Reused existing cursor click choreography and dispatched the DOM action after the cursor reached the resolved element center."
            dispatchSummary = "Browser click dispatched through DOM pointer/mouse/click events."
        }
        BrowserCursorTargeting.finishClick(cursor: cursor)
        cursorFinished = true
        sleepRunLoop(0.28)
        let postSurface = try BrowserMainActor.sync {
            try BrowserSurfaceRegistry.shared.surfaceForPostActionState(startingFrom: request.browser)
        }
        var postState = try getState(
            BrowserGetStateRequest(
                browser: postSurface.tabTargetID,
                maxElements: 500,
                includeRawText: false,
                imageMode: request.imageMode ?? .path,
                debug: request.debug
            )
        )
        var dispatchOK = jsonIndicatesSuccess(dispatchResult)
        var effectObserved = clickEffectObserved(
            dispatchResult: dispatchResult,
            preStateToken: preStateToken,
            postStateToken: postState.stateToken
        )
        if usedNativeDispatch, dispatchOK, effectObserved == false {
            responseWarnings.append("Native browser click completed, but no effect was observed; retried with DOM dispatch.")
            dispatchResult = try BrowserMainActor.runBlocking {
                if let target = request.target {
                    return try await surface.dispatchClick(target: target, clickCount: clickCount)
                }
                return try await surface.dispatchClickPoint(point: viewportPoint, clickCount: clickCount)
            }
            dispatchRouteNote = "Reused existing cursor click choreography, retried with DOM dispatch after native background click produced no observed effect."
            dispatchSummary = "Browser click dispatched through DOM pointer/mouse/click events after native click was unverified."
            sleepRunLoop(0.12)
            let fallbackPostSurface = try BrowserMainActor.sync {
                try BrowserSurfaceRegistry.shared.surfaceForPostActionState(startingFrom: request.browser)
            }
            postState = try getState(
                BrowserGetStateRequest(
                    browser: fallbackPostSurface.tabTargetID,
                    maxElements: 500,
                    includeRawText: false,
                    imageMode: request.imageMode ?? .path,
                    debug: request.debug
                )
            )
            dispatchOK = jsonIndicatesSuccess(dispatchResult)
            effectObserved = clickEffectObserved(
                dispatchResult: dispatchResult,
                preStateToken: preStateToken,
                postStateToken: postState.stateToken
            )
        }
        return actionResponse(
            dispatchOK: dispatchOK,
            effectObserved: effectObserved,
            summary: dispatchSummary,
            target: postState.target,
            requestedTarget: request.target,
            preStateToken: preStateToken,
            postStateToken: postState.stateToken,
            cursor: cursor,
            screenshot: postState.screenshot,
            warnings: responseWarnings,
            notes: [
                dispatchRouteNote,
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

    private func ownedSurface(_ targetID: String, activateTarget: Bool = true) throws -> OwnedBrowserSurface {
        try BrowserMainActor.sync {
            if activateTarget {
                return try BrowserSurfaceRegistry.shared.activateOwnedSurface(for: targetID)
            }
            return try BrowserSurfaceRegistry.shared.ownedSurface(for: targetID)
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
        return BrowserActionResponse(
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
        dispatchOK: Bool,
        effectObserved: Bool,
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
        let ok = dispatchOK && effectObserved
        let verificationWarnings = dispatchOK && effectObserved == false
            ? ["Dispatch completed, but no lightweight post-action effect was observed in browser state."]
            : []
        return BrowserActionResponse(
            contractVersion: ContractVersion.current,
            ok: ok,
            classification: ok ? .success : .effectNotVerified,
            failureDomain: ok ? nil : (dispatchOK ? .verification : .transport),
            summary: summary,
            target: target,
            requestedTarget: requestedTarget,
            preStateToken: preStateToken,
            postStateToken: postStateToken,
            cursor: cursor,
            screenshot: screenshot,
            warnings: warnings + verificationWarnings + cursor.warnings,
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

    private func clickEffectObserved(
        dispatchResult: JSONValueDTO,
        preStateToken: String,
        postStateToken: String
    ) -> Bool {
        guard jsonIndicatesSuccess(dispatchResult) else { return false }
        return preStateToken != postStateToken
    }

    private func scrollEffectObserved(
        dispatchResult: JSONValueDTO,
        preStateToken: String,
        postStateToken: String
    ) -> Bool {
        guard jsonIndicatesSuccess(dispatchResult) else { return false }
        if preStateToken != postStateToken {
            return true
        }
        guard case .object(let object) = dispatchResult,
              case .object(let delta)? = object["delta"] else {
            return false
        }
        let dx = numberValue(delta["x"])
        let dy = numberValue(delta["y"])
        return abs(dx) > 0.5 || abs(dy) > 0.5
    }

    private func typeTextEffectObserved(
        dispatchResult: JSONValueDTO,
        text: String,
        preStateToken: String,
        postStateToken: String
    ) -> Bool {
        guard jsonIndicatesSuccess(dispatchResult) else { return false }
        if text.isEmpty {
            return true
        }
        if preStateToken != postStateToken {
            return true
        }
        guard case .object(let object) = dispatchResult else {
            return false
        }
        if case .string(let value)? = object["valuePreview"] {
            return value.contains(text)
        }
        return false
    }

    private func numberValue(_ value: JSONValueDTO?) -> Double {
        guard case .number(let number)? = value else { return 0 }
        return number
    }
}

private extension BrowserActionResponse {
    func replacingCursor(
        _ cursor: ActionCursorTargetResponseDTO,
        preStateToken replacementPreStateToken: String?,
        warnings additionalWarnings: [String]
    ) -> BrowserActionResponse {
        BrowserActionResponse(
            contractVersion: contractVersion,
            ok: ok,
            classification: classification,
            failureDomain: failureDomain,
            summary: summary,
            target: target,
            requestedTarget: requestedTarget,
            preStateToken: preStateToken ?? replacementPreStateToken,
            postStateToken: postStateToken,
            cursor: cursor,
            screenshot: screenshot,
            warnings: additionalWarnings + warnings + cursor.warnings,
            notes: notes,
            debug: debug
        )
    }
}
