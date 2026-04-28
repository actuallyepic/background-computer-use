import Foundation
import CodexAppServerProtocol

/// How strictly to enforce that the running codex binary matches the version pinned to this
/// Swift package.
///
/// Default is ``exact``. For ``CodexConnection/localManaged(_:)`` this checks the locally
/// installed `codex` binary's `--version` output against `CodexBindingMetadata.codexVersion`
/// before the child process is even spawned — when both are in lockstep (the supported
/// release model), `.exact` succeeds and is the right choice. Reach for ``allowMismatch``
/// only when you genuinely cannot pin the binary (e.g. development machines running a
/// drifted local build).
public enum VersionPolicy: Sendable {
    /// Require the connected codex to match `CodexBindingMetadata.codexVersion` exactly.
    case exact
    /// Permit any codex version. The protocol wire format may drift; use with care.
    case allowMismatch
}

#if os(macOS)
/// Options controlling a locally launched codex app-server process.
public struct LocalServerOptions: Sendable {
    /// Path to the codex executable (resolved via `$PATH` if just a name). Defaults to `"codex"`.
    public var codexExecutable: String?
    /// Working directory for the child process. Defaults to the current process directory.
    public var workingDirectory: URL?
    /// Environment variables added to or overriding the current process environment.
    /// Entries here override ``codexHome`` if the same key (`CODEX_HOME`) is set in both.
    public var environment: [String: String]
    /// Override the codex configuration directory. Forwarded to the child process as
    /// `CODEX_HOME`. Defaults to nil — codex resolves `~/.codex` as usual.
    ///
    /// The directory is created (with intermediate directories) before the child is
    /// launched if it doesn't already exist — codex itself crashes immediately when
    /// `CODEX_HOME` points to a nonexistent path.
    ///
    /// Useful for sandbox testing, CI isolation, or running multiple codex instances
    /// against separate config / auth state.
    public var codexHome: URL?
    /// Config overrides forwarded as `-c key=value` to `codex app-server`.
    ///
    /// Equivalent to passing `["-c", "key=value", ...]` via ``extraArguments``. Most
    /// `~/.codex/config.toml` keys (e.g. `sandbox_mode`,
    /// `features.exec_permission_approvals`) are reachable this way. Per-thread
    /// alternatives on `ThreadStartParams` (`sandbox`, `model`, `cwd`, freeform `config`)
    /// are usually preferable when they exist.
    public var extraConfig: [String: String]
    /// Additional command-line arguments appended to `codex app-server`.
    ///
    /// Use for flags with no JSON-RPC equivalent (e.g. `--enable foo` / `--disable bar`,
    /// websocket auth flags). Reach for typed protocol params on `ThreadStartParams`
    /// first when available.
    public var extraArguments: [String]
    /// How long to wait for the spawned codex process to report ready before failing.
    /// Raise this on cold-start machines, CI boxes with slow disks, or when running
    /// a debug-build codex that takes longer to initialise. Defaults to 10 seconds.
    public var readinessTimeout: Duration

    public init(
        codexExecutable: String? = nil,
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        codexHome: URL? = nil,
        extraConfig: [String: String] = [:],
        extraArguments: [String] = [],
        readinessTimeout: Duration = .seconds(10)
    ) {
        self.codexExecutable = codexExecutable
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.codexHome = codexHome
        self.extraConfig = extraConfig
        self.extraArguments = extraArguments
        self.readinessTimeout = readinessTimeout
    }
}
#endif

/// Options for connecting to a pre-running codex app-server over the network.
public struct RemoteServerOptions: Sendable {
    /// Websocket URL (`ws://…` or `wss://…`). Bearer auth requires `wss` or a loopback host
    /// unless ``allowInsecureBearer`` is set.
    public var url: URL
    /// Optional bearer token; sent as `Authorization: Bearer <token>`.
    public var authToken: String?
    /// Version of the remote codex. Required when `versionPolicy == .exact`.
    public var codexVersion: String?
    /// Permit sending the bearer `authToken` over plain `ws://` to a non-loopback host.
    /// Defaults to `false` — the default only allows bearer auth on `wss://` or loopback
    /// `ws://`, because sending a secret over unencrypted transport is almost always a
    /// mistake. Set to `true` only for trusted same-subnet / VPN-only deployments where
    /// TLS termination lives elsewhere.
    public var allowInsecureBearer: Bool

    public init(
        url: URL,
        authToken: String? = nil,
        codexVersion: String? = nil,
        allowInsecureBearer: Bool = false
    ) {
        self.url = url
        self.authToken = authToken
        self.codexVersion = codexVersion
        self.allowInsecureBearer = allowInsecureBearer
    }
}

/// Where to find the codex app-server this client connects to.
public enum CodexConnection: Sendable {
#if os(macOS)
    /// Launch and manage a local codex app-server subprocess (macOS only).
    case localManaged(LocalServerOptions = .init())
#endif
    /// Connect to a codex app-server already running at a remote URL.
    case remote(RemoteServerOptions)
}

/// Client-side configuration passed to ``CodexClient/connect(_:options:)``.
public struct CodexClientOptions: Sendable {
    /// Whether to advertise support for experimental app-server APIs. Defaults to `true`.
    public var experimentalAPI: Bool
    /// Whether to enforce codex version match. Defaults to ``VersionPolicy/exact``.
    public var versionPolicy: VersionPolicy
    /// Identity of this client (name, title, version) reported to the server during initialize.
    public var clientInfo: ClientInfo

    public init(
        experimentalAPI: Bool = true,
        versionPolicy: VersionPolicy = .exact,
        clientInfo: ClientInfo
    ) {
        self.experimentalAPI = experimentalAPI
        self.versionPolicy = versionPolicy
        self.clientInfo = clientInfo
    }
}

/// Why a ``CodexClient`` became (or failed to stay) connected.
///
/// Attached to ``ConnectionState/disconnected(_:)`` and
/// ``CodexClientError/connectionClosed(_:)`` so consumers can surface meaningful
/// recovery UI without parsing free-form strings.
public enum DisconnectReason: Sendable, Equatable, CustomStringConvertible {
    /// Caller invoked ``CodexClient/disconnect()``. Not an error.
    case clientRequested
    /// The WebSocket closed. `code` is the close code sent by the peer if any,
    /// `reason` is the URLSession-supplied description.
    case webSocketClosed(code: URLSessionWebSocketTask.CloseCode?, reason: String)
    /// A network-level failure terminated the connection.
    case networkError(URLError)
    /// The locally managed codex process exited. `status` is the reported exit
    /// code when available; `description` is the best-effort reason.
    case processExited(status: Int32?, description: String)
    /// The `initialize` handshake or version check failed.
    case handshakeFailed(String)
    /// Generic fallback carrying a best-effort message.
    case other(String)

    public var description: String {
        switch self {
        case .clientRequested:
            return "client requested disconnect"
        case .webSocketClosed(let code, let reason):
            if let code {
                return "websocket closed (code=\(code.rawValue)): \(reason)"
            }
            return "websocket closed: \(reason)"
        case .networkError(let error):
            return "network error: \(error.localizedDescription)"
        case .processExited(let status, let description):
            if let status {
                return "codex process exited (status=\(status)): \(description)"
            }
            return "codex process exited: \(description)"
        case .handshakeFailed(let message):
            return "handshake failed: \(message)"
        case .other(let message):
            return message
        }
    }
}

/// High-level connection lifecycle phase reported via ``CodexEvent/connectionStateChanged(_:)``.
public enum ConnectionState: Sendable, Equatable {
    /// The client is launching the local process and/or opening the websocket.
    case connecting
    /// The websocket is open; `initialize` has not yet completed.
    case connected
    /// The `initialize` handshake has finished; RPC calls may now be issued.
    case initialized
    /// The client has been disconnected. Carries the reason so UIs can render
    /// an accurate error state without consulting a second event.
    case disconnected(DisconnectReason)
}

/// An event observable through ``CodexClient/events(bufferSize:)``.
public enum CodexEvent: Sendable {
    /// Reports a change in the connection lifecycle. ``ConnectionState/disconnected(_:)``
    /// carries the reason directly — there is no separate "disconnected" event.
    case connectionStateChanged(ConnectionState)
    /// A typed server-to-client notification.
    case notification(ServerNotificationEvent)
    /// A typed server-to-client request. Respond via ``CodexClient/respond(to:result:)`` or ``CodexClient/reject(_:code:message:)``.
    case serverRequest(AnyTypedServerRequest)
    /// A JSON frame that failed to parse as JSON-RPC.
    case invalidMessage(rawJSON: Data, errorDescription: String)
    /// A JSON-RPC message with a method string this library does not recognise (likely version skew).
    case unknownMessage(method: String, rawJSON: Data)
    /// Emitted when a slow consumer dropped events due to buffer overflow. `skipped` counts dropped events.
    case lagged(skipped: Int)
    /// A line of stderr output from the locally managed codex process.
    case processLog(line: String)
}

/// Errors surfaced by ``CodexClient``.
public enum CodexClientError: Error, LocalizedError, Sendable {
    case executableLookupFailed(String)
    case missingRemoteVersion
    case versionMismatch(expected: String, actual: String)
    case unsupportedBearerTransport(URL)
    case invalidRemoteURL(String)
    case notConnected
    /// The websocket failed to open before the system-default timeout. `url`
    /// is the address that was being dialled.
    case connectTimeout(URL)
    /// The connection closed before the pending RPC received a response.
    case connectionClosed(DisconnectReason)
    /// The server returned a JSON-RPC error. See ``isThreadNotFound`` and
    /// other helpers for promoting this to a more specific condition.
    case rpcError(code: Int, message: String)
    /// The server indicated the referenced thread does not exist. Common when
    /// resuming a persisted thread whose rollout was pruned. The associated
    /// string is the raw server message for diagnostic display.
    case threadNotFound(String)
    case invalidResponse(String)
    case processLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableLookupFailed(let executable):
            "Unable to execute codex binary: \(executable)"
        case .missingRemoteVersion:
            "Remote connections require an explicit codexVersion when using exact version policy"
        case .versionMismatch(let expected, let actual):
            "Codex version mismatch. Expected \(expected), got \(actual)"
        case .unsupportedBearerTransport(let url):
            "Bearer auth requires wss:// or loopback ws:// URLs: \(url.absoluteString)"
        case .invalidRemoteURL(let value):
            "Invalid remote URL: \(value)"
        case .notConnected:
            "WebSocket is not connected"
        case .connectTimeout(let url):
            "Timed out opening websocket to \(url.absoluteString)"
        case .connectionClosed(let reason):
            "Connection closed: \(reason.description)"
        case .rpcError(_, let message):
            "RPC error: \(message)"
        case .threadNotFound(let message):
            "Thread not found: \(message)"
        case .invalidResponse(let message):
            "Invalid response: \(message)"
        case .processLaunchFailed(let message):
            "Failed to launch codex app-server: \(message)"
        }
    }
}

public extension InitializeResponse {
    /// The codex semver version parsed from ``userAgent``, or `nil` if no version
    /// substring could be located.
    ///
    /// `userAgent` is the *combined* server+client identity string codex assembles
    /// during `initialize`, formatted as:
    /// `"<originator>/<codex-version> (<OS>; <arch>) <terminal-UA> (<clientName>; <clientVersion>)"`.
    /// The `<originator>` prefix is process-global on the codex side and may be
    /// overwritten by the first client's `clientInfo.name` rather than the literal
    /// `"codex_cli_rs"` — never key off the prefix. Use this property to extract the
    /// underlying codex version, which is the only stable component.
    var codexVersion: String? {
        CodexVersionChecker.parseVersion(from: userAgent)
    }
}

public extension CodexClientError {
    /// Whether this error indicates the referenced thread no longer exists.
    ///
    /// Detects both ``threadNotFound(_:)`` and ``rpcError(code:message:)``
    /// whose message text matches the codex app-server convention. Useful in a
    /// single `catch` clause that falls back to starting a fresh thread.
    ///
    /// ```swift
    /// do {
    ///     _ = try await client.call(RPC.ThreadResume.self, params: params)
    /// } catch let error as CodexClientError where error.isThreadNotFound {
    ///     // saved thread id is stale; start fresh
    /// }
    /// ```
    var isThreadNotFound: Bool {
        switch self {
        case .threadNotFound:
            return true
        case .rpcError(_, let message):
            let lower = message.lowercased()
            return lower.contains("thread not found")
                || lower.contains("thread does not exist")
                || lower.contains("unknown thread")
                || lower.contains("no such thread")
        default:
            return false
        }
    }
}
