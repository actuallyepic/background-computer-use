import Testing
import BackgroundComputerUse
import Foundation

@Suite
struct RuntimeFacadePublicAPITests {
    @Test
    func testRuntimeFacadeIsImportableWithoutTestableImport() {
        let runtime = BackgroundComputerUseRuntime()
        let permissions = runtime.permissions()
        let apps = runtime.listApps()

        #expect(!permissions.checkedAt.isEmpty)
        #expect(!apps.contractVersion.isEmpty)
        _ = apps.runningApps
    }

    @Test
    func testPublicRequestDTOsAreConstructible() throws {
        let cursor = CursorRequestDTO(id: "agent-1", name: "Agent", color: "#20C46B")
        let target = try ActionTargetRequestDTO.displayIndex(3)

        let listWindows = ListWindowsRequest(app: "Safari")
        let state = GetWindowStateRequest(window: "window-id", imageMode: .path)
        let click = ClickRequest(window: "window-id", target: target, clickCount: 1, cursor: cursor)
        let coordinateClick = ClickRequest(window: "window-id", x: 10, y: 20)
        let scroll = ScrollRequest(window: "window-id", target: target, direction: .down)
        let secondary = PerformSecondaryActionRequest(window: "window-id", target: target, action: "show_menu")
        let drag = DragRequest(window: "window-id", toX: 100, toY: 120)
        let resize = ResizeRequest(window: "window-id", handle: .bottomRight, toX: 300, toY: 320)
        let frame = SetWindowFrameRequest(window: "window-id", x: 10, y: 20, width: 500, height: 400)
        let typeText = TypeTextRequest(window: "window-id", target: target, text: "hello")
        let pressKey = PressKeyRequest(window: "window-id", key: "command+a")
        let setValue = SetValueRequest(window: "window-id", target: target, value: "hello")
        let browserTarget = BrowserActionTargetRequestDTO.displayIndex(1)
        let browserCreate = try BrowserCreateWindowRequest(
            url: "https://example.com",
            profileID: "default",
            visibility: .visible,
            activate: false,
            imageMode: .omit
        )
        let browserState = BrowserGetStateRequest(browser: "bt_target", imageMode: .path)
        let browserNavigate = BrowserNavigateRequest(browser: "bt_target", url: "https://example.com")
        let browserEvaluate = BrowserEvaluateJavaScriptRequest(browser: "bt_target", javaScript: "document.title")
        let browserInject = BrowserInjectJavaScriptRequest(browser: "bt_target", scriptID: "helper", javaScript: "window.__helper = true;")
        let browserRemove = BrowserRemoveInjectedJavaScriptRequest(browser: "bt_target", scriptID: "helper")
        let browserScripts = BrowserListInjectedJavaScriptRequest(browser: "bt_target")
        let browserClick = BrowserClickRequest(browser: "bt_target", target: browserTarget, clickCount: 1, cursor: cursor)
        let browserType = BrowserTypeTextRequest(browser: "bt_target", target: browserTarget, text: "hello")
        let browserScroll = BrowserScrollRequest(browser: "bt_target", target: browserTarget, direction: .down)
        let browserReload = BrowserReloadRequest(browser: "bt_target")
        let browserClose = BrowserCloseRequest(browser: "bt_target")
        let gridCell = try BrowserGridCellRequestDTO(id: "app", url: "http://localhost:3000", profileID: "dev-local")
        let gridLayout = BrowserGridLayoutDTO(columns: 2, rows: 1, gap: 8)
        let gridCreate = try BrowserCreateGridRequest(
            title: "Dev Grid",
            profileID: "default",
            visibility: .visible,
            layout: gridLayout,
            cells: [gridCell],
            imageMode: .omit
        )
        let gridUpdate = BrowserUpdateGridRequest(grid: "bg_grid", layout: gridLayout, cells: [gridCell])
        let gridState = BrowserGetGridStateRequest(grid: "bg_grid", imageMode: .omit)

        #expect(listWindows.app == "Safari")
        #expect(state.imageMode == .path)
        #expect(click.target?.displayIndex == 3)
        #expect(coordinateClick.x == 10)
        #expect(scroll.direction == .down)
        #expect(secondary.action == "show_menu")
        #expect(drag.toX == 100)
        #expect(resize.handle == .bottomRight)
        #expect(frame.width == 500)
        #expect(typeText.text == "hello")
        #expect(pressKey.key == "command+a")
        #expect(setValue.value == "hello")
        #expect(browserCreate.profileID == "default")
        #expect(browserCreate.visibility == .visible)
        #expect(browserCreate.activate == false)
        #expect(browserState.browser == "bt_target")
        #expect(browserNavigate.url == "https://example.com")
        #expect(browserEvaluate.javaScript == "document.title")
        #expect(browserInject.scriptID == "helper")
        #expect(browserRemove.scriptID == "helper")
        #expect(browserScripts.browser == "bt_target")
        #expect(browserClick.target?.kind == .displayIndex)
        #expect(browserType.text == "hello")
        #expect(browserScroll.direction == .down)
        #expect(browserReload.browser == "bt_target")
        #expect(browserClose.browser == "bt_target")
        #expect(gridCell.profileID == "dev-local")
        #expect(gridCreate.layout.columns == 2)
        #expect(gridUpdate.grid == "bg_grid")
        #expect(gridState.grid == "bg_grid")
    }

    @Test
    func testPublicTargetFactoriesValidateLikeHTTPDecoding() {
        #expect(throws: ActionTargetRequestValidationError.self) {
            try ActionTargetRequestDTO.displayIndex(-1)
        }
        #expect(throws: ActionTargetRequestValidationError.self) {
            try ActionTargetRequestDTO.nodeID("  ")
        }
        #expect(throws: ActionTargetRequestValidationError.self) {
            try ActionTargetRequestDTO.refetchFingerprint("")
        }
    }

    @Test
    func testBrowserRequestValidationMatchesHTTPDecoding() throws {
        let decoder = JSONDecoder()

        let defaults = try decoder.decode(
            BrowserCreateWindowRequest.self,
            from: Data(#"{"url":"https://example.com"}"#.utf8)
        )
        #expect(defaults.profileID == "default")
        #expect(defaults.visibility == .visible)
        #expect(defaults.activate == false)

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(
                BrowserCreateWindowRequest.self,
                from: Data(#"{"profileID":"../default"}"#.utf8)
            )
        }

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(
                BrowserCreateWindowRequest.self,
                from: Data(#"{"visibility":"background"}"#.utf8)
            )
        }

        #expect(throws: BrowserProfileValidationError.self) {
            _ = try BrowserProfileDTO(profileID: "bad/path")
        }

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(
                BrowserGridCellRequestDTO.self,
                from: Data(#"{"id":"   ","url":"https://example.com"}"#.utf8)
            )
        }

        #expect(throws: BrowserSurfaceRequestValidationError.self) {
            _ = try decoder.decode(
                BrowserCreateGridRequest.self,
                from: Data(#"{"layout":{"kind":"grid","columns":2,"rows":1},"cells":[{"id":"app"},{"id":"app"}]}"#.utf8)
            )
        }
    }

    @Test
    func testBrowserRoutesAreInPublicCatalogWithoutProviderRoutes() {
        let runtime = BackgroundComputerUseRuntime()
        let routeIDs = Set(runtime.routeCatalog().routes.map(\.id))

        for expected in [
            "browser_create_window",
            "browser_list_targets",
            "browser_get_state",
            "browser_navigate",
            "browser_evaluate_js",
            "browser_inject_js",
            "browser_remove_injected_js",
            "browser_list_injected_js",
            "browser_click",
            "browser_type_text",
            "browser_scroll",
            "browser_reload",
            "browser_close",
            "browser_create_grid",
            "browser_update_grid",
            "browser_get_grid_state",
        ] {
            #expect(routeIDs.contains(expected))
        }

        #expect(!routeIDs.contains("browser_register_provider"))
        #expect(!routeIDs.contains("browser_unregister_provider"))
        #expect(!routeIDs.contains("events_emit"))
        #expect(!routeIDs.contains("events_poll"))
        #expect(!routeIDs.contains("events_clear"))
    }
}
