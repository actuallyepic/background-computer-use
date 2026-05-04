import Foundation

enum RouteID: String, CaseIterable {
    case health
    case bootstrap
    case routes
    case listApps = "list_apps"
    case listWindows = "list_windows"
    case getWindowState = "get_window_state"
    case click
    case scroll
    case performSecondaryAction = "perform_secondary_action"
    case drag
    case resize
    case setWindowFrame = "set_window_frame"
    case typeText = "type_text"
    case pressKey = "press_key"
    case setValue = "set_value"
    case browserCreateWindow = "browser_create_window"
    case browserListTargets = "browser_list_targets"
    case browserGetState = "browser_get_state"
    case browserNavigate = "browser_navigate"
    case browserEvaluateJS = "browser_evaluate_js"
    case browserInjectJS = "browser_inject_js"
    case browserRemoveInjectedJS = "browser_remove_injected_js"
    case browserListInjectedJS = "browser_list_injected_js"
    case browserClick = "browser_click"
    case browserTypeText = "browser_type_text"
    case browserScroll = "browser_scroll"
    case browserReload = "browser_reload"
    case browserClose = "browser_close"
    case browserCreateGrid = "browser_create_grid"
    case browserUpdateGrid = "browser_update_grid"
    case browserGetGridState = "browser_get_grid_state"
}

enum RouteRegistry {
    static let descriptors: [RouteDescriptorDTO] = [
        RouteDescriptorDTO(
            id: RouteID.health.rawValue,
            method: "GET",
            path: "/health",
            category: "system",
            summary: "Health probe for the local loopback runtime.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["System routes should remain cheap, background-safe, and independent of per-window execution lanes."]
            ),
            implementationStatus: .implemented,
            notes: RuntimeMetadata.systemRouteNotes
        ),
        RouteDescriptorDTO(
            id: RouteID.bootstrap.rawValue,
            method: "GET",
            path: "/v1/bootstrap",
            category: "system",
            summary: "Connection, permission, and route discovery for the local API.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: [
                    "Agents should call bootstrap first to confirm the runtime URL, permissions, and launch readiness.",
                    "When Accessibility or Screen Recording is missing, bootstrap returns user-facing instructions and presents a local permission alert."
                ]
            ),
            implementationStatus: .implemented,
            notes: RuntimeMetadata.systemRouteNotes + [
                "Call this before action routes. If instructions.ready is false, pause action attempts until the user grants the requested macOS permissions and relaunches the signed app bundle."
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.routes.rawValue,
            method: "GET",
            path: "/v1/routes",
            category: "system",
            summary: "Self-documenting route catalog for the API surface.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: [
                    "The route registry is the machine-readable source of truth for request and response shapes.",
                    "Call /v1/bootstrap first, then use /v1/routes to plan action calls."
                ]
            ),
            implementationStatus: .implemented,
            notes: RuntimeMetadata.systemRouteNotes + [
                "For visual work, call get_window_state with imageMode path or base64 whenever possible and inspect screenshots before and after actions.",
                "Use AX tree nodes for semantic targets, but treat screenshots as the visual ground truth because AX trees and verifier summaries can lag, be incomplete, or miss purely visual state."
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.listApps.rawValue,
            method: "POST",
            path: "/v1/list_apps",
            category: "discovery",
            summary: "List targetable running apps.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["Discovery routes should remain independent of any one window lane."]
            ),
            implementationStatus: .implemented,
            notes: ["Discovery routes are coordinated by the shared-read runtime lane."]
        ),
        RouteDescriptorDTO(
            id: RouteID.listWindows.rawValue,
            method: "POST",
            path: "/v1/list_windows",
            category: "discovery",
            summary: "List windows for a target app query.",
            execution: RouteExecutionPolicyDTO(
                lane: .sharedRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["Window enumeration should stay outside per-window write lanes."]
            ),
            implementationStatus: .implemented,
            notes: ["Stable derived window IDs use bundle ID, pid, launch date, and window number."]
        ),
        RouteDescriptorDTO(
            id: RouteID.getWindowState.rawValue,
            method: "POST",
            path: "/v1/get_window_state",
            category: "state",
            summary: "Read the state surface for one window, including screenshot and projected tree.",
            execution: RouteExecutionPolicyDTO(
                lane: .windowRead,
                backgroundBehavior: .backgroundRequired,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .avoid,
                readActRead: false,
                allowsConcurrentClients: true,
                notes: ["Window-scoped reads should share a lane so future deduplication and caching can sit behind one contract."]
            ),
            implementationStatus: .implemented,
            notes: [
                "Default response is model-facing: resolved window, normalized screenshot, projected tree, menu/focus/selection, safety, performance, and notes.",
                "Pipeline internals stay opt-in under debug via debugMode summary/full or specific includeRawCapture/includeSemanticTree/includeProjectedTree/includePlatformProfile/includeDiagnostics flags."
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.click.rawValue,
            method: "POST",
            path: "/v1/click",
            category: "action",
            summary: "Dispatch a click against a semantic target or screenshot coordinate and return refreshed state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Uses semantic AX first for eligible targets, then native target-only SLPS/SLEvent background pointer dispatch for target-derived and direct x/y coordinates.",
                "Coordinate clicks default to a single click; double-click is used only when explicitly requested.",
                "Right and middle mouse buttons are reported as unsupported rather than mapped to hidden secondary/default actions."
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.scroll.rawValue,
            method: "POST",
            path: "/v1/scroll",
            category: "action",
            summary: "Dispatch a scroll action against a semantic target and return refreshed state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Ranks the target and ancestor panes, classifies the surface, tries AX dispatch first, then uses targeted wheel or process-scoped paging fallbacks with reread verification.",
                "The route preserves honest classifications including success, boundary, unsupported, unresolved, and verifier_ambiguous."
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.performSecondaryAction.rawValue,
            method: "POST",
            path: "/v1/perform_secondary_action",
            category: "action",
            summary: "Dispatch an exposed secondary action label against a semantic target and return verification evidence.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Dispatches an exact public secondary-action label against the requested semantic target.",
                "Dispatch is AX-only through captured action bindings; no LaunchServices, shell open, primary click, typing, keypress, or file-open fallback is used.",
                "Outcome classification is verifier-first. transports[].rawAXStatus is diagnostic AX telemetry and can report an error even when the requested effect verifies."
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.drag.rawValue,
            method: "POST",
            path: "/v1/drag",
            category: "action",
            summary: "Move a window or drag target using background-safe motion and return refreshed motion state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .allowed),
            implementationStatus: .implemented,
            notes: ["Window motion uses the shared planner/executor/verifier flow and reports background-safety observations with motion telemetry."]
        ),
        RouteDescriptorDTO(
            id: RouteID.resize.rawValue,
            method: "POST",
            path: "/v1/resize",
            category: "action",
            summary: "Resize a window from a named handle and return refreshed motion state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .allowed),
            implementationStatus: .implemented,
            notes: ["Resize shares the same window-motion stack, lane policy, and verification model as drag."]
        ),
        RouteDescriptorDTO(
            id: RouteID.setWindowFrame.rawValue,
            method: "POST",
            path: "/v1/set_window_frame",
            category: "action",
            summary: "Set a target window frame directly and return refreshed motion state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .allowed),
            implementationStatus: .implemented,
            notes: ["set_window_frame is the canonical window-layout route and shares the same motion telemetry surface as drag and resize."]
        ),
        RouteDescriptorDTO(
            id: RouteID.typeText.rawValue,
            method: "POST",
            path: "/v1/type_text",
            category: "action",
            summary: "Type text into a targeted or focused text-entry element and return verification evidence.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Uses Unicode CGEvent postToPid, optional AX focus/caret assist, cursor approach, and read-act-read verification.",
                "Default focusAssistMode is none; no app/window focus restacking or Return submission is hidden inside the route."
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.pressKey.rawValue,
            method: "POST",
            path: "/v1/press_key",
            category: "action",
            summary: "Press a key or key chord against the target window and return refreshed state.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Routes high-level chords through semantic AX operations when a generic, window-local equivalent can be verified, then falls back to WindowServer target-window preflight plus native CGEvent postToPid key delivery.",
                "The response reports the actual route used so callers can distinguish semantic actions from native key dispatch.",
                "If native key delivery dispatches but no effect is verified, the response warns callers to perform a safe click in the target content surface before retrying."
            ]
        ),
        RouteDescriptorDTO(
            id: RouteID.setValue.rawValue,
            method: "POST",
            path: "/v1/set_value",
            category: "action",
            summary: "Set a value directly on a semantic replacement target and return verification evidence.",
            execution: actionPolicy(lane: .windowWrite, mainThreadBehavior: .avoid),
            implementationStatus: .implemented,
            notes: [
                "Uses direct AXUIElementSetAttributeValue(kAXValueAttribute), typed coercion, cursor approach, settle, reread, and exact-value verification.",
                "set_value does not type, focus, press Return, submit, or auto-confirm.",
                "Outcome classification is verifier-first. rawAXStatus is diagnostic AX telemetry and does not by itself decide success or failure."
            ]
        ),
        browserRoute(
            .browserCreateWindow,
            path: "/v1/browser/create_window",
            summary: "Create a BCU-owned browser target.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserListTargets,
            path: "/v1/browser/list_targets",
            summary: "List BCU-owned browser targets."
        ),
        browserRoute(
            .browserGetState,
            path: "/v1/browser/get_state",
            summary: "Read DOM state, interactables, geometry, and screenshot evidence for an owned browser target.",
            lane: .windowRead
        ),
        browserRoute(
            .browserNavigate,
            path: "/v1/browser/navigate",
            summary: "Navigate an owned browser target and return refreshed browser state.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserEvaluateJS,
            path: "/v1/browser/evaluate_js",
            summary: "Evaluate JavaScript in an owned browser target.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserInjectJS,
            path: "/v1/browser/inject_js",
            summary: "Install named JavaScript into an owned browser target.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserRemoveInjectedJS,
            path: "/v1/browser/remove_injected_js",
            summary: "Remove a named injected script from an owned browser target.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserListInjectedJS,
            path: "/v1/browser/list_injected_js",
            summary: "List injected scripts installed on owned browser targets.",
            lane: .windowRead
        ),
        browserRoute(
            .browserClick,
            path: "/v1/browser/click",
            summary: "Move the BCU cursor to a DOM target or browser coordinate and dispatch a browser click.",
            readActRead: true
        ),
        browserRoute(
            .browserTypeText,
            path: "/v1/browser/type_text",
            summary: "Type text into a DOM target in an owned browser target.",
            readActRead: true
        ),
        browserRoute(
            .browserScroll,
            path: "/v1/browser/scroll",
            summary: "Scroll an owned browser target or DOM target.",
            readActRead: true
        ),
        browserRoute(
            .browserReload,
            path: "/v1/browser/reload",
            summary: "Reload an owned browser target and return refreshed browser state.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserClose,
            path: "/v1/browser/close",
            summary: "Close an owned browser target.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserCreateGrid,
            path: "/v1/browser/create_grid",
            summary: "Create an owned browser grid container.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserUpdateGrid,
            path: "/v1/browser/update_grid",
            summary: "Update an owned browser grid container.",
            lane: .windowWrite
        ),
        browserRoute(
            .browserGetGridState,
            path: "/v1/browser/get_grid_state",
            summary: "Read layout, cell, and screenshot state for an owned browser grid.",
            lane: .windowRead
        ),
    ]

    static func descriptor(for routeID: RouteID) -> RouteDescriptorDTO {
        descriptors.first(where: { $0.id == routeID.rawValue })!
    }

    static func bootstrapRouteDescriptors(baseURL: URL) -> [BootstrapRouteDTO] {
        descriptors.map { descriptor in
            BootstrapRouteDTO(
                id: descriptor.id,
                method: descriptor.method,
                path: descriptor.path,
                url: baseURL.appendingPathComponent(descriptor.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString,
                category: descriptor.category,
                summary: descriptor.summary
            )
        }
    }

    static func publicRoutes() -> [APIRouteDTO] {
        descriptors.map(publicRoute)
    }

    private static func publicRoute(_ descriptor: RouteDescriptorDTO) -> APIRouteDTO {
        APIRouteDTO(
            id: descriptor.id,
            method: descriptor.method,
            path: descriptor.path,
            category: descriptor.category,
            summary: descriptor.summary,
            notes: descriptor.notes,
            execution: descriptor.execution,
            implementationStatus: descriptor.implementationStatus,
            usage: APIDocumentation.usage(for: descriptor.id),
            request: requestSchema(for: descriptor.id),
            response: responseSchema(for: descriptor.id),
            errors: APIDocumentation.errors(for: descriptor.id)
        )
    }

    private static func requestSchema(for routeID: String) -> RouteBodySchemaDTO? {
        switch routeID {
        case RouteID.health.rawValue, RouteID.bootstrap.rawValue, RouteID.routes.rawValue:
            return nil
        case RouteID.listApps.rawValue:
            return json([])
        case RouteID.listWindows.rawValue:
            return json([
                field("app", "string", required: true, "App name, bundle ID, or target query.")
            ])
        case RouteID.getWindowState.rawValue:
            return json([
                field("window", "string", required: true, "Stable window ID from list_windows."),
                field("includeMenuBar", "boolean", defaultValue: "true"),
                field("menuPath", "string[]", "Optional menu path to open before reading transient menu state, e.g. [\"File\"]."),
                field("webTraversal", "visible | full", "Use full only for deep WebKit/Electron parity/debug traversal; visible keeps the fast AXVisibleChildren default for web areas.", defaultValue: "visible"),
                field("maxNodes", "integer", defaultValue: "6500"),
                field("imageMode", "path | base64 | omit", defaultValue: "path"),
                field("includeRawScreenshot", "boolean", defaultValue: "false"),
                field("debugMode", "none | summary | full", defaultValue: "none"),
                field("debug", "boolean", defaultValue: "false"),
                field("includeDiagnostics", "boolean"),
                field("includePlatformProfile", "boolean"),
                field("includeRawCapture", "boolean"),
                field("includeSemanticTree", "boolean"),
                field("includeProjectedTree", "boolean")
            ])
        case RouteID.click.rawValue:
            return clickRequestSchema()
        case RouteID.scroll.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(
                    required: true,
                    "Semantic target from get_window_state. Prefer node_id or refetch_fingerprint when available; display_index uses the rendered tree line number."
                ),
                field("direction", "up | down | left | right", required: true),
                field("pages", "integer"),
                field("verificationMode", "strict | fast"),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit"),
                debugField()
            ])
        case RouteID.performSecondaryAction.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(
                    required: true,
                    "Semantic target whose secondaryActions or secondaryActionBindings include the requested label."
                ),
                field("action", "string", required: true, "Exact public label from the target node's secondaryActions array."),
                field("actionID", "string", "Optional stable descriptor ID from secondaryActionBindings; resolves before label fallback."),
                field("menuPath", "string[]", "Optional menu path to open during the pre-action read, e.g. [\"File\"]."),
                field("webTraversal", "visible | full", "Use full only for deep WebKit/Electron parity/debug traversal; visible keeps the fast AXVisibleChildren default for web areas.", defaultValue: "visible"),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit"),
                debugField()
            ])
        case RouteID.drag.rawValue:
            return json([
                field("window", "string", required: true),
                field("toX", "number", required: true),
                field("toY", "number", required: true),
                field("cursor", "CursorRequest")
            ])
        case RouteID.resize.rawValue:
            return json([
                field("window", "string", required: true),
                field("handle", "ResizeHandle", required: true),
                field("toX", "number", required: true),
                field("toY", "number", required: true),
                field("cursor", "CursorRequest")
            ])
        case RouteID.setWindowFrame.rawValue:
            return json([
                field("window", "string", required: true),
                field("x", "number", required: true),
                field("y", "number", required: true),
                field("width", "number", required: true),
                field("height", "number", required: true),
                field("animate", "boolean", defaultValue: "true"),
                field("cursor", "CursorRequest")
            ])
        case RouteID.typeText.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(
                    required: false,
                    "Optional semantic text-entry target. Omit to type into the current focused text entry."
                ),
                field("text", "string", required: true),
                field("focusAssistMode", "none | focus | focus_and_caret_end", defaultValue: "none"),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit"),
                debugField()
            ])
        case RouteID.pressKey.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                field("key", "string", required: true),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit"),
                debugField()
            ])
        case RouteID.setValue.rawValue:
            return json([
                field("window", "string", required: true),
                field("stateToken", "string"),
                actionTargetField(
                    required: true,
                    "Semantic target that reports value-set support."
                ),
                field("value", "string", required: true),
                field("cursor", "CursorRequest"),
                field("includeMenuBar", "boolean"),
                field("maxNodes", "integer"),
                field("imageMode", "path | base64 | omit"),
                debugField()
            ])
        case RouteID.browserCreateWindow.rawValue:
            return json([
                field("url", "string"),
                field("title", "string"),
                field("profileID", "string", defaultValue: "default"),
                field("visibility", "visible | non_visible", defaultValue: "visible"),
                field("allowVisibleFallback", "boolean", "When true, a non_visible request may be promoted to visible if screenshot evidence is explicitly requested."),
                field("x", "number"),
                field("y", "number"),
                field("width", "number"),
                field("height", "number"),
                field("userAgent", "string"),
                field("imageMode", "path | base64 | omit", defaultValue: "omit"),
                debugField()
            ])
        case RouteID.browserListTargets.rawValue:
            return json([
                field("includeRegistered", "boolean", defaultValue: "false")
            ])
        case RouteID.browserGetState.rawValue:
            return json([
                field("browser", "string", required: true, "Owned browser tab/window target ID, or a grid cell target ID from browser/create_grid, browser/get_grid_state, or browser/list_targets."),
                field("maxElements", "integer", defaultValue: "500"),
                field("includeRawText", "boolean", defaultValue: "false"),
                field("imageMode", "path | base64 | omit", defaultValue: "path"),
                debugField()
            ])
        case RouteID.browserNavigate.rawValue:
            return json([
                field("browser", "string", required: true),
                field("url", "string", required: true),
                field("waitUntilLoaded", "boolean", defaultValue: "true"),
                field("timeoutMs", "integer", defaultValue: "8000"),
                field("imageMode", "path | base64 | omit", defaultValue: "path"),
                debugField()
            ])
        case RouteID.browserEvaluateJS.rawValue:
            return json([
                field("browser", "string", required: true),
                field("javaScript", "string", required: true),
                field("timeoutMs", "integer", defaultValue: "8000"),
                debugField()
            ])
        case RouteID.browserInjectJS.rawValue:
            return json([
                field("browser", "string", required: true),
                field("scriptID", "string", required: true),
                field("javaScript", "string", required: true),
                field("urlMatch", "string"),
                field("runAt", "document_start | document_end | document_idle", defaultValue: "document_idle"),
                field("persistAcrossReloads", "boolean", defaultValue: "true"),
                field("injectImmediately", "boolean", defaultValue: "true"),
                debugField()
            ])
        case RouteID.browserRemoveInjectedJS.rawValue:
            return json([
                field("browser", "string", required: true),
                field("scriptID", "string", required: true)
            ])
        case RouteID.browserListInjectedJS.rawValue:
            return json([
                field("browser", "string")
            ])
        case RouteID.browserClick.rawValue:
            return json(browserActionFields(extra: [
                field("x", "number", "Browser viewport x coordinate. Must be supplied with y and without target."),
                field("y", "number", "Browser viewport y coordinate. Must be supplied with x and without target."),
                field("clickCount", "integer", defaultValue: "1")
            ]))
        case RouteID.browserTypeText.rawValue:
            return json(browserActionFields(extra: [
                field("text", "string", required: true),
                field("append", "boolean", defaultValue: "false")
            ]))
        case RouteID.browserScroll.rawValue:
            return json(browserActionFields(extra: [
                field("direction", "up | down | left | right", required: true),
                field("pages", "integer", defaultValue: "1")
            ]))
        case RouteID.browserReload.rawValue:
            return json([
                field("browser", "string", required: true),
                field("waitUntilLoaded", "boolean", defaultValue: "true"),
                field("timeoutMs", "integer", defaultValue: "8000"),
                field("imageMode", "path | base64 | omit", defaultValue: "path"),
                debugField()
            ])
        case RouteID.browserClose.rawValue:
            return json([
                field("browser", "string", required: true)
            ])
        case RouteID.browserCreateGrid.rawValue:
            return json([
                field("title", "string"),
                field("profileID", "string", defaultValue: "default"),
                field("ephemeral", "boolean", defaultValue: "false"),
                field("visibility", "visible | non_visible", defaultValue: "visible"),
                field("layout", "BrowserGridLayout", required: true),
                field("cells", "BrowserGridCellRequest[]", required: true),
                field("x", "number"),
                field("y", "number"),
                field("width", "number"),
                field("height", "number"),
                field("imageMode", "path | base64 | omit", defaultValue: "omit"),
                debugField()
            ])
        case RouteID.browserUpdateGrid.rawValue:
            return json([
                field("grid", "string", required: true),
                field("title", "string"),
                field("layout", "BrowserGridLayout"),
                field("cells", "BrowserGridCellRequest[]", "Optional partial update matched by existing cell id."),
                field("imageMode", "path | base64 | omit", defaultValue: "omit"),
                debugField()
            ])
        case RouteID.browserGetGridState.rawValue:
            return json([
                field("grid", "string", required: true),
                field("imageMode", "path | base64 | omit", defaultValue: "omit"),
                debugField()
            ])
        default:
            return nil
        }
    }

    private static func responseSchema(for routeID: String) -> RouteBodySchemaDTO {
        switch routeID {
        case RouteID.health.rawValue:
            return json([
                field("ok", "boolean", required: true),
                field("contractVersion", "string", required: true),
                field("timestamp", "string", required: true)
            ])
        case RouteID.bootstrap.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("baseURL", "string | null", required: true),
                field("startedAt", "string | null", required: true),
                field("permissions", "RuntimePermissions", required: true),
                field("instructions", "BootstrapInstructions", required: true),
                field("guide", "APIGuide", required: true, "High-level operating flow, common concepts, response interpretation, and troubleshooting guidance."),
                field("routes", "BootstrapRoute[]", required: true)
            ])
        case RouteID.routes.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("guide", "APIGuide", required: true, "High-level operating flow, common concepts, response interpretation, and troubleshooting guidance."),
                field("routes", "APIRoute[]", required: true)
            ])
        case RouteID.listApps.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("frontmostApp", "RunningApp | null", required: true),
                field("runningApps", "RunningApp[]", required: true),
                field("notes", "string[]", required: true)
            ])
        case RouteID.listWindows.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("app", "AppReference", required: true),
                field("windows", "WindowSummary[]", required: true),
                field("notes", "string[]", required: true)
            ])
        case RouteID.getWindowState.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("stateToken", "string", required: true),
                field("window", "ResolvedWindow", required: true),
                field("screenshot", "Screenshot", required: true),
                field("tree", "AXTree", required: true),
                field("menuPresentation", "AXMenuPresentation | null"),
                field("focusedElement", "FocusedElement", required: true),
                field("selectionSummary", "AXFocusSelectionSnapshot | null"),
                field("backgroundSafety", "BackgroundSafety", required: true),
                field("performance", "ReadPerformance", required: true),
                field("debug", "GetWindowStateDebug | null"),
                field("notes", "string[]", required: true)
            ])
        case RouteID.click.rawValue:
            return clickActionResponse()
        case RouteID.scroll.rawValue:
            return scrollActionResponse()
        case RouteID.performSecondaryAction.rawValue:
            return secondaryActionResponse()
        case RouteID.drag.rawValue:
            return actionResponse("DragResponse")
        case RouteID.resize.rawValue:
            return actionResponse("ResizeResponse")
        case RouteID.setWindowFrame.rawValue:
            return actionResponse("SetWindowFrameResponse")
        case RouteID.typeText.rawValue:
            return textActionResponse("TypeTextResponse")
        case RouteID.pressKey.rawValue:
            return pressKeyActionResponse()
        case RouteID.setValue.rawValue:
            return textActionResponse("SetValueResponse")
        case RouteID.browserCreateWindow.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("target", "BrowserTarget", required: true),
                field("state", "BrowserGetStateResponse | null"),
                field("notes", "string[]", required: true)
            ])
        case RouteID.browserListTargets.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("targets", "BrowserTarget[]", required: true),
                field("notes", "string[]", required: true)
            ])
        case RouteID.browserGetState.rawValue, RouteID.browserNavigate.rawValue, RouteID.browserReload.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("stateToken", "string", required: true),
                field("target", "BrowserTarget", required: true),
                field("screenshot", "Screenshot", required: true),
                field("dom", "BrowserDOMSnapshot", required: true),
                field("performance", "BrowserPerformance", required: true),
                field("warnings", "string[]", required: true),
                field("notes", "string[]", required: true)
            ])
        case RouteID.browserEvaluateJS.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("target", "BrowserTarget", required: true),
                field("result", "JSONValue | null"),
                field("resultDescription", "string | null"),
                field("error", "string | null"),
                field("notes", "string[]", required: true)
            ])
        case RouteID.browserInjectJS.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("script", "BrowserInjectedScript", required: true),
                field("immediateResult", "BrowserEvaluateJavaScriptResponse | null"),
                field("notes", "string[]", required: true)
            ])
        case RouteID.browserRemoveInjectedJS.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("removed", "boolean", required: true),
                field("remainingScripts", "BrowserInjectedScript[]", required: true),
                field("notes", "string[]", required: true)
            ])
        case RouteID.browserListInjectedJS.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("scripts", "BrowserInjectedScript[]", required: true),
                field("notes", "string[]", required: true)
            ])
        case RouteID.browserClick.rawValue, RouteID.browserTypeText.rawValue, RouteID.browserScroll.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
                field("failureDomain", "targeting | unsupported | coercion | transport | verification | app_specific_semantics | null"),
                field("summary", "string", required: true),
                field("target", "BrowserTarget | null"),
                field("requestedTarget", "BrowserActionTarget | null"),
                field("preStateToken", "string | null"),
                field("postStateToken", "string | null"),
                field("cursor", "ActionCursorTarget", required: true),
                field("screenshot", "Screenshot | null"),
                field("warnings", "string[]", required: true),
                debugNotesField(),
                field("debug", "BrowserActionDebug | null")
            ])
        case RouteID.browserClose.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("closed", "boolean", required: true),
                field("notes", "string[]", required: true)
            ])
        case RouteID.browserCreateGrid.rawValue, RouteID.browserUpdateGrid.rawValue, RouteID.browserGetGridState.rawValue:
            return json([
                field("contractVersion", "string", required: true),
                field("ok", "boolean", required: true),
                field("grid", "BrowserGridState", required: true),
                field("notes", "string[]", required: true)
            ])
        default:
            return json([
                field("contractVersion", "string", required: true),
                field("requestID", "string", required: true),
                field("status", "string", required: true),
                field("route", "RouteSummary", required: true),
                field("target", "RouteTargetSummary", required: true),
                field("notes", "string[]", required: true)
            ])
        }
    }

    private static func actionResponse(_ type: String) -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("cursor", "CursorResponse", required: true),
            field("action", type + ".action", required: true),
            field("window", "MotionWindow", required: true),
            field("backgroundSafety", "BackgroundSafety", required: true),
            field("performance", "MotionPerformance", required: true),
            field("error", "ActionError | null")
        ])
    }

    private static func clickRequestSchema() -> RouteBodySchemaDTO {
        json([
            field("window", "string", required: true),
            field("stateToken", "string"),
            actionTargetField(
                required: false,
                "Semantic target from get_window_state. Mutually exclusive with x/y."
            ),
            field("x", "number", "Model-facing screenshot x coordinate. Must be supplied with y and without target."),
            field("y", "number", "Model-facing screenshot y coordinate. Must be supplied with x and without target."),
            field("mode", "single | double", "Explicit click mode. Omitted mode defaults to single.", defaultValue: "single"),
            field("clickCount", "integer", "Explicit exact click count. Supported values are 1 and 2."),
            field("mouseButton", "left | right | middle", defaultValue: "left"),
            field("cursor", "CursorRequest"),
            field("includeMenuBar", "boolean"),
            field("maxNodes", "integer"),
            field("imageMode", "path | base64 | omit"),
            debugField()
        ])
    }

    private static func clickActionResponse() -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | transport | verification | null"),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("requestedTarget", "ClickRequestedTarget", required: true),
            field("target", "AXActionTarget | null"),
            field("clickCount", "integer | null"),
            field("mouseButton", "left | right | middle | null"),
            field("finalRoute", "coordinate_xy | semantic_ax | ax_element_pointer_xy | semantic_ax_then_remaining_xy | rejected", required: true),
            field("fallbackReason", "none | ax_coordinate_required | ax_multi_click_requires_xy | ax_first_click_unverified_using_full_element_pointer | missing_stable_ax_coordinate | unsupported_mouse_button | invalid_click_count | invalid_target | stale_coordinate_guard | transport_failed", required: true),
            field("axAttempt", "exact_primary_ax_action | set_container_selected_rows | set_row_selected_true | safe_unique_descendant_retarget | ambiguous_descendant_click | coordinate_required | unsupported_primary_click | none | null"),
            field("coordinate", "ClickCoordinateMapping | null"),
            field("transports", "ClickTransportAttempt[]", required: true),
            field("routeSteps", "ClickRouteStep[]", required: true),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("frontmostBundleBefore", "string | null"),
            field("frontmostBundleBeforeDispatch", "string | null"),
            field("frontmostBundleAfter", "string | null"),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", "ClickVerification | null")
        ])
    }

    private static func textActionResponse(_ type: String) -> RouteBodySchemaDTO {
        var fields = [
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | coercion | transport | verification | app_specific_semantics | null"),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("target", "AXActionTarget | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("semanticAppropriate", "boolean | null"),
            field("semanticReasons", "string[]", required: true),
            field("liveElementResolution", "string | null"),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", type + ".verification | null")
        ]

        if type == "SetValueResponse" {
            fields.insert(field("requestedValue", "SetValueRequestedValue", required: true), at: 6)
            fields.insert(field("rawAXStatus", "string | null"), at: 7)
            fields.insert(field("writePrimitive", "string | null"), at: 8)
        } else if type == "TypeTextResponse" {
            fields.insert(field("text", "string", required: true), at: 6)
            fields.insert(field("focusAssistMode", "none | focus | focus_and_caret_end", required: true), at: 7)
            fields.insert(field("dispatchPrimitive", "string | null"), at: 8)
            fields.insert(field("dispatchSucceeded", "boolean | null"), at: 9)
        }

        return json(fields)
    }

    private static func pressKeyActionResponse() -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | coercion | transport | verification | app_specific_semantics | null"),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("parsedKey", "PressKeyParsedKey | null"),
            field("action", "PressKeyAction | null"),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", "PressKeyVerification | null", "Includes route-specific search, selection, text-state, selection-summary, and visual-diff evidence when available.")
        ])
    }

    private static func scrollActionResponse() -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | boundary | unsupported | unresolved | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | transport | verification | null"),
            field("issueBucket", "none | targeting | transport | verification | opacity", required: true),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("requestedTarget", "AXActionTarget | null"),
            field("chosenContainer", "AXActionTarget | null"),
            field("direction", "up | down | left | right", required: true),
            field("pages", "integer", required: true),
            field("winningMode", "background_safe_ax_ladder | post_to_pid_paging | targeted_scroll_wheel_post_to_pid | null"),
            field("winningStrategy", "ax_scroll_to_show_descendant | scrollbar_value | ax_page_action | post_to_pid_paging | targeted_scroll_wheel_post_to_pid | null"),
            field("planCandidates", "ScrollCandidate[]", required: true),
            field("transports", "ScrollTransportAttempt[]", required: true),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("frontmostBundleBefore", "string | null"),
            field("frontmostBundleBeforeDispatch", "string | null"),
            field("frontmostBundleAfter", "string | null"),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", "ScrollVerificationSummary | null"),
            field("verificationReads", "ScrollVerificationRead[]", required: true)
        ])
    }

    private static func secondaryActionResponse() -> RouteBodySchemaDTO {
        json([
            field("contractVersion", "string", required: true),
            field("ok", "boolean", required: true),
            field("classification", "success | unsupported | effect_not_verified | verifier_ambiguous", required: true),
            field("failureDomain", "targeting | unsupported | transport | verification | app_specific_semantics | null"),
            field("summary", "string", required: true),
            field("window", "ResolvedWindow | null"),
            field("requestedAction", "SecondaryActionRequested", required: true),
            field("action", "SecondaryActionAction | null", required: false, "Attempted semantic route, dispatch primitive, transport status, and detail. Null when no dispatch was attempted."),
            field("outcome", "SecondaryActionOutcome", required: true, "Verifier-oriented outcome status/reason. Use this before raw AX status when deciding what happened."),
            field("target", "AXActionTarget | null"),
            field("dispatchTarget", "AXActionTarget | null"),
            field("binding", "SecondaryActionBinding | null"),
            field("transports", "SecondaryActionTransportAttempt[]; each attempt includes rawAXStatus, transportDisposition, and transportSuccess", required: true),
            field("preStateToken", "string | null"),
            field("postStateToken", "string | null"),
            field("postState", "AXPipelineV2Response | null"),
            field("cursor", "ActionCursorTarget", required: true),
            field("warnings", "string[]", required: true),
            debugNotesField(),
            field("verification", "SecondaryActionVerification | null", required: false, "Effect-specific verifier evidence. Prefer imageMode with screenshots when visible UI interpretation matters.")
        ])
    }

    private static func json(_ fields: [RouteFieldDTO]) -> RouteBodySchemaDTO {
        RouteBodySchemaDTO(contentType: "application/json", fields: fields)
    }

    private static func field(
        _ name: String,
        _ type: String,
        required: Bool = false,
        _ description: String? = nil,
        defaultValue: String? = nil
    ) -> RouteFieldDTO {
        RouteFieldDTO(
            name: name,
            type: type,
            required: required,
            description: description,
            defaultValue: defaultValue
        )
    }

    private static func actionTargetField(
        required: Bool,
        _ description: String
    ) -> RouteFieldDTO {
        field(
            "target",
            #"{"kind":"display_index"|"node_id"|"refetch_fingerprint","value":integer|string}"#,
            required: required,
            description
        )
    }

    private static func debugField() -> RouteFieldDTO {
        field(
            "debug",
            "boolean",
            required: false,
            "When true, include verbose implementation notes in action responses.",
            defaultValue: "false"
        )
    }

    private static func debugNotesField() -> RouteFieldDTO {
        field(
            "notes",
            "string[]",
            required: false,
            "Verbose implementation notes. Present only when the request includes debug: true."
        )
    }

    private static func browserActionFields(extra: [RouteFieldDTO]) -> [RouteFieldDTO] {
        [
            field("browser", "string", required: true, "Browser target ID from browser/create_window, browser/create_grid, or browser/list_targets."),
            field("stateToken", "string"),
            field(
                "target",
                #"{"kind":"display_index"|"browser_node_id"|"dom_selector","value":integer|string}"#,
                "DOM target from browser/get_state. browser/click may use x/y instead."
            ),
            field("cursor", "CursorRequest"),
            field("imageMode", "path | base64 | omit", defaultValue: "path"),
            debugField()
        ] + extra
    }

    private static func actionPolicy(
        lane: RouteExecutionLaneDTO,
        mainThreadBehavior: MainThreadBehaviorDTO
    ) -> RouteExecutionPolicyDTO {
        RouteExecutionPolicyDTO(
            lane: lane,
            backgroundBehavior: .backgroundRequired,
            focusStealPolicy: .forbidden,
            mainThreadBehavior: mainThreadBehavior,
            readActRead: true,
            allowsConcurrentClients: true,
            notes: [
                "Mutating action routes should coordinate through a per-window write lane.",
                "If a future implementation cannot satisfy background safety, it must report that explicitly instead of silently stealing focus."
            ]
        )
    }

    private static func browserRoute(
        _ id: RouteID,
        path: String,
        summary: String,
        lane: RouteExecutionLaneDTO = .sharedRead,
        readActRead: Bool = false
    ) -> RouteDescriptorDTO {
        RouteDescriptorDTO(
            id: id.rawValue,
            method: "POST",
            path: path,
            category: "browser",
            summary: summary,
            execution: RouteExecutionPolicyDTO(
                lane: readActRead ? .windowWrite : lane,
                backgroundBehavior: .backgroundPreferred,
                focusStealPolicy: .forbidden,
                mainThreadBehavior: .required,
                readActRead: readActRead,
                allowsConcurrentClients: true,
                notes: [
                    "Stage 1 browser routes target BCU-owned browser surfaces only.",
                    "Provider registration and generic control-plane events are intentionally not part of this route surface."
                ]
            ),
            implementationStatus: .implemented,
            notes: [
                "Owned browser targets use browser target IDs, not native app/window IDs.",
                "Use hostWindow.windowID with native window routes only when a visible owned browser exposes host window metadata."
            ]
        )
    }
}
