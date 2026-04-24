import Foundation

protocol DebugNotesRequest {
    var debug: Bool? { get }
}

struct ListAppsRequest: Decodable {}

struct ListWindowsRequest: Decodable {
    let app: String
}

struct GetWindowStateRequest: Decodable {
    let window: String
    let includeMenuBar: Bool?
    let menuPath: [String]?
    let webTraversal: AXWebTraversalMode?
    let maxNodes: Int?
    let imageMode: ImageMode?
    let includeRawScreenshot: Bool?
    let debugMode: StateDebugModeDTO?
    let debug: Bool?
    let includeRawCapture: Bool?
    let includeSemanticTree: Bool?
    let includeProjectedTree: Bool?
    let includePlatformProfile: Bool?
    let includeDiagnostics: Bool?
}

struct ClickRequest: Decodable {
    let window: String
    let stateToken: String?
    let elementIndex: Int?
    let x: Double?
    let y: Double?
    let mode: ClickModeDTO?
    let clickCount: Int?
    let mouseButton: MouseButtonDTO?
    let cursor: CursorRequestDTO?
    let includeMenuBar: Bool?
    let maxNodes: Int?
    let imageMode: ImageMode?
    let debug: Bool?
}

struct ScrollRequest: Decodable {
    let window: String
    let stateToken: String?
    let elementIndex: Int
    let direction: ScrollDirectionDTO
    let pages: Int?
    let verificationMode: ActionVerificationModeDTO?
    let cursor: CursorRequestDTO?
    let includeMenuBar: Bool?
    let maxNodes: Int?
    let imageMode: ImageMode?
    let debug: Bool?
}

struct PerformSecondaryActionRequest: Decodable {
    let window: String
    let stateToken: String?
    let elementIndex: Int
    let action: String
    let actionID: String?
    let menuPath: [String]?
    let webTraversal: AXWebTraversalMode?
    let cursor: CursorRequestDTO?
    let includeMenuBar: Bool?
    let maxNodes: Int?
    let imageMode: ImageMode?
    let debug: Bool?
}

struct DragRequest: Decodable {
    let window: String
    let toX: Double
    let toY: Double
    let cursor: CursorRequestDTO?
}

struct ResizeRequest: Decodable {
    let window: String
    let handle: ResizeHandleDTO
    let toX: Double
    let toY: Double
    let cursor: CursorRequestDTO?
}

struct SetWindowFrameRequest: Decodable {
    let window: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let animate: Bool?
    let cursor: CursorRequestDTO?
}

struct TypeTextRequest: Decodable {
    let window: String
    let stateToken: String?
    let elementIndex: Int?
    let text: String
    let focusAssistMode: TypeTextFocusAssistModeDTO?
    let cursor: CursorRequestDTO?
    let includeMenuBar: Bool?
    let maxNodes: Int?
    let imageMode: ImageMode?
    let debug: Bool?
}

struct PressKeyRequest: Decodable {
    let window: String
    let stateToken: String?
    let key: String
    let cursor: CursorRequestDTO?
    let includeMenuBar: Bool?
    let maxNodes: Int?
    let imageMode: ImageMode?
    let debug: Bool?
}

struct SetValueRequest: Decodable {
    let window: String
    let stateToken: String?
    let elementIndex: Int
    let value: String
    let cursor: CursorRequestDTO?
    let includeMenuBar: Bool?
    let maxNodes: Int?
    let imageMode: ImageMode?
    let debug: Bool?
}

extension ClickRequest: DebugNotesRequest {}
extension ScrollRequest: DebugNotesRequest {}
extension PerformSecondaryActionRequest: DebugNotesRequest {}
extension TypeTextRequest: DebugNotesRequest {}
extension PressKeyRequest: DebugNotesRequest {}
extension SetValueRequest: DebugNotesRequest {}
