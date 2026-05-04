import AppKit
import Foundation
@preconcurrency import WebKit

private struct InstalledBrowserScript {
    let dto: BrowserInjectedScriptDTO
    let javaScript: String
}

private struct BrowserResolveResult: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let message: String?
    let element: BrowserInteractableDTO?
    let candidates: [BrowserInteractableDTO]?
}

@MainActor
private final class BrowserTabHost {
    let window: NSWindow

    private let rootView: NSView
    private let tabStrip: NSStackView
    private let contentView: NSView
    private var tabs: [String: OwnedBrowserSurface] = [:]
    private var buttons: [String: NSButton] = [:]
    private var activeTabID: String?

    init(window: NSWindow, preferredContentSize: CGSize) {
        self.window = window
        let contentSize = preferredContentSize.width > 0 && preferredContentSize.height > 0
            ? preferredContentSize
            : window.contentRect(forFrameRect: window.frame).size
        rootView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        rootView.translatesAutoresizingMaskIntoConstraints = true
        rootView.autoresizingMask = [.width, .height]

        tabStrip = NSStackView()
        tabStrip.orientation = .horizontal
        tabStrip.alignment = .centerY
        tabStrip.distribution = .fill
        tabStrip.spacing = 6
        tabStrip.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        tabStrip.translatesAutoresizingMaskIntoConstraints = true
        tabStrip.autoresizingMask = [.width, .minYMargin]

        contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        contentView.translatesAutoresizingMaskIntoConstraints = true
        contentView.autoresizingMask = [.width, .height]

        rootView.addSubview(tabStrip)
        rootView.addSubview(contentView)
        window.contentView = rootView
        window.minSize = NSSize(width: 480, height: 360)
        window.setContentSize(contentSize)
        updateStripVisibility()
    }

    var contentBounds: CGRect {
        contentView.bounds
    }

    func addTab(_ surface: OwnedBrowserSurface, activate: Bool) {
        tabs[surface.tabTargetID] = surface
        surface.attachBrowserWebView(to: contentView)

        let button = NSButton(title: surface.tabStripTitle, target: self, action: #selector(selectTab(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(surface.tabTargetID)
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = true
        button.frame.size = NSSize(width: min(max(Double(button.title.count) * 7 + 28, 92), 240), height: 24)
        buttons[surface.tabTargetID] = button
        tabStrip.addArrangedSubview(button)

        if activate || activeTabID == nil {
            activateTab(surface.tabTargetID)
        } else {
            surface.setBrowserTabVisible(false)
        }
        updateStripVisibility()
    }

    func removeTab(_ surface: OwnedBrowserSurface) {
        let wasActive = activeTabID == surface.tabTargetID
        tabs.removeValue(forKey: surface.tabTargetID)
        if let button = buttons.removeValue(forKey: surface.tabTargetID) {
            tabStrip.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        surface.disposeBrowserWebView()

        if tabs.isEmpty {
            activeTabID = nil
            updateStripVisibility()
            window.close()
            return
        }

        if wasActive {
            activateTab(tabs.keys.sorted().first ?? "")
        }
        updateStripVisibility()
    }

    func closeAllTabs() {
        for surface in tabs.values {
            surface.disposeBrowserWebView()
        }
        tabs.removeAll()
        for button in buttons.values {
            tabStrip.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        buttons.removeAll()
        activeTabID = nil
        updateStripVisibility()
    }

    func updateTab(_ surface: OwnedBrowserSurface) {
        buttons[surface.tabTargetID]?.title = surface.tabStripTitle
        if activeTabID == surface.tabTargetID {
            window.title = surface.tabStripTitle
        }
    }

    func isActive(_ surface: OwnedBrowserSurface) -> Bool {
        activeTabID == surface.tabTargetID
    }

    func activeSurface() -> OwnedBrowserSurface? {
        activeTabID.flatMap { tabs[$0] }
    }

    func activateSurface(_ surface: OwnedBrowserSurface) {
        activateTab(surface.tabTargetID)
    }

    @objc private func selectTab(_ sender: NSButton) {
        guard let tabID = sender.identifier?.rawValue else { return }
        activateTab(tabID)
    }

    private func activateTab(_ tabID: String) {
        guard tabs[tabID] != nil else { return }
        activeTabID = tabID
        for (candidateID, surface) in tabs {
            let isActive = candidateID == tabID
            surface.setBrowserTabVisible(isActive)
            buttons[candidateID]?.state = isActive ? .on : .off
        }
        tabs[tabID]?.activateBrowserTabInterface()
    }

    private func updateStripVisibility() {
        let showTabs = tabs.count > 1
        tabStrip.isHidden = !showTabs
        layoutViews(showTabs: showTabs)
    }

    private func layoutViews(showTabs: Bool) {
        let bounds = rootView.bounds
        let tabHeight: CGFloat = showTabs ? 34 : 0
        tabStrip.frame = NSRect(x: 0, y: max(bounds.height - tabHeight, 0), width: bounds.width, height: tabHeight)
        contentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height - tabHeight, 1))
        for surface in tabs.values {
            surface.resizeHostedBrowserWebView(to: contentView.bounds)
        }
    }
}

@MainActor
final class BrowserSurfaceRegistry {
    static let shared = BrowserSurfaceRegistry()

    private var ownedSurfacesByWindowID: [String: OwnedBrowserSurface] = [:]
    private var ownedSurfacesByTabID: [String: OwnedBrowserSurface] = [:]
    private var ownedSurfacesByHostWindowID: [String: OwnedBrowserSurface] = [:]
    private var gridSurfacesByGridID: [String: BrowserGridSurface] = [:]
    private var gridSurfacesByCellID: [String: BrowserGridSurface] = [:]
    private var gridSurfacesByHostWindowID: [String: BrowserGridSurface] = [:]

    private init() {}

    func createWindow(request: BrowserCreateWindowRequest) throws -> OwnedBrowserSurface {
        let surface = try OwnedBrowserSurface(request: request)
        registerOwnedSurface(surface)
        return surface
    }

    func createPopupWindow(
        opener: OwnedBrowserSurface,
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures
    ) throws -> OwnedBrowserSurface {
        let surface = try OwnedBrowserSurface(
            popupFrom: opener,
            configuration: configuration,
            windowFeatures: windowFeatures
        )
        registerOwnedSurface(surface)
        BrowserEventStore.shared.emit(
            targetID: opener.tabTargetID,
            scriptID: nil,
            type: "browser_popup_created",
            payload: .object([
                "popupTargetID": .string(surface.tabTargetID),
                "popupWindowTargetID": .string(surface.windowTargetID)
            ])
        )
        return surface
    }

    func registerOwnedSurface(_ surface: OwnedBrowserSurface) {
        ownedSurfacesByTabID[surface.tabTargetID] = surface
        if surface.ownsBrowserWindow || ownedSurfacesByWindowID[surface.windowTargetID] == nil {
            ownedSurfacesByWindowID[surface.windowTargetID] = surface
            ownedSurfacesByHostWindowID[surface.hostWindowID()] = surface
        }
    }

    func unregisterOwnedSurface(_ surface: OwnedBrowserSurface) {
        ownedSurfacesByTabID.removeValue(forKey: surface.tabTargetID)
        if surface.ownsBrowserWindow {
            ownedSurfacesByWindowID.removeValue(forKey: surface.windowTargetID)
            ownedSurfacesByHostWindowID.removeValue(forKey: surface.hostWindowID())
        }
    }

    func unregisterOwnedWindow(windowTargetID: String) {
        let tabs = ownedSurfacesByTabID.values.filter { $0.windowTargetID == windowTargetID }
        for tab in tabs {
            ownedSurfacesByTabID.removeValue(forKey: tab.tabTargetID)
        }
        if let owner = ownedSurfacesByWindowID.removeValue(forKey: windowTargetID) {
            ownedSurfacesByHostWindowID.removeValue(forKey: owner.hostWindowID())
        }
    }

    func listTargets() -> [BrowserTargetSummaryDTO] {
        var seenWindows: Set<String> = []
        var owned: [BrowserTargetSummaryDTO] = []
        for surface in ownedSurfacesByTabID.values.sorted(by: { $0.tabTargetID < $1.tabTargetID }) {
            if seenWindows.insert(surface.windowTargetID).inserted,
               let owner = ownedSurfacesByWindowID[surface.windowTargetID] {
                owned.append((owner.activeSurfaceInWindow() ?? owner).windowSummary())
            }
            owned.append(surface.tabSummary())
        }
        let grids = gridSurfacesByGridID.values
            .sorted { $0.gridTargetID < $1.gridTargetID }
            .flatMap { [$0.gridSummary()] + $0.cellSummaries().compactMap(\.target) }
        return owned + grids
    }

    func ownedSurface(for targetID: String) throws -> OwnedBrowserSurface {
        if let surface = ownedSurfacesByTabID[targetID] {
            return surface
        }
        if let surface = ownedSurfacesByWindowID[targetID] {
            return surface.activeSurfaceInWindow() ?? surface
        }
        if let grid = gridSurfacesByCellID[targetID],
           let surface = grid.cellSurface(for: targetID) {
            return surface
        }
        throw BrowserSurfaceError.targetNotFound(targetID)
    }

    func coordinationID(for targetID: String) throws -> String {
        if let surface = ownedSurfacesByTabID[targetID] ?? ownedSurfacesByWindowID[targetID] {
            return surface.windowTargetID
        }
        if let grid = gridSurfacesByGridID[targetID] ?? gridSurfacesByCellID[targetID] {
            return grid.gridTargetID
        }
        throw BrowserSurfaceError.targetNotFound(targetID)
    }

    func summary(for targetID: String) throws -> BrowserTargetSummaryDTO {
        if let surface = ownedSurfacesByTabID[targetID] {
            return surface.tabSummary()
        }
        if let surface = ownedSurfacesByWindowID[targetID] {
            return (surface.activeSurfaceInWindow() ?? surface).windowSummary()
        }
        if let grid = gridSurfacesByGridID[targetID] {
            return grid.gridSummary()
        }
        if let grid = gridSurfacesByCellID[targetID],
           let summary = grid.cellSummary(for: targetID) {
            return summary.target
        }
        throw BrowserSurfaceError.targetNotFound(targetID)
    }

    func activateOwnedSurface(for targetID: String) throws -> OwnedBrowserSurface {
        let surface = try ownedSurface(for: targetID)
        surface.activateForTargeting()
        return surface
    }

    func surfaceForPostActionState(startingFrom targetID: String) throws -> OwnedBrowserSurface {
        let surface = try ownedSurface(for: targetID)
        return surface.activeSurfaceInWindow() ?? surface
    }

    func unregisterGrid(gridTargetID: String) {
        guard let grid = gridSurfacesByGridID.removeValue(forKey: gridTargetID) else { return }
        gridSurfacesByHostWindowID.removeValue(forKey: grid.hostWindowID())
        for cellID in grid.cellTargetIDs {
            gridSurfacesByCellID.removeValue(forKey: cellID)
        }
    }

    func unregisterGridCell(targetID: String) {
        gridSurfacesByCellID.removeValue(forKey: targetID)
    }

    func createGrid(request: BrowserCreateGridRequest) throws -> BrowserGridSurface {
        let grid = try BrowserGridSurface(request: request)
        gridSurfacesByGridID[grid.gridTargetID] = grid
        gridSurfacesByHostWindowID[grid.hostWindowID()] = grid
        for cell in grid.cellTargetIDs {
            gridSurfacesByCellID[cell] = grid
        }
        return grid
    }

    func gridSurface(for targetID: String) throws -> BrowserGridSurface {
        if let grid = gridSurfacesByGridID[targetID] ?? gridSurfacesByCellID[targetID] {
            return grid
        }
        throw BrowserSurfaceError.targetNotFound(targetID)
    }

    func close(targetID: String) throws -> Bool {
        if let grid = gridSurfacesByGridID[targetID] {
            unregisterGrid(gridTargetID: grid.gridTargetID)
            grid.close()
            return true
        }
        if let grid = gridSurfacesByCellID[targetID] {
            let closed = grid.closeCell(targetID: targetID)
            if closed {
                gridSurfacesByCellID.removeValue(forKey: targetID)
            }
            return closed
        }
        if let windowOwner = ownedSurfacesByWindowID[targetID] {
            unregisterOwnedWindow(windowTargetID: windowOwner.windowTargetID)
            windowOwner.close()
            return true
        }
        let surface = try ownedSurfacesByTabID[targetID] ?? ownedSurface(for: targetID)
        if surface.ownsBrowserWindow {
            unregisterOwnedWindow(windowTargetID: surface.windowTargetID)
        } else {
            unregisterOwnedSurface(surface)
        }
        surface.close()
        return true
    }

    func setOwnedHostWindowFrame(
        windowID: String,
        frame: CGRect,
        animate: Bool
    ) -> (before: ResolvedWindowDTO, after: ResolvedWindowDTO)? {
        let surface = ownedSurfacesByHostWindowID[windowID] ?? ownedSurfacesByTabID.values.first {
            $0.hostWindowID() == windowID
        }
        guard let surface else {
            if let grid = gridSurfacesByHostWindowID[windowID] ?? gridSurfacesByGridID.values.first(where: { $0.hostWindowID() == windowID }) {
                gridSurfacesByHostWindowID[grid.hostWindowID()] = grid
                let before = grid.resolvedWindowDTO()
                grid.setHostFrame(frame, animate: animate)
                let after = grid.resolvedWindowDTO()
                gridSurfacesByHostWindowID[after.windowID] = grid
                return (before, after)
            }
            return nil
        }
        ownedSurfacesByHostWindowID[surface.hostWindowID()] = surface
        let before = surface.resolvedWindowDTO()
        surface.setHostFrame(frame, animate: animate)
        let after = surface.resolvedWindowDTO()
        ownedSurfacesByHostWindowID[after.windowID] = surface
        return (before, after)
    }
}

@MainActor
final class BrowserGridSurface: NSObject, NSWindowDelegate {
    let gridTargetID: String
    let profileID: String
    let visibility: BrowserVisibilityDTO

    private let window: NSWindow
    private let contentView: NSView
    private var layout: BrowserGridLayoutDTO
    private var cells: [OwnedBrowserSurface] = []
    private var isClosed = false

    init(request: BrowserCreateGridRequest) throws {
        gridTargetID = "bg_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        visibility = request.visibility ?? .visible
        profileID = try BrowserProfileStore.shared.resolvedProfileID(request.profileID)
        layout = try BrowserGridSurface.sanitizedLayout(request.layout, cellCount: request.cells.count)

        let frame = NSRect(
            x: request.x ?? 80,
            y: request.y ?? 80,
            width: max(request.width ?? 1440, 640),
            height: max(request.height ?? 900, 420)
        )
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = request.title ?? "Browser Grid"
        window.isReleasedWhenClosed = false
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        super.init()
        window.delegate = self

        let frames = BrowserGridSurface.cellFrames(layout: layout, bounds: contentView.bounds, count: request.cells.count)
        for (index, cellRequest) in request.cells.enumerated() {
            let cell = try OwnedBrowserSurface(
                gridTargetID: gridTargetID,
                cellRequest: cellRequest,
                defaultProfileID: profileID,
                defaultEphemeral: request.ephemeral,
                visibility: visibility,
                parentWindow: window,
                containerView: contentView,
                frame: frames[index]
            )
            cells.append(cell)
        }

        if visibility == .visible {
            window.orderFrontRegardless()
        }
        rememberHostWindow()
    }

    var cellTargetIDs: [String] {
        cells.map(\.tabTargetID)
    }

    func cellSurface(for targetID: String) -> OwnedBrowserSurface? {
        cells.first { $0.tabTargetID == targetID }
    }

    func gridSummary() -> BrowserTargetSummaryDTO {
        BrowserTargetSummaryDTO(
            targetID: gridTargetID,
            kind: .ownedBrowserGrid,
            ownerApp: "BackgroundComputerUse",
            title: window.title,
            url: nil,
            isLoading: cells.contains { $0.tabSummary().isLoading },
            parentTargetID: nil,
            visibility: visibility,
            profileID: profileID,
            hostWindow: hostWindowDTO(),
            capabilities: BrowserTargetCapabilitiesDTO(
                readDom: false,
                evaluateJavaScript: false,
                injectJavaScript: false,
                emitPageEvents: false,
                dispatchDomEvents: false,
                nativeClickFallback: false,
                screenshot: screenshotCapable,
                hostWindowMetadata: true
            )
        )
    }

    func cellSummaries() -> [BrowserGridCellSummaryDTO] {
        cells.map { cell in
            let summary = cell.tabSummary()
            return BrowserGridCellSummaryDTO(
                target: summary,
                cellID: summary.cellID ?? summary.targetID,
                frameInContainer: summary.frameInContainer ?? RectDTO(x: 0, y: 0, width: 0, height: 0)
            )
        }
    }

    func cellSummary(for targetID: String) -> BrowserGridCellSummaryDTO? {
        cellSummaries().first { $0.target.targetID == targetID }
    }

    func update(request: BrowserUpdateGridRequest) throws {
        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           title.isEmpty == false {
            window.title = title
        }
        if let layout = request.layout {
            self.layout = try BrowserGridSurface.sanitizedLayout(layout, cellCount: cells.count)
            relayout()
        }
        if let requestedCells = request.cells {
            for request in requestedCells {
                guard let cell = cells.first(where: { $0.matchesGridCellID(request.id) }) else {
                    throw BrowserSurfaceError.invalidRequest("Grid \(gridTargetID) does not contain a cell with id '\(request.id)'.")
                }
                if let url = request.url {
                    try cell.navigate(url)
                }
            }
        }
    }

    func state(imageMode: ImageMode?, debug: Bool?) -> BrowserGridStateResponse {
        let warnings = screenshotCapable ? [] : [
            "Browser grid \(gridTargetID) is \(visibility.rawValue); container screenshots are omitted."
        ]
        let screenshot = ScreenshotCaptureService.capture(
            window: resolvedWindowDTO(),
            stateToken: "\(gridTargetID)-grid",
            imageMode: screenshotCapable ? (imageMode ?? .path) : .omit,
            includeRawRetinaCapture: debug == true,
            includeCursorOverlay: true
        )
        return BrowserGridStateResponse(
            ok: true,
            grid: BrowserGridStateDTO(
                target: gridSummary(),
                layout: layout,
                cells: cellSummaries(),
                screenshot: screenshot,
                warnings: warnings
            ),
            notes: ["Read browser grid layout and cell metadata for owned grid target \(gridTargetID)."]
        )
    }

    func closeCell(targetID: String) -> Bool {
        guard let index = cells.firstIndex(where: { $0.tabTargetID == targetID }) else {
            return false
        }
        cells[index].close()
        cells.remove(at: index)
        relayout()
        return true
    }

    func close() {
        guard isClosed == false else { return }
        isClosed = true
        for cell in cells {
            cell.close()
        }
        cells.removeAll()
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        BrowserSurfaceRegistry.shared.unregisterGrid(gridTargetID: gridTargetID)
        guard isClosed == false else { return }
        isClosed = true
        for cell in cells {
            cell.close()
        }
        cells.removeAll()
    }

    func hostWindowID() -> String {
        resolvedWindowDTO().windowID
    }

    func resolvedWindowDTO() -> ResolvedWindowDTO {
        let frame = window.frame
        let bundleID = Bundle.main.bundleIdentifier ?? "xyz.dubdub.backgroundcomputeruse"
        let launchDate = NSRunningApplication.current.launchDate
        let windowID = WindowID.make(
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate,
            windowNumber: window.windowNumber
        )
        WindowTargetCache.shared.remember(
            windowID: windowID,
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate,
            windowNumber: window.windowNumber,
            title: window.title
        )
        return ResolvedWindowDTO(
            windowID: windowID,
            title: window.title,
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate.map(Time.iso8601String),
            windowNumber: window.windowNumber,
            frameAppKit: RectDTO(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
            resolutionStrategy: "owned_browser_grid"
        )
    }

    func setHostFrame(_ frame: CGRect, animate: Bool) {
        window.setFrame(frame, display: true, animate: animate)
        contentView.frame = NSRect(origin: .zero, size: frame.size)
        relayout()
        rememberHostWindow()
    }

    private var screenshotCapable: Bool {
        visibility == .visible && window.windowNumber > 0
    }

    private func hostWindowDTO() -> BrowserHostWindowDTO {
        let resolved = resolvedWindowDTO()
        return BrowserHostWindowDTO(
            bundleID: resolved.bundleID,
            pid: resolved.pid,
            windowNumber: resolved.windowNumber,
            windowID: resolved.windowID,
            title: resolved.title,
            frameAppKit: resolved.frameAppKit
        )
    }

    private func rememberHostWindow() {
        _ = resolvedWindowDTO()
    }

    private func relayout() {
        let frames = BrowserGridSurface.cellFrames(layout: layout, bounds: contentView.bounds, count: cells.count)
        for (cell, frame) in zip(cells, frames) {
            cell.setFrameInContainer(frame)
        }
    }

    private static func sanitizedLayout(_ layout: BrowserGridLayoutDTO, cellCount: Int) throws -> BrowserGridLayoutDTO {
        guard layout.kind == .grid else {
            throw BrowserSurfaceError.invalidRequest("Only fixed grid browser layouts are supported.")
        }
        guard layout.columns > 0, layout.rows > 0 else {
            throw BrowserSurfaceError.invalidRequest("Grid rows and columns must be positive.")
        }
        let columns = min(layout.columns, 8)
        let rows = min(layout.rows, 8)
        guard columns * rows >= cellCount else {
            throw BrowserSurfaceError.invalidRequest("Grid layout does not have enough cells for the requested URLs.")
        }
        return BrowserGridLayoutDTO(
            columns: columns,
            rows: rows,
            gap: max(0, min(layout.gap ?? 8, 48))
        )
    }

    private static func cellFrames(layout: BrowserGridLayoutDTO, bounds: CGRect, count: Int) -> [CGRect] {
        let columns = max(layout.columns, 1)
        let rows = max(layout.rows, 1)
        let gap = max(layout.gap ?? 8, 0)
        let width = max((bounds.width - gap * Double(columns - 1)) / Double(columns), 1)
        let height = max((bounds.height - gap * Double(rows - 1)) / Double(rows), 1)
        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            let x = Double(column) * (width + gap)
            let y = bounds.height - Double(row + 1) * height - Double(row) * gap
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }
}

@MainActor
final class OwnedBrowserSurface: NSObject, @unchecked Sendable, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, NSToolbarDelegate, NSTextFieldDelegate, NSWindowDelegate {
    let windowTargetID: String
    let tabTargetID: String
    let profileID: String
    let visibility: BrowserVisibilityDTO

    private let window: NSWindow
    private let webView: WKWebView
    private let ownsWindow: Bool
    private let parentTargetID: String
    private let targetKind: BrowserTargetKindDTO
    private let cellID: String?
    private var frameInContainer: RectDTO?
    private var scripts: [String: InstalledBrowserScript] = [:]
    private var urlField: NSTextField?
    private var statusItem: NSToolbarItem?
    private var lastNavigationError: String?
    private var tabHost: BrowserTabHost?
    private var isClosed = false

    init(request: BrowserCreateWindowRequest) throws {
        windowTargetID = "bw_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        tabTargetID = "bt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        let requestedVisibility = request.visibility ?? .visible
        let requestedScreenshot = (request.imageMode ?? .omit) != .omit
        visibility = requestedVisibility == .nonVisible && request.allowVisibleFallback == true && requestedScreenshot
            ? .visible
            : requestedVisibility
        let profile = try BrowserProfileStore.shared.dataStore(profileID: request.profileID, ephemeral: request.ephemeral)
        profileID = profile.profileID
        ownsWindow = true
        parentTargetID = windowTargetID
        targetKind = .ownedBrowserTab
        cellID = nil
        frameInContainer = nil

        let configuration = BrowserWebEnvironment.makeConfiguration(dataStore: profile.dataStore)

        let initialFrame = NSRect(
            x: request.x ?? 120,
            y: request.y ?? 120,
            width: max(request.width ?? 1120, 420),
            height: max(request.height ?? 760, 320)
        )
        window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        let customUserAgent = request.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        webView.customUserAgent = customUserAgent?.isEmpty == false
            ? customUserAgent
            : BrowserWebCompatibility.desktopSafariUserAgent
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        super.init()

        installScriptMessageHandler(on: configuration.userContentController)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.autoresizingMask = [.width, .height]

        window.title = request.title ?? "Browser Surface"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.toolbar = makeToolbar()
        window.isReleasedWhenClosed = false
        window.delegate = self
        tabHost = BrowserTabHost(window: window, preferredContentSize: initialFrame.size)
        tabHost?.addTab(self, activate: true)
        window.setContentSize(initialFrame.size)

        if visibility == .visible {
            window.orderFrontRegardless()
        }
        window.setContentSize(initialFrame.size)

        rememberHostWindow()

        if let rawURL = request.url, rawURL.isEmpty == false {
            try navigate(rawURL)
        } else {
            webView.loadHTMLString(defaultHTML, baseURL: nil)
        }
        updateToolbarState()
    }

    init(
        popupFrom opener: OwnedBrowserSurface,
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures
    ) throws {
        guard let openerTabHost = opener.tabHost else {
            throw BrowserSurfaceError.invalidRequest("Popup tabs are currently supported only for standalone owned browser windows.")
        }
        windowTargetID = opener.windowTargetID
        tabTargetID = "bt_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        visibility = opener.visibility
        profileID = opener.profileID
        ownsWindow = false
        parentTargetID = opener.windowTargetID
        targetKind = .ownedBrowserTab
        cellID = nil
        frameInContainer = nil

        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        window = opener.window
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = opener.webView.customUserAgent ?? BrowserWebCompatibility.desktopSafariUserAgent
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        super.init()

        scripts = opener.scripts
        rebuildUserScripts()
        installScriptMessageHandler(on: configuration.userContentController)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.autoresizingMask = [.width, .height]

        tabHost = openerTabHost
        tabHost?.addTab(self, activate: true)

        rememberHostWindow()
        updateToolbarState()
    }

    init(
        gridTargetID: String,
        cellRequest: BrowserGridCellRequestDTO,
        defaultProfileID: String?,
        defaultEphemeral: Bool?,
        visibility: BrowserVisibilityDTO,
        parentWindow: NSWindow,
        containerView: NSView,
        frame: CGRect
    ) throws {
        windowTargetID = gridTargetID
        tabTargetID = "bc_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        self.visibility = visibility
        let profile = try BrowserProfileStore.shared.dataStore(
            profileID: cellRequest.profileID ?? defaultProfileID,
            ephemeral: cellRequest.ephemeral ?? defaultEphemeral
        )
        profileID = profile.profileID
        ownsWindow = false
        parentTargetID = gridTargetID
        targetKind = .ownedBrowserGridCell
        cellID = cellRequest.id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? tabTargetID
        frameInContainer = RectDTO(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        window = parentWindow

        let configuration = BrowserWebEnvironment.makeConfiguration(dataStore: profile.dataStore)
        webView = WKWebView(frame: frame, configuration: configuration)
        let customUserAgent = cellRequest.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        webView.customUserAgent = customUserAgent?.isEmpty == false
            ? customUserAgent
            : BrowserWebCompatibility.desktopSafariUserAgent
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        super.init()

        installScriptMessageHandler(on: configuration.userContentController)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = []
        containerView.addSubview(webView)

        if let rawURL = cellRequest.url, rawURL.isEmpty == false {
            try navigate(rawURL)
        } else {
            webView.loadHTMLString(defaultHTML, baseURL: nil)
        }
        updateToolbarState()
    }

    func windowSummary() -> BrowserTargetSummaryDTO {
        BrowserTargetSummaryDTO(
            targetID: windowTargetID,
            kind: .ownedBrowserWindow,
            ownerApp: "BackgroundComputerUse",
            title: window.title,
            url: webView.url?.absoluteString,
            isLoading: webView.isLoading,
            parentTargetID: nil,
            visibility: visibility,
            profileID: profileID,
            hostWindow: hostWindowDTO(),
            capabilities: ownedCapabilities
        )
    }

    func tabSummary() -> BrowserTargetSummaryDTO {
        BrowserTargetSummaryDTO(
            targetID: tabTargetID,
            kind: targetKind,
            ownerApp: "BackgroundComputerUse",
            title: webView.title ?? window.title,
            url: webView.url?.absoluteString,
            isLoading: webView.isLoading,
            parentTargetID: parentTargetID,
            visibility: visibility,
            profileID: profileID,
            gridID: targetKind == .ownedBrowserGridCell ? parentTargetID : nil,
            cellID: cellID,
            frameInContainer: frameInContainer,
            hostWindow: hostWindowDTO(),
            capabilities: ownedCapabilities
        )
    }

    var screenshotCapable: Bool {
        visibility == .visible && window.windowNumber > 0 && isActiveForWindowCapture
    }

    var ownsBrowserWindow: Bool {
        ownsWindow
    }

    private var isActiveForWindowCapture: Bool {
        guard let tabHost else { return true }
        return tabHost.isActive(self)
    }

    func navigate(_ rawURL: String) throws {
        let url = try normalizedURL(rawURL)
        urlField?.stringValue = url.absoluteString
        webView.load(URLRequest(url: url))
        updateToolbarState()
    }

    func reload() {
        webView.reload()
        updateToolbarState()
    }

    func close() {
        guard isClosed == false else { return }
        isClosed = true
        if let tabHost {
            if ownsWindow {
                tabHost.closeAllTabs()
                window.close()
            } else {
                tabHost.removeTab(self)
            }
            return
        }
        disposeBrowserWebView()
        if ownsWindow {
            window.close()
        }
    }

    func activateForTargeting() {
        tabHost?.activateSurface(self)
    }

    func activeSurfaceInWindow() -> OwnedBrowserSurface? {
        tabHost?.activeSurface()
    }

    func attachBrowserWebView(to containerView: NSView) {
        webView.removeFromSuperview()
        webView.frame = containerView.bounds
        webView.autoresizingMask = [.width, .height]
        containerView.addSubview(webView)
    }

    func setBrowserTabVisible(_ visible: Bool) {
        webView.isHidden = !visible
        if visible {
            webView.frame = tabHost?.contentBounds ?? webView.frame
        }
    }

    func resizeHostedBrowserWebView(to bounds: CGRect) {
        webView.frame = bounds
    }

    func activateBrowserTabInterface() {
        window.toolbar = makeToolbar()
        updateToolbarState()
    }

    func disposeBrowserWebView() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "bcu")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    var tabStripTitle: String {
        let rawTitle = webView.title ?? webView.url?.host ?? "New Tab"
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Tab" : trimmed
    }

    func setFrameInContainer(_ frame: CGRect) {
        webView.frame = frame
        frameInContainer = RectDTO(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    func matchesGridCellID(_ id: String) -> Bool {
        id == cellID || id == tabTargetID
    }

    func waitUntilLoaded(timeoutMs: Int?) async throws {
        let timeout = TimeInterval(max(100, timeoutMs ?? 8_000)) / 1_000
        let start = Date()
        while webView.isLoading {
            if Date().timeIntervalSince(start) > timeout {
                throw BrowserSurfaceError.timedOut("Timed out waiting for browser target \(tabTargetID) to finish loading.")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func evaluateJavaScript(_ source: String) async throws -> BrowserEvaluateJavaScriptResponse {
        try await ensureBootstrap()
        let value = try await webView.evaluateJavaScript(source)
        return BrowserEvaluateJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            target: tabSummary(),
            result: JSONValueDTO.from(any: value),
            resultDescription: value.map(String.init(describing:)),
            error: nil,
            notes: ["Executed JavaScript in owned WKWebView target \(tabTargetID)."]
        )
    }

    func installScript(request: BrowserInjectJavaScriptRequest) async throws -> BrowserInjectJavaScriptResponse {
        let runAt = request.runAt ?? .documentIdle
        let dto = BrowserInjectedScriptDTO(
            scriptID: request.scriptID,
            targetID: request.browser,
            urlMatch: request.urlMatch,
            runAt: runAt,
            persistAcrossReloads: request.persistAcrossReloads ?? true,
            sourceLength: request.javaScript.count,
            installedAt: Time.iso8601String(from: Date())
        )
        scripts[request.scriptID] = InstalledBrowserScript(dto: dto, javaScript: request.javaScript)
        rebuildUserScripts()

        let immediateResult: BrowserEvaluateJavaScriptResponse?
        if request.injectImmediately ?? true {
            immediateResult = try await evaluateJavaScript(request.javaScript)
        } else {
            immediateResult = nil
        }

        return BrowserInjectJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            script: dto,
            immediateResult: immediateResult,
            notes: [
                "Installed script '\(request.scriptID)' for owned browser target \(tabTargetID).",
                "document_start scripts run on the next navigation/reload; injectImmediately also evaluates the source in the current page."
            ]
        )
    }

    func removeScript(scriptID: String) -> BrowserRemoveInjectedJavaScriptResponse {
        let removed = scripts.removeValue(forKey: scriptID) != nil
        rebuildUserScripts()
        return BrowserRemoveInjectedJavaScriptResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            removed: removed,
            remainingScripts: listScripts(),
            notes: [removed ? "Removed injected script '\(scriptID)'." : "No injected script matched '\(scriptID)'."]
        )
    }

    func listScripts() -> [BrowserInjectedScriptDTO] {
        scripts.values
            .map(\.dto)
            .sorted { $0.scriptID < $1.scriptID }
    }

    func snapshot(maxElements: Int?, includeRawText: Bool?) async throws -> BrowserDOMSnapshotDTO {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.snapshot(maxElements, includeRawText);",
            arguments: [
                "maxElements": max(1, min(maxElements ?? 500, 5_000)),
                "includeRawText": includeRawText ?? false
            ],
            in: nil,
            contentWorld: .page
        )
        var snapshot: BrowserDOMSnapshotDTO = try decodeJavaScriptValue(value)
        snapshot = BrowserDOMSnapshotDTO(
            viewport: snapshot.viewport,
            focusedElement: snapshot.focusedElement,
            interactables: snapshot.interactables.map(mapInteractableToAppKit),
            rawText: snapshot.rawText,
            nodeCount: snapshot.nodeCount
        )
        return snapshot
    }

    func resolve(target: BrowserActionTargetRequestDTO) async throws -> BrowserInteractableDTO {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.resolve(target);",
            arguments: ["target": ["kind": target.kind.rawValue, "value": target.value]],
            in: nil,
            contentWorld: .page
        )
        let result: BrowserResolveResult = try decodeJavaScriptValue(value)
        guard result.ok, let element = result.element else {
            if result.error == "ambiguous_target" {
                throw BrowserSurfaceError.targetAmbiguous(result.message ?? "Browser target was ambiguous.")
            }
            throw BrowserSurfaceError.invalidRequest(result.message ?? result.error ?? "Browser target did not resolve.")
        }
        return mapInteractableToAppKit(element)
    }

    func dispatchClick(target: BrowserActionTargetRequestDTO, clickCount: Int) async throws -> JSONValueDTO {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.click(target, clickCount);",
            arguments: [
                "target": ["kind": target.kind.rawValue, "value": target.value],
                "clickCount": max(1, min(clickCount, 2))
            ],
            in: nil,
            contentWorld: .page
        )
        return JSONValueDTO.from(any: value)
    }

    func dispatchClickPoint(point: PointDTO, clickCount: Int) async throws -> JSONValueDTO {
        try await ensureBootstrap()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.clickPoint(x, y, clickCount);",
            arguments: [
                "x": point.x,
                "y": point.y,
                "clickCount": max(1, min(clickCount, 2))
            ],
            in: nil,
            contentWorld: .page
        )
        return JSONValueDTO.from(any: value)
    }

    func dispatchTypeText(target: BrowserActionTargetRequestDTO?, text: String, append: Bool) async throws -> JSONValueDTO {
        try await ensureBootstrap()
        let encodedTarget: Any = target.map { ["kind": $0.kind.rawValue, "value": $0.value] } ?? NSNull()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.typeText(target, text, append);",
            arguments: [
                "target": encodedTarget,
                "text": text,
                "append": append
            ],
            in: nil,
            contentWorld: .page
        )
        return JSONValueDTO.from(any: value)
    }

    func dispatchScroll(target: BrowserActionTargetRequestDTO?, direction: ScrollDirectionDTO, pages: Int) async throws -> JSONValueDTO {
        try await ensureBootstrap()
        let encodedTarget: Any = target.map { ["kind": $0.kind.rawValue, "value": $0.value] } ?? NSNull()
        let value = try await webView.callAsyncJavaScript(
            "return window.__bcu.scroll(target, direction, pages);",
            arguments: [
                "target": encodedTarget,
                "direction": direction.rawValue,
                "pages": max(1, min(pages, 10))
            ],
            in: nil,
            contentWorld: .page
        )
        return JSONValueDTO.from(any: value)
    }

    func viewportPointToAppKit(_ point: PointDTO) -> CGPoint {
        BrowserWebViewGeometry.appKitPoint(forViewportPoint: point, in: webView)
    }

    func viewportRectToAppKit(_ rect: RectDTO) -> CGRect {
        BrowserWebViewGeometry.appKitRect(forViewportRect: rect, in: webView)
    }

    func dispatchNativeClick(appKitPoint: CGPoint, clickCount: Int) throws -> JSONValueDTO {
        let window = resolvedWindowDTO()
        guard window.windowNumber > 0 else {
            throw BrowserSurfaceError.invalidRequest("Browser target \(tabTargetID) does not have a visible host window for native click dispatch.")
        }
        let routing = try NativeWindowServerRoutingResolver().resolve(windowNumber: window.windowNumber)
        let target = RoutedClickTarget(window: window, routing: routing)
        let result = try NativeBackgroundClickTransport().dispatch(
            NativeBackgroundClickDispatchRequest(
                target: target,
                eventTapPointTopLeft: CGPoint(
                    x: appKitPoint.x,
                    y: DesktopGeometry.desktopTop() - appKitPoint.y
                ),
                appKitPoint: appKitPoint,
                clickCount: clickCount,
                mouseButton: .left
            )
        )
        return .object([
            "ok": .bool(result.dispatchSuccess),
            "route": .string("native_background_click"),
            "eventsPrepared": .number(Double(result.eventsPrepared)),
            "targetPID": .number(Double(result.targetPID)),
            "targetWindowNumber": .number(Double(result.targetWindowNumber)),
            "ownerConnection": .number(Double(result.ownerConnection)),
            "notes": .array(result.notes.map(JSONValueDTO.string))
        ])
    }

    func resolvedWindowDTO() -> ResolvedWindowDTO {
        let frame = window.frame
        let bundleID = Bundle.main.bundleIdentifier ?? "xyz.dubdub.backgroundcomputeruse"
        let launchDate = NSRunningApplication.current.launchDate
        let windowID = WindowID.make(
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate,
            windowNumber: window.windowNumber
        )
        WindowTargetCache.shared.remember(
            windowID: windowID,
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate,
            windowNumber: window.windowNumber,
            title: window.title
        )
        return ResolvedWindowDTO(
            windowID: windowID,
            title: window.title,
            bundleID: bundleID,
            pid: getpid(),
            launchDate: launchDate.map(Time.iso8601String),
            windowNumber: window.windowNumber,
            frameAppKit: RectDTO(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
            resolutionStrategy: "owned_browser_window"
        )
    }

    func hostWindowID() -> String {
        resolvedWindowDTO().windowID
    }

    func setHostFrame(_ frame: CGRect, animate: Bool) {
        window.setFrame(frame, display: true, animate: animate)
        rememberHostWindow()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bcu",
              let body = message.body as? [String: Any],
              body["kind"] as? String == "event" else {
            return
        }

        let type = (body["type"] as? String) ?? "event"
        let scriptID = body["scriptID"] as? String
        let payload = JSONValueDTO.from(any: body["payload"])
        BrowserEventStore.shared.emit(
            targetID: tabTargetID,
            scriptID: scriptID,
            type: type,
            payload: payload
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastNavigationError = nil
        updateToolbarState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        lastNavigationError = error.localizedDescription
        updateToolbarState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        lastNavigationError = error.localizedDescription
        updateToolbarState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateToolbarState()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame?.isMainFrame != true else {
            return nil
        }

        do {
            let popup = try BrowserSurfaceRegistry.shared.createPopupWindow(
                opener: self,
                configuration: configuration,
                windowFeatures: windowFeatures
            )
            return popup.webView
        } catch {
            lastNavigationError = "Popup creation failed: \(error)"
            updateToolbarState()
            BrowserEventStore.shared.emit(
                targetID: tabTargetID,
                scriptID: nil,
                type: "browser_popup_failed",
                payload: .object(["error": .string(String(describing: error))])
            )
            return nil
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        _ = try? BrowserSurfaceRegistry.shared.close(targetID: tabTargetID)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        guard visibility == .visible else {
            completionHandler()
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard visibility == .visible else {
            completionHandler(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        guard visibility == .visible else {
            completionHandler(defaultText)
            return
        }
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = input
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard ownsWindow else { return }
        isClosed = true
        tabHost?.closeAllTabs()
        BrowserSurfaceRegistry.shared.unregisterOwnedWindow(windowTargetID: windowTargetID)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .browserBack:
            return buttonItem(identifier: itemIdentifier, symbol: "chevron.left", label: "Back", action: #selector(goBack))
        case .browserForward:
            return buttonItem(identifier: itemIdentifier, symbol: "chevron.right", label: "Forward", action: #selector(goForward))
        case .browserReload:
            return buttonItem(identifier: itemIdentifier, symbol: "arrow.clockwise", label: "Reload", action: #selector(reloadFromToolbar))
        case .browserURL:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let field = NSTextField(string: webView.url?.absoluteString ?? "")
            field.placeholderString = "Enter URL"
            field.delegate = self
            field.target = self
            field.action = #selector(navigateFromToolbar)
            field.controlSize = .regular
            field.bezelStyle = .roundedBezel
            field.lineBreakMode = .byTruncatingMiddle
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
            item.view = field
            item.label = "URL"
            item.paletteLabel = "URL"
            urlField = field
            return item
        case .browserStatus:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Status"
            item.paletteLabel = "Status"
            item.view = NSProgressIndicator()
            statusItem = item
            return item
        default:
            return nil
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.browserBack, .browserForward, .browserReload, .flexibleSpace, .browserURL, .browserStatus]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.browserBack, .browserForward, .browserReload, .browserURL, .browserStatus]
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        navigateFromToolbar()
    }

    @objc private func navigateFromToolbar() {
        guard let rawURL = urlField?.stringValue, rawURL.isEmpty == false else { return }
        try? navigate(rawURL)
    }

    @objc private func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    @objc private func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    @objc private func reloadFromToolbar() {
        reload()
    }

    private var ownedCapabilities: BrowserTargetCapabilitiesDTO {
        BrowserTargetCapabilitiesDTO(
            readDom: true,
            evaluateJavaScript: true,
            injectJavaScript: true,
            emitPageEvents: true,
            dispatchDomEvents: true,
            nativeClickFallback: screenshotCapable,
            screenshot: screenshotCapable,
            hostWindowMetadata: true
        )
    }

    private func hostWindowDTO() -> BrowserHostWindowDTO {
        let resolved = resolvedWindowDTO()
        return BrowserHostWindowDTO(
            bundleID: resolved.bundleID,
            pid: resolved.pid,
            windowNumber: resolved.windowNumber,
            windowID: resolved.windowID,
            title: resolved.title,
            frameAppKit: resolved.frameAppKit
        )
    }

    private func rememberHostWindow() {
        _ = resolvedWindowDTO()
    }

    private func ensureBootstrap() async throws {
        let value = try await webView.callAsyncJavaScript(
            """
            if (!window.__bcu || window.__bcu.version !== 1) {
              return false;
            }
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard (value as? Bool) == true else {
            throw BrowserSurfaceError.javascriptFailed("BCU browser bootstrap script is not available in the page.")
        }
    }

    private func rebuildUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(
                source: BrowserBootstrapScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        for script in scripts.values.sorted(by: { $0.dto.scriptID < $1.dto.scriptID }) where script.dto.persistAcrossReloads {
            controller.addUserScript(
                WKUserScript(
                    source: script.javaScript,
                    injectionTime: injectionTime(for: script.dto.runAt),
                    forMainFrameOnly: false
                )
            )
        }
    }

    private func installScriptMessageHandler(on controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: "bcu")
        controller.add(self, name: "bcu")
    }

    private func injectionTime(for runAt: BrowserScriptRunAtDTO) -> WKUserScriptInjectionTime {
        switch runAt {
        case .documentStart:
            return .atDocumentStart
        case .documentEnd, .documentIdle:
            return .atDocumentEnd
        }
    }

    private func mapInteractableToAppKit(_ interactable: BrowserInteractableDTO) -> BrowserInteractableDTO {
        let rectAppKit = viewportRectToAppKit(interactable.rectViewport)
        let centerAppKit = viewportPointToAppKit(interactable.centerViewport)
        return BrowserInteractableDTO(
            displayIndex: interactable.displayIndex,
            nodeID: interactable.nodeID,
            role: interactable.role,
            tagName: interactable.tagName,
            text: interactable.text,
            accessibleName: interactable.accessibleName,
            valuePreview: interactable.valuePreview,
            selectorCandidates: interactable.selectorCandidates,
            rectViewport: interactable.rectViewport,
            centerViewport: interactable.centerViewport,
            rectAppKit: RectDTO(x: rectAppKit.minX, y: rectAppKit.minY, width: rectAppKit.width, height: rectAppKit.height),
            centerAppKit: PointDTO(x: centerAppKit.x, y: centerAppKit.y),
            isVisible: interactable.isVisible,
            isEnabled: interactable.isEnabled,
            isEditable: interactable.isEditable
        )
    }

    private func decodeJavaScriptValue<T: Decodable>(_ value: Any?) throws -> T {
        let jsonValue = JSONValueDTO.from(any: value)
        let data = try JSONSupport.encoder.encode(jsonValue)
        return try JSONSupport.decoder.decode(T.self, from: data)
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "BrowserSurfaceToolbar.\(tabTargetID)")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    private func buttonItem(
        identifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        item.view = button
        return item
    }

    private func updateToolbarState() {
        if ownsWindow && tabHost == nil {
            window.title = webView.title ?? "Browser Surface"
        }
        urlField?.stringValue = webView.url?.absoluteString ?? urlField?.stringValue ?? ""
        if let indicator = statusItem?.view as? NSProgressIndicator {
            if webView.isLoading {
                indicator.style = .spinning
                indicator.startAnimation(nil)
            } else {
                indicator.stopAnimation(nil)
                indicator.isHidden = lastNavigationError == nil
            }
        }
        tabHost?.updateTab(self)
    }

    private func normalizedURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "about:blank" {
            return URL(string: "about:blank")!
        }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if let url = URL(string: "https://\(trimmed)") {
            return url
        }
        throw BrowserSurfaceError.invalidURL(raw)
    }

    private var defaultHTML: String {
        """
        <!doctype html>
        <meta charset="utf-8">
        <title>Browser Surface</title>
        <style>
        html, body { margin: 0; height: 100%; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; color: #1f2328; }
        main { min-height: 100%; display: grid; place-items: center; background: color-mix(in srgb, Canvas 92%, #5a9 8%); }
        section { max-width: 520px; padding: 24px; }
        h1 { font-size: 22px; margin: 0 0 8px; }
        p { line-height: 1.5; margin: 0; color: #4b5563; }
        </style>
        <main><section><h1>Browser Surface</h1><p>Navigate with the toolbar or the /v1/browser/navigate API.</p></section></main>
        """
    }
}

private extension NSToolbarItem.Identifier {
    static let browserBack = NSToolbarItem.Identifier("BrowserSurface.Back")
    static let browserForward = NSToolbarItem.Identifier("BrowserSurface.Forward")
    static let browserReload = NSToolbarItem.Identifier("BrowserSurface.Reload")
    static let browserURL = NSToolbarItem.Identifier("BrowserSurface.URL")
    static let browserStatus = NSToolbarItem.Identifier("BrowserSurface.Status")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
