import Foundation

public enum JSONValueDTO: Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValueDTO])
    case object([String: JSONValueDTO])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(sanitizedJSONDouble(value))
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValueDTO].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValueDTO].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(sanitizedJSONDouble(value))
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public static func from(any value: Any?) -> JSONValueDTO {
        guard let value, !(value is NSNull) else {
            return .null
        }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        }
        if let value = value as? Bool {
            return .bool(value)
        }
        if let value = value as? String {
            return .string(value)
        }
        if let value = value as? [Any] {
            return .array(value.map(JSONValueDTO.from(any:)))
        }
        if let value = value as? [String: Any] {
            return .object(value.mapValues(JSONValueDTO.from(any:)))
        }
        return .string(String(describing: value))
    }
}

public enum BrowserVisibilityDTO: String, Codable, Sendable {
    case visible
    case nonVisible = "non_visible"
}

public enum BrowserProfileValidationError: Error, CustomStringConvertible, Sendable {
    case invalidProfileID(String)

    public var description: String {
        switch self {
        case .invalidProfileID(let value):
            return "Browser profileID '\(value)' must be 1-64 characters and contain only letters, numbers, dot, underscore, or hyphen."
        }
    }
}

public enum BrowserProfileIDValidation {
    public static func validate(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard trimmed.isEmpty == false,
              trimmed.count <= 64,
              trimmed.rangeOfCharacter(from: allowed.inverted) == nil,
              trimmed != ".",
              trimmed != ".." else {
            throw BrowserProfileValidationError.invalidProfileID(value)
        }
        return trimmed
    }
}

public struct BrowserProfileDTO: Codable, Sendable {
    public let profileID: String
    public let ephemeral: Bool

    public init(profileID: String = "default", ephemeral: Bool = false) throws {
        self.profileID = try BrowserProfileIDValidation.validate(profileID)
        self.ephemeral = ephemeral
    }
}

public enum BrowserTargetKindDTO: String, Codable, Sendable {
    case ownedBrowserWindow = "owned_browser_window"
    case ownedBrowserTab = "owned_browser_tab"
    case ownedBrowserGrid = "owned_browser_grid"
    case ownedBrowserGridCell = "owned_browser_grid_cell"
}

public struct BrowserTargetCapabilitiesDTO: Codable, Sendable {
    public let readDom: Bool
    public let evaluateJavaScript: Bool
    public let injectJavaScript: Bool
    public let emitPageEvents: Bool
    public let dispatchDomEvents: Bool
    public let nativeClickFallback: Bool
    public let screenshot: Bool
    public let hostWindowMetadata: Bool

    public init(
        readDom: Bool,
        evaluateJavaScript: Bool,
        injectJavaScript: Bool,
        emitPageEvents: Bool,
        dispatchDomEvents: Bool,
        nativeClickFallback: Bool,
        screenshot: Bool,
        hostWindowMetadata: Bool
    ) {
        self.readDom = readDom
        self.evaluateJavaScript = evaluateJavaScript
        self.injectJavaScript = injectJavaScript
        self.emitPageEvents = emitPageEvents
        self.dispatchDomEvents = dispatchDomEvents
        self.nativeClickFallback = nativeClickFallback
        self.screenshot = screenshot
        self.hostWindowMetadata = hostWindowMetadata
    }
}

public struct BrowserHostWindowDTO: Codable, Sendable {
    public let bundleID: String
    public let pid: Int32
    public let windowNumber: Int?
    public let windowID: String?
    public let title: String
    public let frameAppKit: RectDTO

    public init(
        bundleID: String,
        pid: Int32,
        windowNumber: Int? = nil,
        windowID: String? = nil,
        title: String,
        frameAppKit: RectDTO
    ) {
        self.bundleID = bundleID
        self.pid = pid
        self.windowNumber = windowNumber
        self.windowID = windowID
        self.title = title
        self.frameAppKit = frameAppKit
    }
}

public struct BrowserTargetSummaryDTO: Codable, Sendable {
    public let targetID: String
    public let kind: BrowserTargetKindDTO
    public let ownerApp: String
    public let title: String
    public let url: String?
    public let isLoading: Bool
    public let parentTargetID: String?
    public let visibility: BrowserVisibilityDTO
    public let profileID: String
    public let gridID: String?
    public let cellID: String?
    public let frameInContainer: RectDTO?
    public let hostWindow: BrowserHostWindowDTO?
    public let capabilities: BrowserTargetCapabilitiesDTO

    public init(
        targetID: String,
        kind: BrowserTargetKindDTO,
        ownerApp: String,
        title: String,
        url: String? = nil,
        isLoading: Bool,
        parentTargetID: String? = nil,
        visibility: BrowserVisibilityDTO = .visible,
        profileID: String = "default",
        gridID: String? = nil,
        cellID: String? = nil,
        frameInContainer: RectDTO? = nil,
        hostWindow: BrowserHostWindowDTO? = nil,
        capabilities: BrowserTargetCapabilitiesDTO
    ) {
        self.targetID = targetID
        self.kind = kind
        self.ownerApp = ownerApp
        self.title = title
        self.url = url
        self.isLoading = isLoading
        self.parentTargetID = parentTargetID
        self.visibility = visibility
        self.profileID = profileID
        self.gridID = gridID
        self.cellID = cellID
        self.frameInContainer = frameInContainer
        self.hostWindow = hostWindow
        self.capabilities = capabilities
    }
}

public enum BrowserScriptRunAtDTO: String, Codable, Sendable {
    case documentStart = "document_start"
    case documentEnd = "document_end"
    case documentIdle = "document_idle"
}

public struct BrowserInjectedScriptDTO: Codable, Sendable {
    public let scriptID: String
    public let targetID: String?
    public let urlMatch: String?
    public let runAt: BrowserScriptRunAtDTO
    public let persistAcrossReloads: Bool
    public let sourceLength: Int
    public let installedAt: String

    public init(
        scriptID: String,
        targetID: String? = nil,
        urlMatch: String? = nil,
        runAt: BrowserScriptRunAtDTO,
        persistAcrossReloads: Bool,
        sourceLength: Int,
        installedAt: String
    ) {
        self.scriptID = scriptID
        self.targetID = targetID
        self.urlMatch = urlMatch
        self.runAt = runAt
        self.persistAcrossReloads = persistAcrossReloads
        self.sourceLength = sourceLength
        self.installedAt = installedAt
    }
}

public enum BrowserActionTargetKindDTO: String, Codable, Sendable {
    case displayIndex = "display_index"
    case browserNodeID = "browser_node_id"
    case domSelector = "dom_selector"
}

public struct BrowserActionTargetRequestDTO: Codable, Sendable {
    public let kind: BrowserActionTargetKindDTO
    public let value: String

    public init(kind: BrowserActionTargetKindDTO, value: String) {
        self.kind = kind
        self.value = value
    }

    public static func displayIndex(_ index: Int) -> BrowserActionTargetRequestDTO {
        BrowserActionTargetRequestDTO(kind: .displayIndex, value: String(max(index, 0)))
    }

    public static func browserNodeID(_ value: String) -> BrowserActionTargetRequestDTO {
        BrowserActionTargetRequestDTO(kind: .browserNodeID, value: value)
    }

    public static func domSelector(_ value: String) -> BrowserActionTargetRequestDTO {
        BrowserActionTargetRequestDTO(kind: .domSelector, value: value)
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(BrowserActionTargetKindDTO.self, forKey: .kind)
        switch kind {
        case .displayIndex:
            if let index = try? container.decode(Int.self, forKey: .value) {
                guard index >= 0 else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .value,
                        in: container,
                        debugDescription: "display_index targets must use a non-negative integer value."
                    )
                }
                value = String(index)
            } else {
                let raw = try container.decode(String.self, forKey: .value)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let index = Int(raw), index >= 0 else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .value,
                        in: container,
                        debugDescription: "display_index targets must use a non-negative integer value."
                    )
                }
                value = String(index)
            }
        case .browserNodeID, .domSelector:
            let raw = try container.decode(String.self, forKey: .value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.isEmpty == false else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "\(kind.rawValue) targets must use a non-empty string value."
                )
            }
            value = raw
        }
    }
}

public struct BrowserViewportDTO: Codable, Sendable {
    public let width: Double
    public let height: Double
    public let scrollX: Double
    public let scrollY: Double
    public let deviceScaleFactor: Double

    public init(width: Double, height: Double, scrollX: Double = 0, scrollY: Double = 0, deviceScaleFactor: Double = 1) {
        self.width = sanitizedJSONDouble(width)
        self.height = sanitizedJSONDouble(height)
        self.scrollX = sanitizedJSONDouble(scrollX)
        self.scrollY = sanitizedJSONDouble(scrollY)
        self.deviceScaleFactor = sanitizedJSONDouble(deviceScaleFactor)
    }
}

public struct BrowserFocusedElementDTO: Codable, Sendable {
    public let nodeID: String?
    public let tagName: String?
    public let role: String?
    public let text: String?
    public let valuePreview: String?
    public let isEditable: Bool

    public init(nodeID: String? = nil, tagName: String? = nil, role: String? = nil, text: String? = nil, valuePreview: String? = nil, isEditable: Bool) {
        self.nodeID = nodeID
        self.tagName = tagName
        self.role = role
        self.text = text
        self.valuePreview = valuePreview
        self.isEditable = isEditable
    }
}

public struct BrowserInteractableDTO: Codable, Sendable {
    public let displayIndex: Int
    public let nodeID: String
    public let role: String
    public let tagName: String
    public let text: String?
    public let accessibleName: String?
    public let valuePreview: String?
    public let selectorCandidates: [String]
    public let rectViewport: RectDTO
    public let centerViewport: PointDTO
    public let rectAppKit: RectDTO?
    public let centerAppKit: PointDTO?
    public let isVisible: Bool
    public let isEnabled: Bool
    public let isEditable: Bool

    public init(
        displayIndex: Int,
        nodeID: String,
        role: String,
        tagName: String,
        text: String? = nil,
        accessibleName: String? = nil,
        valuePreview: String? = nil,
        selectorCandidates: [String] = [],
        rectViewport: RectDTO,
        centerViewport: PointDTO,
        rectAppKit: RectDTO? = nil,
        centerAppKit: PointDTO? = nil,
        isVisible: Bool,
        isEnabled: Bool,
        isEditable: Bool
    ) {
        self.displayIndex = displayIndex
        self.nodeID = nodeID
        self.role = role
        self.tagName = tagName
        self.text = text
        self.accessibleName = accessibleName
        self.valuePreview = valuePreview
        self.selectorCandidates = selectorCandidates
        self.rectViewport = rectViewport
        self.centerViewport = centerViewport
        self.rectAppKit = rectAppKit
        self.centerAppKit = centerAppKit
        self.isVisible = isVisible
        self.isEnabled = isEnabled
        self.isEditable = isEditable
    }
}

public struct BrowserDOMSnapshotDTO: Codable, Sendable {
    public let viewport: BrowserViewportDTO
    public let focusedElement: BrowserFocusedElementDTO?
    public let interactables: [BrowserInteractableDTO]
    public let rawText: String?
    public let nodeCount: Int

    public init(
        viewport: BrowserViewportDTO,
        focusedElement: BrowserFocusedElementDTO? = nil,
        interactables: [BrowserInteractableDTO],
        rawText: String? = nil,
        nodeCount: Int
    ) {
        self.viewport = viewport
        self.focusedElement = focusedElement
        self.interactables = interactables
        self.rawText = rawText
        self.nodeCount = nodeCount
    }
}

public struct BrowserPerformanceDTO: Codable, Sendable {
    public let resolveMs: Double
    public let domMs: Double
    public let screenshotMs: Double
    public let totalMs: Double

    public init(resolveMs: Double, domMs: Double, screenshotMs: Double, totalMs: Double) {
        self.resolveMs = sanitizedJSONDouble(resolveMs)
        self.domMs = sanitizedJSONDouble(domMs)
        self.screenshotMs = sanitizedJSONDouble(screenshotMs)
        self.totalMs = sanitizedJSONDouble(totalMs)
    }
}

public struct BrowserCreateWindowRequest: Codable, Sendable, DebugNotesRequest {
    public let url: String?
    public let title: String?
    public let profileID: String?
    public let ephemeral: Bool?
    public let visibility: BrowserVisibilityDTO?
    public let allowVisibleFallback: Bool?
    public let x: Double?
    public let y: Double?
    public let width: Double?
    public let height: Double?
    public let userAgent: String?
    public let activate: Bool?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(
        url: String? = nil,
        title: String? = nil,
        profileID: String = "default",
        ephemeral: Bool? = nil,
        visibility: BrowserVisibilityDTO = .visible,
        allowVisibleFallback: Bool? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        userAgent: String? = nil,
        activate: Bool? = false,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) throws {
        self.url = url
        self.title = title
        self.profileID = try BrowserProfileIDValidation.validate(profileID)
        self.ephemeral = ephemeral
        self.visibility = visibility
        self.allowVisibleFallback = allowVisibleFallback
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.userAgent = userAgent
        self.activate = activate
        self.imageMode = imageMode
        self.debug = debug
    }

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case profileID
        case ephemeral
        case visibility
        case allowVisibleFallback
        case x
        case y
        case width
        case height
        case userAgent
        case activate
        case imageMode
        case debug
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        let rawProfileID = try container.decodeIfPresent(String.self, forKey: .profileID) ?? "default"
        do {
            profileID = try BrowserProfileIDValidation.validate(rawProfileID)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .profileID,
                in: container,
                debugDescription: String(describing: error)
            )
        }
        ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral)
        visibility = try container.decodeIfPresent(BrowserVisibilityDTO.self, forKey: .visibility) ?? .visible
        allowVisibleFallback = try container.decodeIfPresent(Bool.self, forKey: .allowVisibleFallback)
        x = try container.decodeIfPresent(Double.self, forKey: .x)
        y = try container.decodeIfPresent(Double.self, forKey: .y)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
        activate = try container.decodeIfPresent(Bool.self, forKey: .activate) ?? false
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
    }
}

public struct BrowserCreateWindowResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let target: BrowserTargetSummaryDTO
    public let state: BrowserGetStateResponse?
    public let notes: [String]
}

public struct BrowserListTargetsRequest: Codable, Sendable {
    public let includeRegistered: Bool?

    public init(includeRegistered: Bool? = nil) {
        self.includeRegistered = includeRegistered
    }
}

public struct BrowserListTargetsResponse: Codable, Sendable {
    public let contractVersion: String
    public let targets: [BrowserTargetSummaryDTO]
    public let notes: [String]
}

public struct BrowserNavigateRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let url: String
    public let waitUntilLoaded: Bool?
    public let timeoutMs: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(browser: String, url: String, waitUntilLoaded: Bool? = nil, timeoutMs: Int? = nil, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = browser
        self.url = url
        self.waitUntilLoaded = waitUntilLoaded
        self.timeoutMs = timeoutMs
        self.imageMode = imageMode
        self.debug = debug
    }
}

public struct BrowserGetStateRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let maxElements: Int?
    public let includeRawText: Bool?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(browser: String, maxElements: Int? = nil, includeRawText: Bool? = nil, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = browser
        self.maxElements = maxElements
        self.includeRawText = includeRawText
        self.imageMode = imageMode
        self.debug = debug
    }
}

public struct BrowserGetStateResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let stateToken: String
    public let target: BrowserTargetSummaryDTO
    public let screenshot: ScreenshotDTO
    public let dom: BrowserDOMSnapshotDTO
    public let performance: BrowserPerformanceDTO
    public let warnings: [String]
    public let notes: [String]
}

public struct BrowserEvaluateJavaScriptRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let javaScript: String
    public let timeoutMs: Int?
    public let debug: Bool?

    public init(browser: String, javaScript: String, timeoutMs: Int? = nil, debug: Bool? = nil) {
        self.browser = browser
        self.javaScript = javaScript
        self.timeoutMs = timeoutMs
        self.debug = debug
    }
}

public struct BrowserEvaluateJavaScriptResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let target: BrowserTargetSummaryDTO
    public let result: JSONValueDTO?
    public let resultDescription: String?
    public let error: String?
    public let notes: [String]
}

public struct BrowserInjectJavaScriptRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String?
    public let urlMatch: String?
    public let scriptID: String
    public let javaScript: String
    public let runAt: BrowserScriptRunAtDTO?
    public let persistAcrossReloads: Bool?
    public let injectImmediately: Bool?
    public let debug: Bool?

    public init(
        browser: String? = nil,
        urlMatch: String? = nil,
        scriptID: String,
        javaScript: String,
        runAt: BrowserScriptRunAtDTO? = nil,
        persistAcrossReloads: Bool? = nil,
        injectImmediately: Bool? = nil,
        debug: Bool? = nil
    ) {
        self.browser = browser
        self.urlMatch = urlMatch
        self.scriptID = scriptID
        self.javaScript = javaScript
        self.runAt = runAt
        self.persistAcrossReloads = persistAcrossReloads
        self.injectImmediately = injectImmediately
        self.debug = debug
    }
}

public struct BrowserInjectJavaScriptResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let script: BrowserInjectedScriptDTO
    public let immediateResult: BrowserEvaluateJavaScriptResponse?
    public let notes: [String]
}

public struct BrowserRemoveInjectedJavaScriptRequest: Codable, Sendable {
    public let browser: String?
    public let scriptID: String

    public init(browser: String? = nil, scriptID: String) {
        self.browser = browser
        self.scriptID = scriptID
    }
}

public struct BrowserRemoveInjectedJavaScriptResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let removed: Bool
    public let remainingScripts: [BrowserInjectedScriptDTO]
    public let notes: [String]
}

public struct BrowserListInjectedJavaScriptRequest: Codable, Sendable {
    public let browser: String?

    public init(browser: String? = nil) {
        self.browser = browser
    }
}

public struct BrowserListInjectedJavaScriptResponse: Codable, Sendable {
    public let contractVersion: String
    public let scripts: [BrowserInjectedScriptDTO]
    public let notes: [String]
}

public struct BrowserClickRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let stateToken: String?
    public let target: BrowserActionTargetRequestDTO?
    public let x: Double?
    public let y: Double?
    public let clickCount: Int?
    public let cursor: CursorRequestDTO?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(browser: String, stateToken: String? = nil, target: BrowserActionTargetRequestDTO, clickCount: Int? = nil, cursor: CursorRequestDTO? = nil, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = browser
        self.stateToken = stateToken
        self.target = target
        self.x = nil
        self.y = nil
        self.clickCount = clickCount
        self.cursor = cursor
        self.imageMode = imageMode
        self.debug = debug
    }

    public init(browser: String, stateToken: String? = nil, x: Double, y: Double, clickCount: Int? = nil, cursor: CursorRequestDTO? = nil, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = browser
        self.stateToken = stateToken
        self.target = nil
        self.x = x
        self.y = y
        self.clickCount = clickCount
        self.cursor = cursor
        self.imageMode = imageMode
        self.debug = debug
    }
}

public struct BrowserTypeTextRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let stateToken: String?
    public let target: BrowserActionTargetRequestDTO?
    public let text: String
    public let append: Bool?
    public let cursor: CursorRequestDTO?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(browser: String, stateToken: String? = nil, target: BrowserActionTargetRequestDTO? = nil, text: String, append: Bool? = nil, cursor: CursorRequestDTO? = nil, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = browser
        self.stateToken = stateToken
        self.target = target
        self.text = text
        self.append = append
        self.cursor = cursor
        self.imageMode = imageMode
        self.debug = debug
    }
}

public struct BrowserScrollRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let stateToken: String?
    public let target: BrowserActionTargetRequestDTO?
    public let direction: ScrollDirectionDTO
    public let pages: Int?
    public let cursor: CursorRequestDTO?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(browser: String, stateToken: String? = nil, target: BrowserActionTargetRequestDTO? = nil, direction: ScrollDirectionDTO, pages: Int? = nil, cursor: CursorRequestDTO? = nil, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = browser
        self.stateToken = stateToken
        self.target = target
        self.direction = direction
        self.pages = pages
        self.cursor = cursor
        self.imageMode = imageMode
        self.debug = debug
    }
}

public struct BrowserActionDebugDTO: Codable, Sendable {
    public let resolvedRectViewport: RectDTO?
    public let resolvedCenterViewport: PointDTO?
    public let resolvedRectAppKit: RectDTO?
    public let resolvedCenterAppKit: PointDTO?
    public let hostWindowFrameAppKit: RectDTO?
    public let cursorPositionBeforeAppKit: PointDTO?
    public let dispatchResult: JSONValueDTO?
}

public struct BrowserActionResponse: Encodable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let classification: ActionClassificationDTO
    public let failureDomain: ActionFailureDomainDTO?
    public let summary: String
    public let target: BrowserTargetSummaryDTO?
    public let requestedTarget: BrowserActionTargetRequestDTO?
    public let preStateToken: String?
    public let postStateToken: String?
    public let cursor: ActionCursorTargetResponseDTO
    public let screenshot: ScreenshotDTO?
    public let warnings: [String]
    public let notes: [String]
    public let debug: BrowserActionDebugDTO?
}

public struct BrowserReloadRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let waitUntilLoaded: Bool?
    public let timeoutMs: Int?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(browser: String, waitUntilLoaded: Bool? = nil, timeoutMs: Int? = nil, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = browser
        self.waitUntilLoaded = waitUntilLoaded
        self.timeoutMs = timeoutMs
        self.imageMode = imageMode
        self.debug = debug
    }
}

public struct BrowserCloseRequest: Codable, Sendable {
    public let browser: String

    public init(browser: String) {
        self.browser = browser
    }
}

public struct BrowserCloseResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let closed: Bool
    public let notes: [String]
}

public enum BrowserGridLayoutKindDTO: String, Codable, Sendable {
    case grid
}

public struct BrowserGridLayoutRequestDTO: Codable, Sendable {
    public let kind: BrowserGridLayoutKindDTO
    public let columns: Int
    public let rows: Int
    public let gap: Double?

    public init(kind: BrowserGridLayoutKindDTO = .grid, columns: Int, rows: Int, gap: Double? = nil) {
        self.kind = kind
        self.columns = columns
        self.rows = rows
        self.gap = gap.map { sanitizedJSONDouble(max($0, 0)) }
    }
}

public typealias BrowserGridLayoutDTO = BrowserGridLayoutRequestDTO

public struct BrowserGridCellRequestDTO: Codable, Sendable {
    public let id: String
    public let url: String?
    public let profileID: String?
    public let ephemeral: Bool?
    public let userAgent: String?

    public init(id: String, url: String? = nil, profileID: String? = nil, ephemeral: Bool? = nil, userAgent: String? = nil) throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw BrowserSurfaceRequestValidationError.invalidCellID(id)
        }
        self.id = trimmed
        self.url = url
        self.profileID = try profileID.map(BrowserProfileIDValidation.validate)
        self.ephemeral = ephemeral
        self.userAgent = userAgent
    }

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case profileID
        case ephemeral
        case userAgent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decode(String.self, forKey: .id)
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: BrowserSurfaceRequestValidationError.invalidCellID(rawID).description
            )
        }
        id = trimmed
        url = try container.decodeIfPresent(String.self, forKey: .url)
        do {
            profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
                .map(BrowserProfileIDValidation.validate)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .profileID, in: container, debugDescription: String(describing: error))
        }
        ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
    }
}

public struct BrowserGridCellDTO: Codable, Sendable {
    public let targetID: String
    public let kind: BrowserTargetKindDTO
    public let cellID: String
    public let url: String?
    public let profileID: String
    public let frameInContainer: RectDTO
    public let frameAppKit: RectDTO?
    public let target: BrowserTargetSummaryDTO?
    public let warnings: [String]

    public init(
        targetID: String,
        kind: BrowserTargetKindDTO = .ownedBrowserGridCell,
        cellID: String,
        url: String? = nil,
        profileID: String,
        frameInContainer: RectDTO,
        frameAppKit: RectDTO? = nil,
        target: BrowserTargetSummaryDTO? = nil,
        warnings: [String] = []
    ) {
        self.targetID = targetID
        self.kind = kind
        self.cellID = cellID
        self.url = url
        self.profileID = profileID
        self.frameInContainer = frameInContainer
        self.frameAppKit = frameAppKit
        self.target = target
        self.warnings = warnings
    }
}

public struct BrowserGridCellSummaryDTO: Codable, Sendable {
    public let target: BrowserTargetSummaryDTO
    public let cellID: String
    public let frameInContainer: RectDTO

    public init(target: BrowserTargetSummaryDTO, cellID: String, frameInContainer: RectDTO) {
        self.target = target
        self.cellID = cellID
        self.frameInContainer = frameInContainer
    }
}

public struct BrowserCreateGridRequest: Codable, Sendable, DebugNotesRequest {
    public let title: String?
    public let profileID: String?
    public let ephemeral: Bool?
    public let visibility: BrowserVisibilityDTO?
    public let activate: Bool?
    public let x: Double?
    public let y: Double?
    public let layout: BrowserGridLayoutRequestDTO
    public let cells: [BrowserGridCellRequestDTO]
    public let width: Double?
    public let height: Double?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public init(
        title: String? = nil,
        profileID: String = "default",
        ephemeral: Bool? = nil,
        visibility: BrowserVisibilityDTO = .visible,
        activate: Bool? = false,
        x: Double? = nil,
        y: Double? = nil,
        layout: BrowserGridLayoutRequestDTO,
        cells: [BrowserGridCellRequestDTO],
        width: Double? = nil,
        height: Double? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) throws {
        self.title = title
        self.profileID = try BrowserProfileIDValidation.validate(profileID)
        self.ephemeral = ephemeral
        self.visibility = visibility
        self.activate = activate
        self.x = x
        self.y = y
        self.layout = layout
        self.cells = cells
        self.width = width
        self.height = height
        self.imageMode = imageMode
        self.debug = debug
    }

    enum CodingKeys: String, CodingKey {
        case title
        case profileID
        case ephemeral
        case visibility
        case activate
        case x
        case y
        case layout
        case cells
        case width
        case height
        case imageMode
        case debug
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        let rawProfileID = try container.decodeIfPresent(String.self, forKey: .profileID) ?? "default"
        do {
            profileID = try BrowserProfileIDValidation.validate(rawProfileID)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .profileID, in: container, debugDescription: String(describing: error))
        }
        ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral)
        visibility = try container.decodeIfPresent(BrowserVisibilityDTO.self, forKey: .visibility) ?? .visible
        activate = try container.decodeIfPresent(Bool.self, forKey: .activate) ?? false
        x = try container.decodeIfPresent(Double.self, forKey: .x)
        y = try container.decodeIfPresent(Double.self, forKey: .y)
        layout = try container.decode(BrowserGridLayoutRequestDTO.self, forKey: .layout)
        let decodedCells = try container.decode([BrowserGridCellRequestDTO].self, forKey: .cells)
        try BrowserSurfaceRequestValidationError.validateUniqueCellIDs(decodedCells.map(\.id))
        cells = decodedCells
        width = try container.decodeIfPresent(Double.self, forKey: .width)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
    }
}

public struct BrowserUpdateGridRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let title: String?
    public let layout: BrowserGridLayoutRequestDTO?
    public let cells: [BrowserGridCellRequestDTO]?
    public let imageMode: ImageMode?
    public let debug: Bool?

    public var grid: String { browser }

    public init(grid: String, title: String? = nil, layout: BrowserGridLayoutRequestDTO? = nil, cells: [BrowserGridCellRequestDTO]? = nil, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = grid
        self.title = title
        self.layout = layout
        self.cells = cells
        self.imageMode = imageMode
        self.debug = debug
    }

    enum CodingKeys: String, CodingKey {
        case browser
        case grid
        case title
        case layout
        case cells
        case imageMode
        case debug
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        browser = try container.decodeIfPresent(String.self, forKey: .browser)
            ?? container.decode(String.self, forKey: .grid)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        layout = try container.decodeIfPresent(BrowserGridLayoutRequestDTO.self, forKey: .layout)
        let decodedCells = try container.decodeIfPresent([BrowserGridCellRequestDTO].self, forKey: .cells)
        if let decodedCells {
            try BrowserSurfaceRequestValidationError.validateUniqueCellIDs(decodedCells.map(\.id))
        }
        cells = decodedCells
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(browser, forKey: .browser)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(layout, forKey: .layout)
        try container.encodeIfPresent(cells, forKey: .cells)
        try container.encodeIfPresent(imageMode, forKey: .imageMode)
        try container.encodeIfPresent(debug, forKey: .debug)
    }
}

public struct BrowserGetGridStateRequest: Codable, Sendable, DebugNotesRequest {
    public let browser: String
    public let imageMode: ImageMode?
    public let debug: Bool?

    public var grid: String { browser }

    public init(grid: String, imageMode: ImageMode? = nil, debug: Bool? = nil) {
        self.browser = grid
        self.imageMode = imageMode
        self.debug = debug
    }

    enum CodingKeys: String, CodingKey {
        case browser
        case grid
        case imageMode
        case debug
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        browser = try container.decodeIfPresent(String.self, forKey: .browser)
            ?? container.decode(String.self, forKey: .grid)
        imageMode = try container.decodeIfPresent(ImageMode.self, forKey: .imageMode)
        debug = try container.decodeIfPresent(Bool.self, forKey: .debug)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(browser, forKey: .browser)
        try container.encodeIfPresent(imageMode, forKey: .imageMode)
        try container.encodeIfPresent(debug, forKey: .debug)
    }
}

public struct BrowserGridStateDTO: Codable, Sendable {
    public let target: BrowserTargetSummaryDTO
    public let layout: BrowserGridLayoutRequestDTO
    public let cells: [BrowserGridCellSummaryDTO]
    public let screenshot: ScreenshotDTO?
    public let warnings: [String]

    public init(
        target: BrowserTargetSummaryDTO,
        layout: BrowserGridLayoutRequestDTO,
        cells: [BrowserGridCellSummaryDTO],
        screenshot: ScreenshotDTO? = nil,
        warnings: [String] = []
    ) {
        self.target = target
        self.layout = layout
        self.cells = cells
        self.screenshot = screenshot
        self.warnings = warnings
    }
}

public struct BrowserGridStateResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let grid: BrowserGridStateDTO
    public let notes: [String]

    public init(
        contractVersion: String = ContractVersion.current,
        ok: Bool,
        grid: BrowserGridStateDTO,
        notes: [String]
    ) {
        self.contractVersion = contractVersion
        self.ok = ok
        self.grid = grid
        self.notes = notes
    }
}

public typealias BrowserCreateGridResponse = BrowserGridStateResponse
public typealias BrowserUpdateGridResponse = BrowserGridStateResponse

public enum BrowserSurfaceRequestValidationError: Error, CustomStringConvertible, Sendable {
    case invalidCellID(String)
    case duplicateCellID(String)

    public var description: String {
        switch self {
        case .invalidCellID(let value):
            return "Browser grid cell id '\(value)' must be non-empty."
        case .duplicateCellID(let value):
            return "Browser grid cell id '\(value)' must be unique within a grid request."
        }
    }

    static func validateUniqueCellIDs(_ ids: [String]) throws {
        var seen: Set<String> = []
        for id in ids {
            guard seen.insert(id).inserted else {
                throw duplicateCellID(id)
            }
        }
    }
}

public struct BrowserEventDTO: Codable, Sendable {
    public let eventID: String
    public let targetID: String?
    public let scriptID: String?
    public let type: String
    public let payload: JSONValueDTO
    public let emittedAt: String
}

public struct BrowserEmitEventRequest: Codable, Sendable {
    public let browser: String?
    public let scriptID: String?
    public let type: String
    public let payload: JSONValueDTO?
}

public struct BrowserEmitEventResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let event: BrowserEventDTO
}

public struct BrowserPollEventsRequest: Codable, Sendable {
    public let sinceEventID: String?
    public let browser: String?
    public let limit: Int?
}

public struct BrowserPollEventsResponse: Codable, Sendable {
    public let contractVersion: String
    public let events: [BrowserEventDTO]
    public let latestEventID: String?
}

public struct BrowserClearEventsRequest: Codable, Sendable {
    public let browser: String?
}

public struct BrowserClearEventsResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let removedCount: Int
}
