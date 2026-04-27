import Foundation

public struct BackgroundComputerUseRuntimeOptions: Sendable {
    public var visualCursor: VisualCursorMode

    public init(visualCursor: VisualCursorMode = .disabled) {
        self.visualCursor = visualCursor
    }
}

public enum VisualCursorMode: Sendable {
    case disabled
    case enabled
}

public final class BackgroundComputerUseRuntime {
    private let services: RuntimeServices

    public init(options: BackgroundComputerUseRuntimeOptions = .init()) {
        let actionOptions = ActionExecutionOptions(
            visualCursorEnabled: options.visualCursor == .enabled
        )
        services = RuntimeServices(executionOptions: actionOptions)
    }

    public func permissions() -> RuntimePermissionsDTO {
        services.permissions()
    }

    public func listApps() -> ListAppsResponse {
        services.listApps()
    }

    public func listWindows(_ request: ListWindowsRequest) throws -> ListWindowsResponse {
        try services.listWindows(request)
    }

    public func getWindowState(_ request: GetWindowStateRequest) throws -> GetWindowStateResponse {
        try services.getWindowState(request)
    }

    public func click(_ request: ClickRequest) throws -> ClickResponse {
        try services.click(request)
    }

    public func scroll(_ request: ScrollRequest) throws -> ScrollResponse {
        try services.scroll(request)
    }

    public func performSecondaryAction(_ request: PerformSecondaryActionRequest) throws -> PerformSecondaryActionResponse {
        try services.performSecondaryAction(request)
    }

    public func drag(_ request: DragRequest) throws -> DragResponse {
        try services.drag(request)
    }

    public func resize(_ request: ResizeRequest) throws -> ResizeResponse {
        try services.resize(request)
    }

    public func setWindowFrame(_ request: SetWindowFrameRequest) throws -> SetWindowFrameResponse {
        try services.setWindowFrame(request)
    }

    public func typeText(_ request: TypeTextRequest) throws -> TypeTextResponse {
        try services.typeText(request)
    }

    public func pressKey(_ request: PressKeyRequest) throws -> PressKeyResponse {
        try services.pressKey(request)
    }

    public func setValue(_ request: SetValueRequest) throws -> SetValueResponse {
        try services.setValue(request)
    }

    public func browserCreateWindow(_ request: BrowserCreateWindowRequest) throws -> BrowserCreateWindowResponse {
        try services.browserCreateWindow(request)
    }

    public func browserListTargets(_ request: BrowserListTargetsRequest) throws -> BrowserListTargetsResponse {
        try services.browserListTargets(request)
    }

    public func browserNavigate(_ request: BrowserNavigateRequest) throws -> BrowserGetStateResponse {
        try services.browserNavigate(request)
    }

    public func browserGetState(_ request: BrowserGetStateRequest) throws -> BrowserGetStateResponse {
        try services.browserGetState(request)
    }

    public func browserEvaluateJavaScript(_ request: BrowserEvaluateJavaScriptRequest) throws -> BrowserEvaluateJavaScriptResponse {
        try services.browserEvaluateJavaScript(request)
    }

    public func browserInjectJavaScript(_ request: BrowserInjectJavaScriptRequest) throws -> BrowserInjectJavaScriptResponse {
        try services.browserInjectJavaScript(request)
    }

    public func browserRemoveInjectedJavaScript(_ request: BrowserRemoveInjectedJavaScriptRequest) throws -> BrowserRemoveInjectedJavaScriptResponse {
        try services.browserRemoveInjectedJavaScript(request)
    }

    public func browserListInjectedJavaScript(_ request: BrowserListInjectedJavaScriptRequest) throws -> BrowserListInjectedJavaScriptResponse {
        try services.browserListInjectedJavaScript(request)
    }

    public func browserClick(_ request: BrowserClickRequest) throws -> BrowserActionResponse {
        try services.browserClick(request)
    }

    public func browserTypeText(_ request: BrowserTypeTextRequest) throws -> BrowserActionResponse {
        try services.browserTypeText(request)
    }

    public func browserScroll(_ request: BrowserScrollRequest) throws -> BrowserActionResponse {
        try services.browserScroll(request)
    }

    public func browserReload(_ request: BrowserReloadRequest) throws -> BrowserGetStateResponse {
        try services.browserReload(request)
    }

    public func browserClose(_ request: BrowserCloseRequest) throws -> BrowserCloseResponse {
        try services.browserClose(request)
    }

    public func browserEmitEvent(_ request: BrowserEmitEventRequest) -> BrowserEmitEventResponse {
        services.browserEmitEvent(request)
    }

    public func browserPollEvents(_ request: BrowserPollEventsRequest) -> BrowserPollEventsResponse {
        services.browserPollEvents(request)
    }

    public func browserClearEvents(_ request: BrowserClearEventsRequest) -> BrowserClearEventsResponse {
        services.browserClearEvents(request)
    }

    public func browserRegisterProvider(_ request: BrowserRegisterProviderRequest) throws -> BrowserRegisterProviderResponse {
        try services.browserRegisterProvider(request)
    }

    public func browserUnregisterProvider(_ request: BrowserUnregisterProviderRequest) throws -> BrowserUnregisterProviderResponse {
        try services.browserUnregisterProvider(request)
    }
}
