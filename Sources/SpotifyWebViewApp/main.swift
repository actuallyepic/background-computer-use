import AppKit
import BackgroundComputerUse
import Foundation
import QuartzCore
@preconcurrency import WebKit

final class SpotifyMenuButton: NSButton {
    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityPerformPress() -> Bool {
        performClick(nil)
        return true
    }
}

final class SpotifyNativeMenuBarView: NSView {
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
    var onToggleSidebar: (() -> Void)?

    private let backButton = SpotifyMenuButton()
    private let forwardButton = SpotifyMenuButton()
    private let sidebarButton = SpotifyMenuButton()

    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setSidebarOpen(_ isOpen: Bool) {
        configureCodexButton(isOpen: isOpen)
    }

    func setNavigation(canGoBack: Bool, canGoForward: Bool) {
        configureNavigationButton(backButton, symbolName: "chevron.left", title: "Back", isEnabled: canGoBack)
        configureNavigationButton(forwardButton, symbolName: "chevron.right", title: "Forward", isEnabled: canGoForward)
    }

    func setProviderContext(_ context: String) {
        sidebarButton.toolTip = context
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1.0).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1

        let spotifyBadge = NSTextField(labelWithString: "Spotify")
        spotifyBadge.font = .systemFont(ofSize: 15, weight: .semibold)
        spotifyBadge.textColor = .white

        let liveDot = NSView()
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        liveDot.wantsLayer = true
        liveDot.layer?.cornerRadius = 5
        liveDot.layer?.backgroundColor = NSColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1.0).cgColor
        liveDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        liveDot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let titleStack = NSStackView(views: [liveDot, spotifyBadge])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 8

        configureNavigationButton(backButton, symbolName: "chevron.left", title: "Back", isEnabled: false)
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        backButton.widthAnchor.constraint(equalToConstant: 32).isActive = true

        configureNavigationButton(forwardButton, symbolName: "chevron.right", title: "Forward", isEnabled: false)
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
        forwardButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        forwardButton.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let navigationStack = NSStackView(views: [backButton, forwardButton])
        navigationStack.orientation = .horizontal
        navigationStack.alignment = .centerY
        navigationStack.spacing = 8

        configureCodexButton(isOpen: false)
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar)
        sidebarButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        sidebarButton.widthAnchor.constraint(equalToConstant: 34).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [navigationStack, titleStack, spacer, sidebarButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 92, bottom: 0, right: 18)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureNavigationButton(_ button: NSButton, symbolName: String, title: String, isEnabled: Bool) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.isEnabled = isEnabled
        button.wantsLayer = true
        button.layer?.cornerRadius = 16
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(isEnabled ? 0.74 : 0.34).cgColor
        button.contentTintColor = NSColor.white.withAlphaComponent(isEnabled ? 0.88 : 0.28)
        button.setAccessibilityLabel(title)
        button.toolTip = title
    }

    private func configureCodexButton(isOpen: Bool) {
        let title = isOpen ? "Hide Codex" : "Open Codex"
        sidebarButton.title = ""
        sidebarButton.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: title)
        sidebarButton.imagePosition = .imageOnly
        sidebarButton.bezelStyle = .regularSquare
        sidebarButton.isBordered = false
        sidebarButton.wantsLayer = true
        sidebarButton.layer?.cornerRadius = 17
        sidebarButton.layer?.backgroundColor = isOpen
            ? NSColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 0.96).cgColor
            : NSColor.white.withAlphaComponent(0.10).cgColor
        sidebarButton.contentTintColor = isOpen ? NSColor.black : NSColor.white.withAlphaComponent(0.9)
        sidebarButton.setAccessibilityLabel(title)
        sidebarButton.toolTip = title
    }

    @objc private func goBack() {
        onGoBack?()
    }

    @objc private func goForward() {
        onGoForward?()
    }

    @objc private func toggleSidebar() {
        onToggleSidebar?()
    }

}

@MainActor
final class SpotifyWebViewAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    private static let bundleIdentifier = "xyz.dubdub.spotifywebview"

    private let provider = BCUProvider(
        providerID: "xyz.dubdub.spotify-webview",
        displayName: "Spotify WebView"
    )

    private let window = NSWindow(
        contentRect: NSRect(x: 160, y: 120, width: 1280, height: 820),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    private let webView = BCUWebEnvironment.shared.makeWebView()
    private let sidebar = SpotifyCodexSidebarView()
    private let menuBar = SpotifyNativeMenuBarView()
    private let workspaceURL = SpotifyWebViewAppDelegate.discoverWorkspaceURL()
    private lazy var codexController = SpotifyCodexSidebarController(workspaceURL: workspaceURL)
    private let sidebarWidth: CGFloat = 440
    private var sidebarTrailingConstraint: NSLayoutConstraint?
    private var controlPlaneBaseURL: URL?
    private var browserTargetID: String?
    private var navigationObservations: [NSKeyValueObservation] = []
    private var isSidebarOpen: Bool {
        (sidebarTrailingConstraint?.constant ?? sidebarWidth) < 0.5 && sidebar.alphaValue > 0.01
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleInstance() else {
            NSApplication.shared.terminate(nil)
            return
        }
        configureWindow()
        configureProvider()
        configureCodexSidebar()
        loadSpotify()
        connectProvider()
        codexController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareWebViewForShutdown()
        codexController.shutdown()
        guard let controlPlaneBaseURL else { return }
        Task {
            _ = try? await provider.disconnect(from: controlPlaneBaseURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        prepareWebViewForShutdown()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationControls()
        connectProvider()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateNavigationControls()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationControls()
        sidebar.setProviderContext("Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavigationControls()
        sidebar.setProviderContext("Navigation failed: \(error.localizedDescription)")
    }

    private func configureWindow() {
        window.title = "Spotify"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        sidebar.alphaValue = 0
        sidebar.isHidden = true
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        menuBar.translatesAutoresizingMaskIntoConstraints = false
        menuBar.onGoBack = { [weak self] in
            self?.goBackFromMenuBar()
        }
        menuBar.onGoForward = { [weak self] in
            self?.goForwardFromMenuBar()
        }
        menuBar.onToggleSidebar = { [weak self] in
            self?.toggleSidebarFromMenuBar()
        }
        configureNavigationStateObservers()
        updateNavigationControls()

        root.addSubview(menuBar)
        root.addSubview(webView)
        root.addSubview(sidebar)

        sidebarTrailingConstraint = sidebar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: sidebarWidth)
        sidebarTrailingConstraint?.isActive = true

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.topAnchor.constraint(equalTo: menuBar.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            menuBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            menuBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            menuBar.topAnchor.constraint(equalTo: root.topAnchor),
            menuBar.heightAnchor.constraint(equalToConstant: 48),

            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),
            sidebar.topAnchor.constraint(equalTo: menuBar.bottomAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureCodexSidebar() {
        sidebar.onClose = { [weak self] in
            self?.closeSidebar()
        }
        sidebar.onSend = { [weak self] text in
            self?.codexController.send(text)
        }
        sidebar.onRefreshModels = { [weak self] in
            self?.codexController.refreshModels()
        }
        sidebar.onResetChat = { [weak self] in
            self?.codexController.resetChat()
        }
        sidebar.onModelSelected = { [weak self] id in
            self?.codexController.selectModel(id: id)
        }
        sidebar.onReasoningSelected = { [weak self] reasoning in
            self?.codexController.selectReasoning(reasoning)
        }
        codexController.onStatusChanged = { [weak self] status in
            self?.sidebar.setCodexStatus(status)
        }
        codexController.onProviderContextChanged = { [weak self] context in
            self?.sidebar.setProviderContext(context)
            self?.menuBar.setProviderContext(context)
        }
        codexController.onModelsChanged = { [weak self] models, selectedModelID, reasoning, selectedReasoning in
            self?.sidebar.setModels(
                models,
                selectedModelID: selectedModelID,
                reasoning: reasoning,
                selectedReasoning: selectedReasoning
            )
        }
        codexController.onBusyChanged = { [weak self] busy in
            self?.sidebar.setBusy(busy)
        }
        codexController.onMessageAppended = { [weak self] message in
            self?.sidebar.appendMessage(message)
        }
        codexController.onMessageUpdated = { [weak self] id, text in
            self?.sidebar.updateMessage(id: id, text: text)
        }
        codexController.onMessagesCleared = { [weak self] in
            self?.sidebar.clearMessages()
        }
    }

    private func configureProvider() {
        provider.pageEventHandler = { [weak self] event in
            self?.handleSidebarEvent(event)
        }
        provider.register(
            webView: webView,
            surfaceID: "spotify-main",
            title: "Spotify",
            capabilities: .defaultProviderWebView
        )
    }

    private func loadSpotify() {
        webView.load(URLRequest(url: URL(string: "https://open.spotify.com")!))
    }

    private func enforceSingleInstance() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
        guard let existing = siblings.first else {
            return true
        }
        existing.activate(options: [.activateAllWindows])
        return false
    }

    private func prepareWebViewForShutdown() {
        navigationObservations.removeAll()
        webView.stopLoading()
        let pauseScript = """
        (() => {
          try {
            document.querySelectorAll('audio,video').forEach((element) => {
              try { element.pause(); } catch (_) {}
              try { element.muted = true; } catch (_) {}
              try { element.removeAttribute('src'); element.load(); } catch (_) {}
            });
            if (navigator.mediaSession) {
              navigator.mediaSession.playbackState = 'paused';
            }
          } catch (_) {}
        })();
        """
        webView.evaluateJavaScript(pauseScript) { [weak webView] _, _ in
            webView?.loadHTMLString("", baseURL: nil)
        }
    }

    private func connectProvider() {
        guard let baseURL = discoverControlPlaneBaseURL() else {
            sidebar.setProviderContext("BCU runtime not found")
            menuBar.setProviderContext("BCU runtime not found")
            codexController.updateBCUContext(baseURL: nil, browserTargetID: nil)
            return
        }
        controlPlaneBaseURL = baseURL
        Task {
            do {
                let response = try await provider.connect(to: baseURL)
                browserTargetID = response.targets.first?.targetID
                codexController.updateBCUContext(baseURL: baseURL, browserTargetID: browserTargetID)
            } catch {
                sidebar.setProviderContext("Provider registration failed: \(error.localizedDescription)")
                menuBar.setProviderContext("Provider registration failed")
                codexController.updateBCUContext(baseURL: baseURL, browserTargetID: nil)
            }
        }
    }

    private func handleSidebarEvent(_ event: BCUProviderPageEvent) {
        codexController.recordPageEvent(type: event.type, payload: payloadDescription(event.payload))
        switch event.type {
        case "spotify.sidebar.open":
            openSidebar()
        case "spotify.sidebar.close":
            closeSidebar()
        case "spotify.sidebar.toggle":
            toggleSidebar()
        default:
            return
        }
    }

    private func toggleSidebarFromMenuBar() {
        codexController.recordPageEvent(type: "spotify.sidebar.toggle.native", payload: "native menu bar")
        toggleSidebar()
    }

    private func goBackFromMenuBar() {
        guard webView.canGoBack else {
            updateNavigationControls()
            return
        }
        codexController.recordPageEvent(type: "spotify.navigation.back.native", payload: webView.url?.absoluteString ?? "")
        webView.goBack()
        updateNavigationControls()
    }

    private func goForwardFromMenuBar() {
        guard webView.canGoForward else {
            updateNavigationControls()
            return
        }
        codexController.recordPageEvent(type: "spotify.navigation.forward.native", payload: webView.url?.absoluteString ?? "")
        webView.goForward()
        updateNavigationControls()
    }

    private func configureNavigationStateObservers() {
        navigationObservations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateNavigationControls()
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateNavigationControls()
                }
            },
        ]
    }

    private func updateNavigationControls() {
        menuBar.setNavigation(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
    }

    private func toggleSidebar() {
        if isSidebarOpen {
            closeSidebar()
        } else {
            openSidebar()
        }
    }

    private func openSidebar() {
        guard !isSidebarOpen else {
            syncSidebarButtonState(isOpen: true)
            return
        }
        let parent = sidebar.superview
        sidebar.isHidden = false
        parent?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            sidebarTrailingConstraint?.constant = 0
            sidebar.animator().alphaValue = 1
            parent?.animator().layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.sidebar.focusComposer()
            }
        }
        syncSidebarButtonState(isOpen: true)
    }

    @objc private func closeSidebar() {
        guard isSidebarOpen else {
            syncSidebarButtonState(isOpen: false)
            return
        }
        let parent = sidebar.superview
        parent?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            sidebarTrailingConstraint?.constant = sidebarWidth
            sidebar.animator().alphaValue = 0
            parent?.animator().layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.sidebar.isHidden = true
            }
        }
        syncSidebarButtonState(isOpen: false)
    }

    private func syncSidebarButtonState(isOpen: Bool) {
        menuBar.setSidebarOpen(isOpen)
    }

    private func payloadDescription(_ payload: JSONValueDTO) -> String {
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return "\(payload)"
        }
        return text
    }

    private func discoverControlPlaneBaseURL() -> URL? {
        if let raw = ProcessInfo.processInfo.environment["BCU_BASE_URL"] ?? ProcessInfo.processInfo.environment["BACKGROUND_COMPUTER_USE_BASE_URL"],
           let url = URL(string: raw) {
            return url
        }

        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        let manifestURL = URL(fileURLWithPath: tmp)
            .appendingPathComponent("background-computer-use")
            .appendingPathComponent("runtime-manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["baseURL"] as? String else {
            return nil
        }
        return URL(string: raw)
    }

    private static func discoverWorkspaceURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["SPOTIFY_WEBVIEW_WORKSPACE"] ?? environment["BCU_WORKSPACE"],
           !raw.isEmpty {
            return URL(fileURLWithPath: raw)
        }

        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: CommandLine.arguments.first ?? FileManager.default.currentDirectoryPath)
                .deletingLastPathComponent(),
        ]

        for candidate in candidates {
            if let root = packageRoot(containing: candidate) {
                return root
            }
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func packageRoot(containing url: URL) -> URL? {
        var current = url.standardizedFileURL
        let fileManager = FileManager.default
        while current.path != "/" {
            let package = current.appendingPathComponent("Package.swift")
            let spotifySource = current
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("SpotifyWebViewApp", isDirectory: true)
            if fileManager.fileExists(atPath: package.path),
               fileManager.fileExists(atPath: spotifySource.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}

let app = NSApplication.shared
let delegate = SpotifyWebViewAppDelegate()
app.delegate = delegate
app.run()
