import Foundation

enum BrowserSurfaceError: Error, CustomStringConvertible {
    case targetNotFound(String)
    case invalidURL(String)
    case invalidRequest(String)
    case scriptNotFound(String)
    case javascriptFailed(String)
    case targetAmbiguous(String)
    case timedOut(String)

    var description: String {
        switch self {
        case .targetNotFound(let target):
            return "No owned browser target matched '\(target)'."
        case .invalidURL(let value):
            return "Invalid browser URL '\(value)'."
        case .invalidRequest(let message):
            return message
        case .scriptNotFound(let scriptID):
            return "No injected script matched '\(scriptID)'."
        case .javascriptFailed(let message):
            return "JavaScript execution failed: \(message)"
        case .targetAmbiguous(let message):
            return message
        case .timedOut(let message):
            return message
        }
    }
}
