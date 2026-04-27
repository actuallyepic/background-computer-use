import Testing
import BackgroundComputerUse

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
        let browserTarget = BrowserActionTargetRequestDTO.domSelector("#name")
        let browserCreate = BrowserCreateWindowRequest(url: "about:blank", title: "Owned Browser")
        let browserState = BrowserGetStateRequest(browser: "bt_1", imageMode: .omit)
        let browserEvaluate = BrowserEvaluateJavaScriptRequest(browser: "bt_1", javaScript: "document.title")
        let browserClick = BrowserClickRequest(browser: "bt_1", target: browserTarget, cursor: cursor)
        let browserCoordinateClick = BrowserClickRequest(browser: "bt_1", x: 10, y: 20)
        let browserType = BrowserTypeTextRequest(browser: "bt_1", target: browserTarget, text: "Ada")
        let browserScroll = BrowserScrollRequest(browser: "bt_1", target: browserTarget, direction: .down)
        let browserInject = BrowserInjectJavaScriptRequest(
            browser: "bt_1",
            scriptID: "helper",
            javaScript: "window.__bcu.emit('ready')"
        )
        let browserEvent = BrowserEmitEventRequest(
            browser: "bt_1",
            scriptID: "helper",
            type: "ready",
            payload: .object(["ok": .bool(true)])
        )
        let browserCaps = BrowserTargetCapabilitiesDTO(
            readDom: true,
            evaluateJavaScript: true,
            injectJavaScript: true,
            emitPageEvents: true,
            dispatchDomEvents: true,
            nativeClickFallback: false,
            screenshot: true,
            hostWindowMetadata: true
        )
        let providerSurface = BrowserRegisteredProviderSurfaceDTO(
            surfaceID: "main",
            title: "Registered Browser",
            url: "http://localhost:3000",
            capabilities: browserCaps
        )
        let provider = BrowserRegisterProviderRequest(
            providerID: "com.example.browser",
            displayName: "Example",
            protocolVersion: 1,
            browserSurfaces: [providerSurface]
        )

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
        #expect(browserCreate.title == "Owned Browser")
        #expect(browserState.imageMode == .omit)
        #expect(browserEvaluate.javaScript == "document.title")
        #expect(browserClick.target?.value == "#name")
        #expect(browserCoordinateClick.x == 10)
        #expect(browserType.text == "Ada")
        #expect(browserScroll.direction == .down)
        #expect(browserInject.scriptID == "helper")
        #expect(browserEvent.type == "ready")
        #expect(provider.browserSurfaces.first?.capabilities.readDom == true)
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
}
