import Foundation

enum BrowserSurfaceError: Error, CustomStringConvertible {
    case targetNotFound(String)
    case invalidURL(String)
    case invalidRequest(String)
    case scriptNotFound(String)
    case javascriptFailed(String)
    case providerBridgeFailed(String)
    case targetAmbiguous(String)
    case unsupportedRegisteredProvider(String)
    case timedOut(String)

    var description: String {
        switch self {
        case .targetNotFound(let target):
            return "No owned or registered browser target matched '\(target)'."
        case .invalidURL(let value):
            return "Invalid browser URL '\(value)'."
        case .invalidRequest(let message):
            return message
        case .scriptNotFound(let scriptID):
            return "No injected script matched '\(scriptID)'."
        case .javascriptFailed(let message):
            return "JavaScript execution failed: \(message)"
        case .providerBridgeFailed(let message):
            return "Provider bridge failed: \(message)"
        case .targetAmbiguous(let message):
            return message
        case .unsupportedRegisteredProvider(let target):
            return "Registered browser target '\(target)' does not have a live control bridge in this runtime."
        case .timedOut(let message):
            return message
        }
    }
}
