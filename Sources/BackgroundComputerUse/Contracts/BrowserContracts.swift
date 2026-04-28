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

    static func from(any value: Any?) -> JSONValueDTO {
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

public enum BrowserTargetKindDTO: String, Codable, Sendable {
    case ownedBrowserWindow = "owned_browser_window"
    case ownedBrowserTab = "owned_browser_tab"
    case registeredBrowserSurface = "registered_browser_surface"
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
    public let hostWindow: BrowserHostWindowDTO?
    public let capabilities: BrowserTargetCapabilitiesDTO
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
}

public struct BrowserFocusedElementDTO: Codable, Sendable {
    public let nodeID: String?
    public let tagName: String?
    public let role: String?
    public let text: String?
    public let valuePreview: String?
    public let isEditable: Bool
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
}

public struct BrowserDOMSnapshotDTO: Codable, Sendable {
    public let viewport: BrowserViewportDTO
    public let focusedElement: BrowserFocusedElementDTO?
    public let interactables: [BrowserInteractableDTO]
    public let rawText: String?
    public let nodeCount: Int
}

public struct BrowserPerformanceDTO: Codable, Sendable {
    public let resolveMs: Double
    public let domMs: Double
    public let screenshotMs: Double
    public let totalMs: Double
}

public struct BrowserCreateWindowRequest: Decodable, Sendable, DebugNotesRequest {
    public let url: String?
    public let title: String?
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
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        userAgent: String? = nil,
        activate: Bool? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
        self.url = url
        self.title = title
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.userAgent = userAgent
        self.activate = activate
        self.imageMode = imageMode
        self.debug = debug
    }
}

public struct BrowserCreateWindowResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let target: BrowserTargetSummaryDTO
    public let state: BrowserGetStateResponse?
    public let notes: [String]
}

public struct BrowserListTargetsRequest: Decodable, Sendable {
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

    public init(
        browser: String,
        url: String,
        waitUntilLoaded: Bool? = nil,
        timeoutMs: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
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

    public init(
        browser: String,
        maxElements: Int? = nil,
        includeRawText: Bool? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
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

    public init(
        browser: String,
        javaScript: String,
        timeoutMs: Int? = nil,
        debug: Bool? = nil
    ) {
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

    public init(
        browser: String,
        stateToken: String? = nil,
        target: BrowserActionTargetRequestDTO,
        clickCount: Int? = nil,
        cursor: CursorRequestDTO? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
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

    public init(
        browser: String,
        stateToken: String? = nil,
        x: Double,
        y: Double,
        clickCount: Int? = nil,
        cursor: CursorRequestDTO? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
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

    public init(
        browser: String,
        stateToken: String? = nil,
        target: BrowserActionTargetRequestDTO? = nil,
        text: String,
        append: Bool? = nil,
        cursor: CursorRequestDTO? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
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

    public init(
        browser: String,
        stateToken: String? = nil,
        target: BrowserActionTargetRequestDTO? = nil,
        direction: ScrollDirectionDTO,
        pages: Int? = nil,
        cursor: CursorRequestDTO? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
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

public struct BrowserActionResponse: Codable, Sendable {
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

    public init(
        browser: String,
        waitUntilLoaded: Bool? = nil,
        timeoutMs: Int? = nil,
        imageMode: ImageMode? = nil,
        debug: Bool? = nil
    ) {
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

public struct BrowserEventDTO: Codable, Sendable {
    public let eventID: String
    public let targetID: String?
    public let scriptID: String?
    public let type: String
    public let payload: JSONValueDTO
    public let emittedAt: String
}

public struct BrowserEmitEventRequest: Decodable, Sendable {
    public let browser: String?
    public let scriptID: String?
    public let type: String
    public let payload: JSONValueDTO?

    public init(
        browser: String? = nil,
        scriptID: String? = nil,
        type: String,
        payload: JSONValueDTO? = nil
    ) {
        self.browser = browser
        self.scriptID = scriptID
        self.type = type
        self.payload = payload
    }
}

public struct BrowserEmitEventResponse: Encodable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let event: BrowserEventDTO
}

public struct BrowserPollEventsRequest: Decodable, Sendable {
    public let sinceEventID: String?
    public let browser: String?
    public let limit: Int?

    public init(sinceEventID: String? = nil, browser: String? = nil, limit: Int? = nil) {
        self.sinceEventID = sinceEventID
        self.browser = browser
        self.limit = limit
    }
}

public struct BrowserPollEventsResponse: Encodable, Sendable {
    public let contractVersion: String
    public let events: [BrowserEventDTO]
    public let latestEventID: String?
}

public struct BrowserClearEventsRequest: Decodable, Sendable {
    public let browser: String?

    public init(browser: String? = nil) {
        self.browser = browser
    }
}

public struct BrowserClearEventsResponse: Encodable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let removedCount: Int
}

public struct BrowserRegisteredProviderSurfaceDTO: Codable, Sendable {
    public let surfaceID: String
    public let title: String
    public let url: String?
    public let hostWindow: BrowserHostWindowDTO?
    public let capabilities: BrowserTargetCapabilitiesDTO

    public init(
        surfaceID: String,
        title: String,
        url: String? = nil,
        hostWindow: BrowserHostWindowDTO? = nil,
        capabilities: BrowserTargetCapabilitiesDTO
    ) {
        self.surfaceID = surfaceID
        self.title = title
        self.url = url
        self.hostWindow = hostWindow
        self.capabilities = capabilities
    }
}

public struct BrowserProviderCommandEnvelopeDTO<Request: Codable & Sendable>: Codable, Sendable {
    public let contractVersion: String
    public let providerID: String
    public let providerDisplayName: String
    public let protocolVersion: Int
    public let surfaceID: String
    public let targetID: String
    public let command: String
    public let request: Request

    public init(
        contractVersion: String = ContractVersion.current,
        providerID: String,
        providerDisplayName: String,
        protocolVersion: Int,
        surfaceID: String,
        targetID: String,
        command: String,
        request: Request
    ) {
        self.contractVersion = contractVersion
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.protocolVersion = protocolVersion
        self.surfaceID = surfaceID
        self.targetID = targetID
        self.command = command
        self.request = request
    }
}

public struct BrowserRegisterProviderRequest: Codable, Sendable {
    public let providerID: String
    public let displayName: String
    public let baseURL: String?
    public let protocolVersion: Int
    public let browserSurfaces: [BrowserRegisteredProviderSurfaceDTO]

    public init(
        providerID: String,
        displayName: String,
        baseURL: String? = nil,
        protocolVersion: Int,
        browserSurfaces: [BrowserRegisteredProviderSurfaceDTO]
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.baseURL = baseURL
        self.protocolVersion = protocolVersion
        self.browserSurfaces = browserSurfaces
    }
}

public struct BrowserRegisterProviderResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let providerID: String
    public let targets: [BrowserTargetSummaryDTO]
    public let notes: [String]
}

public struct BrowserUnregisterProviderRequest: Codable, Sendable {
    public let providerID: String

    public init(providerID: String) {
        self.providerID = providerID
    }
}

public struct BrowserUnregisterProviderResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let removedTargetCount: Int
    public let notes: [String]
}
