import Foundation

struct RouterContext {
    let baseURL: URL?
    let startedAt: Date?
}

struct Router {
    private let coordinator = RuntimeCoordinator()
    private let runningAppService = RunningAppService()
    private let windowListService = WindowListService()
    private let windowStateService = WindowStateService()
    private let windowDragRouteService = WindowDragRouteService()
    private let windowResizeRouteService = WindowResizeRouteService()
    private let setWindowFrameRouteService = SetWindowFrameRouteService()
    private let setValueRouteService = SetValueRouteService()
    private let typeTextRouteService = TypeTextRouteService()
    private let pressKeyRouteService = PressKeyRouteService()
    private let scrollRouteService = ScrollRouteService()
    private let secondaryActionRouteService = SecondaryActionRouteService()
    private let clickRouteService = ClickRouteService()

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
                    routes: context.baseURL.map(RouteRegistry.bootstrapRouteDescriptors(baseURL:)) ?? []
                )
            )

        case (.get, "/v1/routes"):
            return .json(
                RouteListResponse(
                    contractVersion: ContractVersion.current,
                    routes: RouteRegistry.publicRoutes()
                )
            )

        case (.post, "/v1/list_apps"):
            return execute(routeID: .listApps, target: .shared) {
                runningAppService.listApps()
            }

        case (.post, "/v1/list_windows"):
            return decodeAndExecute(
                ListWindowsRequest.self,
                routeID: .listWindows,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .appQuery, appQuery: payload.app, windowID: nil)
                },
                work: { payload in
                    try windowListService.listWindows(appQuery: payload.app)
                }
            )

        case (.post, "/v1/get_window_state"):
            return decodeAndExecute(
                GetWindowStateRequest.self,
                routeID: .getWindowState,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try windowStateService.getWindowState(request: payload)
                }
            )

        case (.post, "/v1/click"):
            return decodeAndExecute(
                ClickRequest.self,
                routeID: .click,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try clickRouteService.click(request: payload)
                }
            )

        case (.post, "/v1/scroll"):
            return decodeAndExecute(
                ScrollRequest.self,
                routeID: .scroll,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try scrollRouteService.scroll(request: payload)
                }
            )

        case (.post, "/v1/perform_secondary_action"):
            return decodeAndExecute(
                PerformSecondaryActionRequest.self,
                routeID: .performSecondaryAction,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try secondaryActionRouteService.performSecondaryAction(request: payload)
                }
            )

        case (.post, "/v1/drag"):
            return decodeAndExecute(
                DragRequest.self,
                routeID: .drag,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try windowDragRouteService.drag(request: payload)
                }
            )

        case (.post, "/v1/resize"):
            return decodeAndExecute(
                ResizeRequest.self,
                routeID: .resize,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try windowResizeRouteService.resize(request: payload)
                }
            )

        case (.post, "/v1/set_window_frame"):
            return decodeAndExecute(
                SetWindowFrameRequest.self,
                routeID: .setWindowFrame,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try setWindowFrameRouteService.setWindowFrame(request: payload)
                }
            )

        case (.post, "/v1/type_text"):
            return decodeAndExecute(
                TypeTextRequest.self,
                routeID: .typeText,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try typeTextRouteService.typeText(request: payload)
                }
            )

        case (.post, "/v1/press_key"):
            return decodeAndExecute(
                PressKeyRequest.self,
                routeID: .pressKey,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try pressKeyRouteService.pressKey(request: payload)
                }
            )

        case (.post, "/v1/set_value"):
            return decodeAndExecute(
                SetValueRequest.self,
                routeID: .setValue,
                from: request,
                target: { payload in
                    RouteTargetSummaryDTO(kind: .window, appQuery: nil, windowID: payload.window)
                },
                work: { payload in
                    try setValueRouteService.setValue(request: payload)
                }
            )

        default:
            return .json(
                ErrorResponse(
                    error: "route_not_found",
                    message: "No route matched \(request.method.rawValue) \(request.path).",
                    requestID: UUID().uuidString
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )
        }
    }

    private func execute<Response: Encodable>(
        routeID: RouteID,
        target: RouteTargetSummaryDTO,
        work: () throws -> Response
    ) -> HTTPResponse {
        let route = RouteRegistry.descriptor(for: routeID)
        do {
            let response = try coordinator.execute(route: route, target: target, work)
            return .json(response)
        } catch {
            return errorResponse(for: error, routeID: routeID)
        }
    }

    private func decodeAndExecute<Request: Decodable, Response: Encodable>(
        _ type: Request.Type,
        routeID: RouteID,
        from request: HTTPRequest,
        target: (Request) -> RouteTargetSummaryDTO,
        work: (Request) throws -> Response
    ) -> HTTPResponse {
        do {
            let payload = try JSONSupport.decoder.decode(Request.self, from: request.body)
            let routeTarget = target(payload)
            let route = RouteRegistry.descriptor(for: routeID)
            let coordinatedResponse = try coordinator.execute(route: route, target: routeTarget) {
                try work(payload)
            }
            return .json(coordinatedResponse)
        } catch {
            if error is DecodingError {
                return .json(
                    ErrorResponse(
                        error: "invalid_request",
                        message: "Request body does not match the \(routeID.rawValue) schema.",
                        requestID: UUID().uuidString
                    ),
                    statusCode: 400,
                    reasonPhrase: "Bad Request"
                )
            }

            return errorResponse(for: error, routeID: routeID)
        }
    }

    private func decodeAndScaffold<Request: Decodable>(
        _ type: Request.Type,
        routeID: RouteID,
        from request: HTTPRequest,
        target: (Request) -> RouteTargetSummaryDTO
    ) -> HTTPResponse {
        do {
            let payload = try JSONSupport.decoder.decode(Request.self, from: request.body)
            return coordinator.scaffold(
                route: RouteRegistry.descriptor(for: routeID),
                target: target(payload)
            )
        } catch {
            return .json(
                ErrorResponse(
                    error: "invalid_request",
                    message: "Request body does not match the \(routeID.rawValue) schema.",
                    requestID: UUID().uuidString
                ),
                statusCode: 400,
                reasonPhrase: "Bad Request"
            )
        }
    }

    private func errorResponse(for error: Error, routeID: RouteID) -> HTTPResponse {
        switch error {
        case DiscoveryError.accessibilityDenied:
            return .json(
                ErrorResponse(
                    error: "accessibility_denied",
                    message: "Accessibility permission is required for \(routeID.rawValue).",
                    requestID: UUID().uuidString
                ),
                statusCode: 403,
                reasonPhrase: "Forbidden"
            )

        case DiscoveryError.appNotFound(let query):
            return .json(
                ErrorResponse(
                    error: "app_not_found",
                    message: "No targetable app matched query '\(query)'.",
                    requestID: UUID().uuidString
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )

        case DiscoveryError.windowNotFound(let windowID):
            return .json(
                ErrorResponse(
                    error: "window_not_found",
                    message: "No live window matched window ID '\(windowID)'.",
                    requestID: UUID().uuidString
                ),
                statusCode: 404,
                reasonPhrase: "Not Found"
            )

        default:
            return .json(
                ErrorResponse(
                    error: "internal_error",
                    message: "Route \(routeID.rawValue) failed.",
                    requestID: UUID().uuidString
                ),
                statusCode: 500,
                reasonPhrase: "Internal Server Error"
            )
        }
    }
}
