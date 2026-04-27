import Foundation

struct RouterContext {
    let baseURL: URL?
    let startedAt: Date?
}

struct Router {
    private let services = RuntimeServices()

    func response(for request: HTTPRequest, context: RouterContext) -> HTTPResponse {
        switch (request.method, request.path) {
        case (.get, "/health"):
            return .json(
                HealthResponse(
                    ok: true,
                    contractVersion: ContractVersion.current,
                    timestamp: Time.iso8601String(from: Date())
                )
            )

        case (.get, "/v1/bootstrap"):
            let permissions = RuntimePermissionsSnapshot.current().dto
            let instructions = RuntimePermissionInstructions.make(permissions: permissions, baseURL: context.baseURL)
            RuntimePermissionPresenter.showIfNeeded(permissions: permissions, instructions: instructions)
            return .json(
                BootstrapResponse(
                    contractVersion: ContractVersion.current,
                    baseURL: context.baseURL?.absoluteString,
                    startedAt: context.startedAt.map(Time.iso8601String),
                    permissions: permissions,
                    instructions: instructions,
                    guide: APIDocumentation.guide,
                    routes: context.baseURL.map(RouteRegistry.bootstrapRouteDescriptors(baseURL:)) ?? []
                )
            )

        case (.get, "/v1/routes"):
            return .json(
                RouteListResponse(
                    contractVersion: ContractVersion.current,
                    guide: APIDocumentation.guide,
                    routes: RouteRegistry.publicRoutes()
                )
            )

        case (.post, "/v1/list_apps"):
            return decodeAndExecute(
                ListAppsRequest.self,
                routeID: .listApps,
                from: request,
                work: { _ in services.listApps() }
            )

        case (.post, "/v1/list_windows"):
            return decodeAndExecute(
                ListWindowsRequest.self,
                routeID: .listWindows,
                from: request,
                work: { payload in
                    try services.listWindows(payload)
                }
            )

        case (.post, "/v1/get_window_state"):
            return decodeAndExecute(
                GetWindowStateRequest.self,
                routeID: .getWindowState,
                from: request,
                work: { payload in
                    try services.getWindowState(payload)
                }
            )

        case (.post, "/v1/click"):
            return decodeAndExecute(
                ClickRequest.self,
                routeID: .click,
                from: request,
                work: { payload in
                    try services.click(payload)
                }
            )

        case (.post, "/v1/scroll"):
            return decodeAndExecute(
                ScrollRequest.self,
                routeID: .scroll,
                from: request,
                work: { payload in
                    try services.scroll(payload)
                }
            )

        case (.post, "/v1/perform_secondary_action"):
            return decodeAndExecute(
                PerformSecondaryActionRequest.self,
                routeID: .performSecondaryAction,
                from: request,
                work: { payload in
                    try services.performSecondaryAction(payload)
                }
            )

        case (.post, "/v1/drag"):
            return decodeAndExecute(
                DragRequest.self,
                routeID: .drag,
                from: request,
                work: { payload in
                    try services.drag(payload)
                }
            )

        case (.post, "/v1/resize"):
            return decodeAndExecute(
                ResizeRequest.self,
                routeID: .resize,
                from: request,
                work: { payload in
                    try services.resize(payload)
                }
            )

        case (.post, "/v1/set_window_frame"):
            return decodeAndExecute(
                SetWindowFrameRequest.self,
                routeID: .setWindowFrame,
                from: request,
                work: { payload in
                    try services.setWindowFrame(payload)
                }
            )

        case (.post, "/v1/type_text"):
            return decodeAndExecute(
                TypeTextRequest.self,
                routeID: .typeText,
                from: request,
                work: { payload in
                    try services.typeText(payload)
                }
            )

        case (.post, "/v1/press_key"):
            return decodeAndExecute(
                PressKeyRequest.self,
                routeID: .pressKey,
                from: request,
                work: { payload in
                    try services.pressKey(payload)
                }
            )

        case (.post, "/v1/set_value"):
            return decodeAndExecute(
                SetValueRequest.self,
                routeID: .setValue,
                from: request,
                work: { payload in
                    try services.setValue(payload)
                }
            )

        case (.post, "/v1/browser/create_window"):
            return decodeAndExecute(BrowserCreateWindowRequest.self, routeID: .browserCreateWindow, from: request) {
                try services.browserCreateWindow($0)
            }

        case (.post, "/v1/browser/list_targets"):
            return decodeAndExecute(BrowserListTargetsRequest.self, routeID: .browserListTargets, from: request) {
                try services.browserListTargets($0)
            }

        case (.post, "/v1/browser/navigate"):
            return decodeAndExecute(BrowserNavigateRequest.self, routeID: .browserNavigate, from: request) {
                try services.browserNavigate($0)
            }

        case (.post, "/v1/browser/get_state"):
            return decodeAndExecute(BrowserGetStateRequest.self, routeID: .browserGetState, from: request) {
                try services.browserGetState($0)
            }

        case (.post, "/v1/browser/evaluate_js"):
            return decodeAndExecute(BrowserEvaluateJavaScriptRequest.self, routeID: .browserEvaluateJS, from: request) {
                try services.browserEvaluateJavaScript($0)
            }

        case (.post, "/v1/browser/inject_js"):
            return decodeAndExecute(BrowserInjectJavaScriptRequest.self, routeID: .browserInjectJS, from: request) {
                try services.browserInjectJavaScript($0)
            }

        case (.post, "/v1/browser/remove_injected_js"):
            return decodeAndExecute(BrowserRemoveInjectedJavaScriptRequest.self, routeID: .browserRemoveInjectedJS, from: request) {
                try services.browserRemoveInjectedJavaScript($0)
            }

        case (.post, "/v1/browser/list_injected_js"):
            return decodeAndExecute(BrowserListInjectedJavaScriptRequest.self, routeID: .browserListInjectedJS, from: request) {
                try services.browserListInjectedJavaScript($0)
            }

        case (.post, "/v1/browser/click"):
            return decodeAndExecute(BrowserClickRequest.self, routeID: .browserClick, from: request) {
                try services.browserClick($0)
            }

        case (.post, "/v1/browser/type_text"):
            return decodeAndExecute(BrowserTypeTextRequest.self, routeID: .browserTypeText, from: request) {
                try services.browserTypeText($0)
            }

        case (.post, "/v1/browser/scroll"):
            return decodeAndExecute(BrowserScrollRequest.self, routeID: .browserScroll, from: request) {
                try services.browserScroll($0)
            }

        case (.post, "/v1/browser/reload"):
            return decodeAndExecute(BrowserReloadRequest.self, routeID: .browserReload, from: request) {
                try services.browserReload($0)
            }

        case (.post, "/v1/browser/close"):
            return decodeAndExecute(BrowserCloseRequest.self, routeID: .browserClose, from: request) {
                try services.browserClose($0)
            }

        case (.post, "/v1/browser/events/emit"):
            return decodeAndExecute(BrowserEmitEventRequest.self, routeID: .browserEventsEmit, from: request) {
                services.browserEmitEvent($0)
            }

        case (.post, "/v1/browser/events/poll"):
            return decodeAndExecute(BrowserPollEventsRequest.self, routeID: .browserEventsPoll, from: request) {
                services.browserPollEvents($0)
            }

        case (.post, "/v1/browser/events/clear"):
            return decodeAndExecute(BrowserClearEventsRequest.self, routeID: .browserEventsClear, from: request) {
                services.browserClearEvents($0)
            }

        case (.post, "/v1/browser/providers/register"):
            return decodeAndExecute(BrowserRegisterProviderRequest.self, routeID: .browserRegisterProvider, from: request) {
                try services.browserRegisterProvider($0)
            }

        case (.post, "/v1/browser/providers/unregister"):
            return decodeAndExecute(BrowserUnregisterProviderRequest.self, routeID: .browserUnregisterProvider, from: request) {
                try services.browserUnregisterProvider($0)
            }

        default:
            return .json(
                ErrorResponse(
                    error: "route_not_found",
                    message: "No route matched \(request.method.rawValue) \(request.path).",
                    requestID: UUID().uuidString,
                    recovery: [
                        "Call GET /v1/routes and use one of the advertised method/path pairs.",
                        "Check that the request uses the documented HTTP method."
                    ]
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )
        }
    }

    private func decodeAndExecute<Request: Decodable, Response: Encodable>(
        _ type: Request.Type,
        routeID: RouteID,
        from request: HTTPRequest,
        work: (Request) throws -> Response
    ) -> HTTPResponse {
        do {
            let payload = try JSONSupport.decoder.decode(Request.self, from: request.body)
            return .json(
                try work(payload),
                includeDebugNotes: includeDebugNotes(for: routeID, payload: payload)
            )
        } catch {
            if error is DecodingError {
                return invalidRequestResponse(for: error, routeID: routeID)
            }

            return errorResponse(for: error, routeID: routeID)
        }
    }

    private func includeDebugNotes<Request>(for routeID: RouteID, payload: Request) -> Bool {
        guard isActionRoute(routeID),
              let debugRequest = payload as? DebugNotesRequest else {
            return true
        }
        return debugRequest.debug == true
    }

    private func isActionRoute(_ routeID: RouteID) -> Bool {
        switch routeID {
        case .click, .scroll, .performSecondaryAction, .drag, .resize, .setWindowFrame, .typeText, .pressKey, .setValue,
             .browserClick, .browserTypeText, .browserScroll:
            return true
        default:
            return false
        }
    }

    private func invalidRequestResponse(for error: Error, routeID: RouteID) -> HTTPResponse {
        .json(
            ErrorResponse(
                error: "invalid_request",
                message: invalidRequestMessage(for: error, routeID: routeID),
                requestID: UUID().uuidString,
                recovery: [
                    "Call GET /v1/routes and inspect route '\(routeID.rawValue)' request.fields.",
                    "Include all required fields and match enum values exactly.",
                    "Send Content-Type: application/json with a JSON object body for POST routes."
                ]
            ),
            statusCode: 400,
            reasonPhrase: "Bad Request"
        )
    }

    private func invalidRequestMessage(for error: Error, routeID: RouteID) -> String {
        guard case let DecodingError.keyNotFound(key, context) = error else {
            return "Request body does not match the \(routeID.rawValue) schema. \(decodingDetail(for: error))"
        }

        let path = codingPathDescription(context.codingPath + [key])
        return "Request body does not match the \(routeID.rawValue) schema. Missing required field '\(path)'."
    }

    private func decodingDetail(for error: Error) -> String {
        switch error {
        case DecodingError.typeMismatch(let type, let context):
            return "Expected \(type) at '\(codingPathDescription(context.codingPath))'. \(context.debugDescription)"
        case DecodingError.valueNotFound(let type, let context):
            return "Missing value for \(type) at '\(codingPathDescription(context.codingPath))'. \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            return "Invalid value at '\(codingPathDescription(context.codingPath))'. \(context.debugDescription)"
        case DecodingError.keyNotFound(let key, let context):
            let path = codingPathDescription(context.codingPath + [key])
            return "Missing required field '\(path)'."
        default:
            return "Decode error: \(error)."
        }
    }

    private func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "$" : path
    }

    private func errorResponse(for error: Error, routeID: RouteID) -> HTTPResponse {
        switch error {
        case DiscoveryError.accessibilityDenied:
            return .json(
                ErrorResponse(
                    error: "accessibility_denied",
                    message: "Accessibility permission is required for \(routeID.rawValue).",
                    requestID: UUID().uuidString,
                    recovery: [
                        "Grant Accessibility permission to BackgroundComputerUse in System Settings > Privacy & Security > Accessibility.",
                        "Quit and relaunch the signed app bundle through script/start.sh or script/build_and_run.sh run."
                    ]
                ),
                statusCode: 403,
                reasonPhrase: "Forbidden"
            )

        case DiscoveryError.appNotFound(let query):
            return .json(
                ErrorResponse(
                    error: "app_not_found",
                    message: "No targetable app matched query '\(query)'.",
                    requestID: UUID().uuidString,
                    recovery: [
                        "Call POST /v1/list_apps and retry with an exact app name or bundleID.",
                        "Confirm the app is running and has at least one targetable process."
                    ]
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )

        case DiscoveryError.windowNotFound(let windowID):
            return .json(
                ErrorResponse(
                    error: "window_not_found",
                    message: "No live window matched window ID '\(windowID)'.",
                    requestID: UUID().uuidString,
                    recovery: [
                        "Call POST /v1/list_windows again and use a current windowID.",
                        "Confirm the target window has not closed, minimized, or moved to a non-targetable state."
                    ]
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )

        case let error as BrowserSurfaceError:
            let status: (Int, String, String)
            switch error {
            case .targetNotFound:
                status = (404, "browser_target_not_found", "Not Found")
            case .invalidURL, .invalidRequest, .targetAmbiguous, .scriptNotFound:
                status = (400, "browser_invalid_request", "Bad Request")
            case .unsupportedRegisteredProvider:
                status = (501, "browser_provider_unsupported", "Not Implemented")
            case .javascriptFailed, .timedOut:
                status = (500, "browser_runtime_error", "Internal Server Error")
            }
            return .json(
                ErrorResponse(
                    error: status.1,
                    message: error.description,
                    requestID: UUID().uuidString,
                    recovery: [
                        "Call POST /v1/browser/list_targets and use a current browser target ID.",
                        "For owned browser targets, call POST /v1/browser/get_state and retry with current DOM targets."
                    ]
                ),
                statusCode: status.0,
                reasonPhrase: status.2
            )

        default:
            return .json(
                ErrorResponse(
                    error: "internal_error",
                    message: "Route \(routeID.rawValue) failed.",
                    requestID: UUID().uuidString,
                    recovery: [
                        "Retry once if the target UI was changing.",
                        "If the route supports it, retry with debug=true and keep the requestID for logs."
                    ]
                ),
                statusCode: 500,
                reasonPhrase: "Internal Server Error"
            )
        }
    }
}
