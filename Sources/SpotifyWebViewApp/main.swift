import AppKit
import BackgroundComputerUse
import Foundation
import QuartzCore
@preconcurrency import WebKit

final class SpotifyChromeButton: NSButton {
    struct Palette {
        let fill: NSColor
        let hoverFill: NSColor
        let disabledFill: NSColor
        let tint: NSColor
        let hoverTint: NSColor
        let disabledTint: NSColor

        static let ghost = Palette(
            fill: NSColor.white.withAlphaComponent(0.04),
            hoverFill: NSColor.white.withAlphaComponent(0.12),
            disabledFill: NSColor.white.withAlphaComponent(0.03),
            tint: NSColor.white.withAlphaComponent(0.78),
            hoverTint: .white,
            disabledTint: NSColor.white.withAlphaComponent(0.40)
        )

        static let accent = Palette(
            fill: NSColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1.0),
            hoverFill: NSColor(red: 0.16, green: 0.93, blue: 0.45, alpha: 1.0),
            disabledFill: NSColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1.0),
            tint: .black,
            hoverTint: .black,
            disabledTint: .black
        )
    }

    private var palette: Palette = .ghost
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        bezelStyle = .regularSquare
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        applyState(animated: false)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool {
        performClick(nil)
        return true
    }

    override var isEnabled: Bool {
        didSet { applyState(animated: true) }
    }

    func setPalette(_ palette: Palette) {
        self.palette = palette
        applyState(animated: true)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = true
        applyState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyState(animated: true)
    }

    private func applyState(animated: Bool) {
        let fill: NSColor
        let tint: NSColor
        if !isEnabled {
            fill = palette.disabledFill
            tint = palette.disabledTint
        } else if isHovering {
            fill = palette.hoverFill
            tint = palette.hoverTint
        } else {
            fill = palette.fill
            tint = palette.tint
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                layer?.backgroundColor = fill.cgColor
                contentTintColor = tint
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = fill.cgColor
            CATransaction.commit()
            contentTintColor = tint
        }
    }
}

final class SpotifyWindow: NSWindow {
    var chromeHeight: CGFloat = 56 {
        didSet { repositionTrafficLights() }
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        repositionTrafficLights()
    }

    private func repositionTrafficLights() {
        let buttons = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton),
        ].compactMap { $0 }
        guard let first = buttons.first, let parent = first.superview else { return }
        let buttonHeight = first.frame.height
        let targetY = parent.frame.height - (chromeHeight + buttonHeight) / 2
        for button in buttons {
            var frame = button.frame
            if abs(frame.origin.y - targetY) < 0.5 { continue }
            frame.origin.y = targetY
            button.frame = frame
        }
    }
}

final class SpotifyNativeMenuBarView: NSView {
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?

    private let backButton = SpotifyChromeButton()
    private let forwardButton = SpotifyChromeButton()

    private let buttonDiameter: CGFloat = 38

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
        // Sidebar toggle is now injected into Spotify's own DOM; no native chrome state.
        _ = isOpen
    }

    func setNavigation(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }

    func setProviderContext(_ context: String) {
        toolTip = context
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        configureChromeButton(backButton, symbol: "chevron.left", title: "Back")
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.isEnabled = false

        configureChromeButton(forwardButton, symbol: "chevron.right", title: "Forward")
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
        forwardButton.isEnabled = false

        let navigationStack = NSStackView(views: [backButton, forwardButton])
        navigationStack.orientation = .horizontal
        navigationStack.alignment = .centerY
        navigationStack.spacing = 6

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [navigationStack, spacer])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 92, bottom: 0, right: 16)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureChromeButton(_ button: SpotifyChromeButton, symbol: String, title: String) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer?.cornerRadius = buttonDiameter / 2
        button.heightAnchor.constraint(equalToConstant: buttonDiameter).isActive = true
        button.widthAnchor.constraint(equalToConstant: buttonDiameter).isActive = true
        button.setPalette(.ghost)
        button.setAccessibilityLabel(title)
        button.toolTip = title
    }

    @objc private func goBack() {
        onGoBack?()
    }

    @objc private func goForward() {
        onGoForward?()
    }
}

@MainActor
final class SpotifyWebViewAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    private static let bundleIdentifier = "xyz.dubdub.spotifywebview"

    private let provider = BCUProvider(
        providerID: "xyz.dubdub.spotify-webview",
        displayName: "Spotify WebView"
    )

    private let window = SpotifyWindow(
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
    // Vertical insets so the panel slots between Spotify's top bar and the player.
    private let sidebarTopInset: CGFloat = 76
    private let sidebarBottomInset: CGFloat = 96
    private let sidebarRightMargin: CGFloat = 12
    private var sidebarTrailingConstraint: NSLayoutConstraint?
    private var controlPlaneBaseURL: URL?
    private var browserTargetID: String?
    private var navigationObservations: [NSKeyValueObservation] = []
    private var isSidebarOpen: Bool {
        (sidebarTrailingConstraint?.constant ?? sidebarWidth) < sidebarRightMargin + 0.5 && sidebar.alphaValue > 0.01
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleInstance() else {
            NSApplication.shared.terminate(nil)
            return
        }
        configureWindow()
        configureProvider()
        configureCodexSidebar()
        installSpotifyChromeUserScript()
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
        configureNavigationStateObservers()
        updateNavigationControls()

        root.addSubview(menuBar)
        root.addSubview(webView)
        root.addSubview(sidebar)

        let trailingConstraint = sidebar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: sidebarWidth)
        sidebarTrailingConstraint = trailingConstraint

        NSLayoutConstraint.activate([
            menuBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            menuBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            menuBar.topAnchor.constraint(equalTo: root.topAnchor),
            menuBar.heightAnchor.constraint(equalToConstant: 56),

            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.topAnchor.constraint(equalTo: menuBar.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),
            sidebar.topAnchor.constraint(equalTo: menuBar.bottomAnchor, constant: sidebarTopInset),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -sidebarBottomInset),
            trailingConstraint,
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
        codexController.onMessageUpdated = { [weak self] message in
            self?.sidebar.updateMessage(message)
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

    private func installSpotifyChromeUserScript() {
        let source = """
        (function() {
          if (window.__bcuSpotifyChromeInstalled) return;
          window.__bcuSpotifyChromeInstalled = true;

          var SPARKLES_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true">' +
            '<path d="M12 2 L13.6 8.4 L20 10 L13.6 11.6 L12 18 L10.4 11.6 L4 10 L10.4 8.4 Z M18.5 2 L19.2 4.3 L21.5 5 L19.2 5.7 L18.5 8 L17.8 5.7 L15.5 5 L17.8 4.3 Z M5.5 14 L6.2 16.3 L8.5 17 L6.2 17.7 L5.5 20 L4.8 17.7 L2.5 17 L4.8 16.3 Z"/>' +
            '</svg>';

          function hideInstall() {
            var nodes = document.querySelectorAll('a, button');
            for (var i = 0; i < nodes.length; i++) {
              var el = nodes[i];
              var text = (el.textContent || '').trim();
              var aria = el.getAttribute('aria-label') || '';
              if (/^install\\s+app$/i.test(text) || /^install\\s+app$/i.test(aria)) {
                el.style.setProperty('display', 'none', 'important');
              }
            }
          }

          function findProfile() {
            var sels = [
              '[data-testid="user-widget-link"]',
              'button[data-testid="user-widget-button"]',
              '[data-testid="user-widget"]',
              '[data-testid="user-widget-avatar"]',
              '[data-testid="user-avatar"]'
            ];
            for (var i = 0; i < sels.length; i++) {
              var el = document.querySelector(sels[i]);
              if (el) return el;
            }
            return null;
          }

          function buttonHost(profile) {
            // Walk up to the topbar action group so siblings are the other top-bar icons.
            var cur = profile;
            for (var i = 0; i < 4 && cur; i++) {
              if (cur.parentElement && cur.parentElement.children.length > 1) {
                return { host: cur.parentElement, anchor: cur };
              }
              cur = cur.parentElement;
            }
            return profile.parentElement ? { host: profile.parentElement, anchor: profile } : null;
          }

          function ensureSparkles() {
            var profile = findProfile();
            if (!profile) return false;
            var host = buttonHost(profile);
            if (!host) return false;
            if (host.host.querySelector('[data-bcu-sparkles]')) return true;

            var btn = document.createElement('button');
            btn.setAttribute('data-bcu-sparkles', 'true');
            btn.setAttribute('aria-label', 'Toggle Spotify AI');
            btn.title = 'Spotify AI';
            btn.type = 'button';
            btn.innerHTML = SPARKLES_SVG;
            btn.style.cssText = [
              'width:32px',
              'height:32px',
              'min-width:32px',
              'min-height:32px',
              'background:transparent',
              'border:0',
              'border-radius:9999px',
              'color:rgba(255,255,255,0.7)',
              'display:inline-flex',
              'align-items:center',
              'justify-content:center',
              'align-self:center',
              'vertical-align:middle',
              'cursor:pointer',
              'padding:0',
              'margin:0',
              'transition:color 120ms ease',
              'flex:0 0 auto',
              'position:relative',
              'pointer-events:auto'
            ].join(';');
            btn.addEventListener('mouseenter', function() {
              btn.style.color = 'rgba(255,255,255,1)';
            });
            btn.addEventListener('mouseleave', function() {
              btn.style.color = 'rgba(255,255,255,0.7)';
            });
            function fire(e) {
              if (e) {
                e.preventDefault();
                e.stopPropagation();
                if (typeof e.stopImmediatePropagation === 'function') {
                  e.stopImmediatePropagation();
                }
              }
              if (window.__bcu && typeof window.__bcu.emit === 'function') {
                window.__bcu.emit('spotify.sidebar.toggle', { source: 'spotify-topbar' });
              }
            }
            // Capture-phase pointerdown wins over Spotify's document-level handlers.
            btn.addEventListener('pointerdown', fire, true);
            btn.addEventListener('click', function(e) {
              e.preventDefault();
              e.stopPropagation();
            }, true);
            host.host.insertBefore(btn, host.anchor);
            return true;
          }

          var pending = false;
          function tick() {
            try { hideInstall(); ensureSparkles(); } catch (e) { /* swallow */ }
          }
          function schedule() {
            if (pending) return;
            pending = true;
            requestAnimationFrame(function() { pending = false; tick(); });
          }

          tick();
          var obs = new MutationObserver(schedule);
          obs.observe(document.documentElement, { childList: true, subtree: true });
          // Re-run every 2s as a safety net for SPA mutations the observer might miss.
          setInterval(tick, 2000);
        })();
        """

        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
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
            sidebarTrailingConstraint?.animator().constant = -sidebarRightMargin
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
            sidebarTrailingConstraint?.animator().constant = sidebarWidth
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

        if let resourceURL = Bundle.main.url(forResource: "workspace-path", withExtension: "txt"),
           let raw = try? String(contentsOf: resourceURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return URL(fileURLWithPath: raw)
        }

        for candidate in workspaceCandidateURLs(environment: environment) {
            if let root = packageRoot(containing: candidate) {
                return root
            }
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func workspaceCandidateURLs(environment: [String: String]) -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates: [URL] = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
            URL(fileURLWithPath: CommandLine.arguments.first ?? fileManager.currentDirectoryPath)
                .deletingLastPathComponent(),
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
        ]

        if let rawPWD = environment["PWD"], !rawPWD.isEmpty {
            candidates.append(URL(fileURLWithPath: rawPWD))
        }

        for base in [
            home,
            home.appendingPathComponent("dubdubdebug", isDirectory: true),
            home.appendingPathComponent("Developer", isDirectory: true),
            home.appendingPathComponent("Projects", isDirectory: true),
            home.appendingPathComponent("Code", isDirectory: true),
        ] {
            candidates.append(base.appendingPathComponent("background-computer-use", isDirectory: true))
            candidates.append(base.appendingPathComponent("BackgroundComputerUse", isDirectory: true))
            candidates.append(base.appendingPathComponent("spotify-background-computer-use", isDirectory: true))
            candidates.append(base.appendingPathComponent("SpotifyBackgroundComputerUse", isDirectory: true))
        }

        var seen = Set<String>()
        return candidates.compactMap { url in
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return nil }
            return standardized
        }
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
