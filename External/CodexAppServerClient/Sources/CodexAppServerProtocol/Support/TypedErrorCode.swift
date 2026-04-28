import Foundation

/// Typed access to the `codexErrorInfo` enum variant carried by an ``ErrorNotification``.
///
/// The server attaches a structured error classification (``CodexErrorInfoEnum``) to
/// every error notification when the failure fits one of the enumerated categories —
/// rate limits, context window exceeded, sandbox errors, authorization failures, etc.
/// This shortcut pulls the typed code out of the nested union wrapper so consumers
/// can switch on it directly without unwrapping the `.enumeration(…)` case by hand.
///
/// Returns `nil` when:
/// - the server attached no typed code (`error.codexErrorInfo == nil`), or
/// - the error carried a struct-shaped variant (e.g. `httpConnectionFailed`) that
///   doesn't fit the enum taxonomy.
///
/// ```swift
/// for await note in await client.notifications(of: ServerNotifications.Error.self) {
///     switch note.typedCode {
///     case .contextWindowExceeded: showCompactionPrompt()
///     case .usageLimitExceeded: showUpgradeSheet()
///     case .unauthorized: reauthenticate()
///     default: showGenericError(note.error.message)
///     }
/// }
/// ```
extension ErrorNotification {
    public var typedCode: CodexErrorInfoEnum? {
        switch error.codexErrorInfo {
        case .enumeration(let code):
            return code
        case .purpleCodexErrorInfo, .null, .none:
            return nil
        }
    }
}
