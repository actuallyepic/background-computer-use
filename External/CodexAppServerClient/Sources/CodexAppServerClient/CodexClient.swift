import Foundation
import os
@_exported import CodexAppServerProtocol

let codexClientLogger = Logger(subsystem: "xyz.dubdubdub.codex-app-server-client", category: "client")

/// A generic client for the codex app-server JSON-RPC protocol.
///
/// `CodexClient` connects to a locally launched or remote codex app-server, performs the
/// `initialize` handshake, and exposes typed request/response, notification, and server-request APIs.
/// Create one with ``connect(_:options:)`` and observe activity via ``events(bufferSize:)``.
///
/// The client is an `actor`: all state mutations are serialised. Multiple consumers may each call
/// ``events(bufferSize:)`` to receive their own multicast event stream.
///
/// Call ``disconnect()`` when finished to tear down the websocket and (for local launches) the
/// child process. Forgetting to disconnect leaks the local process until the Swift task holding
/// the client is deallocated.
public actor CodexClient {
    /// The server information returned by the `initialize` handshake, or `nil` before connect.
    public private(set) var serverInfo: InitializeResponse?

    /// The most recent connection lifecycle state observed by this client.
    ///
    /// `nil` before the first connection attempt; otherwise always reflects the last
    /// state change emitted on the event stream. Readers that mount after a disconnect
    /// can read ``currentConnectionState`` directly instead of racing to observe the
    /// transient event — handy for late-binding UI.
    public private(set) var currentConnectionState: ConnectionState?

    private let encoder = newJSONEncoder()
    private let decoder = newJSONDecoder()

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var delegate: WebSocketOpenDelegate?
    private var listenTask: Task<Void, Never>?
#if os(macOS)
    internal var localProcess: LocalCodexAppServerProcess?
#endif
    private var nextRequestID = 1
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
    private var connected = false

    private var subscribers: [UUID: AsyncStream<CodexEvent>.Continuation] = [:]
    private var subscriberDropCounts: [UUID: Int] = [:]
    private var streamIsFinished = false

    public init() {}

    /// Subscribe to the client event stream.
    ///
    /// Each call returns a fresh `AsyncStream` — multiple consumers receive independent copies
    /// of every event. The stream uses a bounded buffer; when a slow consumer falls behind,
    /// excess events are dropped and a ``CodexEvent/lagged(skipped:)`` marker is inserted to
    /// signal the gap. Drain the stream promptly to avoid lag.
    ///
    /// Events emitted before subscription are not retained. Subscribe prior to the work that
    /// produces the events you want to observe.
    ///
    /// > Important: When the underlying connection drops the stream finishes silently — the
    /// > `for await` loop simply exits without an error. Pair with
    /// > ``connectionStates(bufferSize:)`` if you need to distinguish a clean shutdown
    /// > from an unexpected disconnect.
    ///
    /// - Parameter bufferSize: Maximum per-consumer buffered events. Defaults to 1024. Uses
    ///   the `.bufferingOldest` policy: when full, oldest events are kept and newest are
    ///   dropped. Use ``events(bufferingPolicy:)`` to choose `.bufferingNewest` (drop oldest)
    ///   or `.unbounded`.
    public func events(bufferSize: Int = 1024) -> AsyncStream<CodexEvent> {
        events(bufferingPolicy: .bufferingOldest(bufferSize))
    }

    /// Subscribe to the client event stream with an explicit buffering policy.
    ///
    /// Use `.bufferingNewest(N)` to keep the most recent events and discard older ones — handy
    /// for inspector / dev panels that care about *current* state more than completeness. Use
    /// `.unbounded` only when you can guarantee draining; the buffer grows without limit
    /// otherwise.
    ///
    /// > Important: Same lifecycle as ``events(bufferSize:)`` — finishes silently on
    /// > disconnect.
    public func events(
        bufferingPolicy: AsyncStream<CodexEvent>.Continuation.BufferingPolicy
    ) -> AsyncStream<CodexEvent> {
        let id = UUID()
        let stream = AsyncStream<CodexEvent>(bufferingPolicy: bufferingPolicy) { continuation in
            if streamIsFinished {
                continuation.finish()
                return
            }
            subscribers[id] = continuation
            subscriberDropCounts[id] = 0
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeSubscriber(id) }
            }
        }
        return stream
    }

    /// Observe a specific typed notification method as an `AsyncStream` of its params.
    ///
    /// Filters the main event stream and extracts the matching params value. Useful when only
    /// one notification type is of interest — avoids switching on the whole `CodexEvent` enum.
    ///
    /// ```swift
    /// for await delta in await client.notifications(of: ServerNotifications.ItemAgentMessageDelta.self) {
    ///     print(delta.delta)
    /// }
    /// ```
    public func notifications<Method: CodexServerNotificationMethod>(
        of method: Method.Type,
        bufferSize: Int = 1024
    ) -> AsyncStream<Method.Params> where Method.Params: Sendable {
        let base = events(bufferSize: bufferSize)
        return AsyncStream { continuation in
            let task = Task {
                for await event in base {
                    if Task.isCancelled { break }
                    if case .notification(let notification) = event,
                       let params = notification.params(as: Method.self) {
                        continuation.yield(params)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
        subscriberDropCounts.removeValue(forKey: id)
    }

    /// Connect to a codex app-server.
    ///
    /// Launches the codex process (for `.localManaged`) or opens a websocket to the remote URL,
    /// runs the `initialize` handshake, and returns a ready-to-use client.
    ///
    /// - Throws: `CodexClientError` on launch, version-mismatch, or handshake failure.
    public static func connect(
        _ connection: CodexConnection,
        options: CodexClientOptions
    ) async throws -> CodexClient {
        let client = CodexClient()
        try await client.bootstrap(connection, options: options)
        return client
    }

    /// Invoke a typed client-to-server request.
    ///
    /// The request is encoded, dispatched over the websocket, and awaited until the server
    /// replies (or the connection closes). Cancellation of the calling task cancels the pending
    /// request.
    ///
    /// > Important: For RPCs whose work continues server-side after the response (notably
    /// > `RPC.TurnStart`, which returns a `turnId` after a quick handshake and then streams
    /// > deltas via subsequent notifications), task cancellation only affects the synchronous
    /// > handshake — *not* the server-side work. Use `RPC.TurnInterrupt` to stop a
    /// > running turn, or use ``streamTurn(input:threadId:)`` which wraps the full lifecycle.
    ///
    /// - Throws: `CodexClientError.rpcError` if the server returned a JSON-RPC error,
    ///   `CodexClientError.connectionClosed` if the connection drops mid-flight,
    ///   `CodexClientError.threadNotFound` when the message matches the codex
    ///   thread-not-found convention, `CancellationError` if the calling task is cancelled.
    public func call<Method: CodexRPCMethod>(
        _ method: Method.Type,
        params: Method.Params
    ) async throws -> Method.Response {
        let data = try await request(method: method.method.rawValue, params: params)
        return try decoder.decode(JSONRPCSuccessResponse<Method.Response>.self, from: data).result
    }

    /// Send a success response to a typed server-to-client request.
    public func respond<Method: CodexServerRequestMethod>(
        to request: TypedServerRequest<Method>,
        result: Method.Response
    ) async throws {
        try await sendResponse(id: request.id, result: result)
    }

    /// Reject a server-initiated request by id with a JSON-RPC error.
    ///
    /// Defaults to JSON-RPC internal-error code `-32603`. Use `-32601` for "method not found".
    public func reject(
        requestID: RequestId,
        code: Int = -32603,
        message: String
    ) async throws {
        let envelope = JSONRPCOutgoingErrorResponse(
            id: requestID,
            error: JSONRPCErrorPayload(code: code, message: message)
        )
        try await sendEncodable(envelope)
    }

    /// Reject an untyped server-initiated request.
    public func reject(
        _ request: AnyTypedServerRequest,
        code: Int = -32603,
        message: String
    ) async throws {
        try await reject(requestID: request.id, code: code, message: message)
    }

    /// Shut down the websocket, cancel pending requests, and (for local launches) terminate
    /// the codex app-server process. All active event streams are finished.
    ///
    /// It is always safe to call `disconnect` more than once.
    public func disconnect() async {
        await shutdown(reason: .clientRequested)
    }

    private func bootstrap(
        _ connection: CodexConnection,
        options: CodexClientOptions
    ) async throws {
        codexClientLogger.debug("bootstrap starting")
        emit(.connectionStateChanged(.connecting))

        let connectionInfo: (url: URL, authToken: String?)
        switch connection {
#if os(macOS)
        case .localManaged(let localOptions):
            let process = try await LocalCodexAppServerProcess.launch(
                options: localOptions,
                versionPolicy: options.versionPolicy
            )
            self.localProcess = process
            connectionInfo = (process.websocketURL, nil)
            startProcessLogForwarding(process)
#endif
        case .remote(let remoteOptions):
            try validate(remoteOptions: remoteOptions, policy: options.versionPolicy)
            connectionInfo = (remoteOptions.url, remoteOptions.authToken)
        }

        codexClientLogger.debug("opening websocket \(connectionInfo.url)")
        try await openWebSocket(url: connectionInfo.url, authToken: connectionInfo.authToken)
        emit(.connectionStateChanged(.connected))

        let capabilities = InitializeCapabilities(
            experimentalApi: options.experimentalAPI,
            optOutNotificationMethods: nil
        )

        let response = try await call(
            RPC.Initialize.self,
            params: InitializeParams(
                capabilities: capabilities,
                clientInfo: options.clientInfo
            )
        )
        try validate(serverInfo: response, policy: options.versionPolicy)
        self.serverInfo = response
        try await sendInitializedNotification()
        codexClientLogger.debug("initialized; serverInfo.userAgent=\(response.userAgent, privacy: .public)")
        emit(.connectionStateChanged(.initialized))
    }

#if os(macOS)
    private func startProcessLogForwarding(_ process: LocalCodexAppServerProcess) {
        Task { [weak self] in
            let lines = await process.stderrLines()
            for await line in lines {
                await self?.emit(.processLog(line: line))
            }
        }
    }
#endif

    private func validate(remoteOptions: RemoteServerOptions, policy: VersionPolicy) throws {
        if let authToken = remoteOptions.authToken, !authToken.isEmpty,
           !supportsBearerToken(url: remoteOptions.url),
           !remoteOptions.allowInsecureBearer {
            throw CodexClientError.unsupportedBearerTransport(remoteOptions.url)
        }
        if policy == .exact {
            guard let remoteVersion = remoteOptions.codexVersion else {
                throw CodexClientError.missingRemoteVersion
            }
            try CodexVersionChecker.validate(
                actual: remoteVersion,
                expected: CodexBindingMetadata.codexVersion,
                policy: policy
            )
        }
    }

    private func validate(serverInfo: InitializeResponse, policy: VersionPolicy) throws {
        guard policy == .exact else { return }
        guard let actualVersion = CodexVersionChecker.parseVersion(from: serverInfo.userAgent) else {
            throw CodexClientError.invalidResponse(
                "unable to parse codex version from initialize.userAgent: \(serverInfo.userAgent)"
            )
        }
        try CodexVersionChecker.validate(
            actual: actualVersion,
            expected: CodexBindingMetadata.codexVersion,
            policy: policy
        )
    }

    private func openWebSocket(url: URL, authToken: String?) async throws {
        let delegate = WebSocketOpenDelegate()
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        var request = URLRequest(url: url)
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024

        self.delegate = delegate
        self.session = session
        self.webSocketTask = task

        task.resume()
        do {
            try await delegate.waitUntilOpen()
        } catch {
            session.invalidateAndCancel()
            self.delegate = nil
            self.session = nil
            self.webSocketTask = nil
            throw mapOpenFailure(error, url: url)
        }

        connected = true
        listenTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func request<Params: Encodable>(method: String, params: Params) async throws -> Data {
        guard let task = webSocketTask, connected else {
            throw CodexClientError.notConnected
        }
        try Task.checkCancellation()

        let requestID = nextRequestID
        nextRequestID += 1

        let envelope = JSONRPCRequest(id: requestID, method: method, params: params)
        let data = try encoder.encode(envelope)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingRequests[requestID] = continuation
                Task {
                    do {
                        try await send(text: data, via: task)
                    } catch {
                        if let pending = self.removePending(requestID) {
                            pending.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            Task { await self.cancelPending(requestID) }
        }
    }

    private func removePending(_ id: Int) -> CheckedContinuation<Data, Error>? {
        pendingRequests.removeValue(forKey: id)
    }

    private func cancelPending(_ id: Int) {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        }
    }

    private func sendInitializedNotification() async throws {
        try await sendEncodable(JSONRPCClientNotification<EmptyParams?>(method: "initialized", params: nil))
    }

    private func sendResponse<Result: Encodable>(id: RequestId, result: Result) async throws {
        try await sendEncodable(JSONRPCSuccessEnvelope(id: id, result: result))
    }

    private func sendEncodable(_ value: some Encodable) async throws {
        guard let task = webSocketTask, connected else {
            throw CodexClientError.notConnected
        }
        let data = try encoder.encode(value)
        try await send(text: data, via: task)
    }

    private func send(text data: Data, via task: URLSessionWebSocketTask) async throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CodexClientError.invalidResponse("failed to encode websocket frame as UTF-8")
        }
        try await task.send(.string(string))
    }

    private func receiveLoop() async {
        while connected, let task = webSocketTask {
            do {
                let message = try await task.receive()
                await handle(message: message)
            } catch {
                await shutdown(reason: classifyReceiveFailure(error))
                return
            }
        }
    }

    private func classifyReceiveFailure(_ error: Error) -> DisconnectReason {
        if let urlError = error as? URLError {
            return .networkError(urlError)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .networkError(URLError(URLError.Code(rawValue: nsError.code)))
        }
        return .other(error.localizedDescription)
    }

    private func mapOpenFailure(_ error: Error, url: URL) -> Error {
        if let codexError = error as? CodexClientError {
            return codexError
        }
        if let urlError = error as? URLError {
            if urlError.code == .timedOut {
                return CodexClientError.connectTimeout(url)
            }
            return CodexClientError.connectionClosed(.networkError(urlError))
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let urlError = URLError(URLError.Code(rawValue: nsError.code))
            if urlError.code == .timedOut {
                return CodexClientError.connectTimeout(url)
            }
            return CodexClientError.connectionClosed(.networkError(urlError))
        }
        return CodexClientError.connectionClosed(.other(error.localizedDescription))
    }

    private func handle(message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let payload):
            data = payload
        @unknown default:
            return
        }

        switch routeIncomingData(data, decoder: decoder) {
        case .response(let id, let responseData, let error):
            handleResponse(id: id, data: responseData, error: error)
        case .event(let event):
            emit(event)
        case .ignored:
            return
        }
    }

    private func handleResponse(id: Int, data: Data, error: IncomingError?) {
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        if let error {
            continuation.resume(throwing: promote(error))
            return
        }
        continuation.resume(returning: data)
    }

    private func promote(_ error: IncomingError) -> CodexClientError {
        let lower = error.message.lowercased()
        let threadNotFoundPatterns = [
            "thread not found",
            "thread does not exist",
            "unknown thread",
            "no such thread",
        ]
        if threadNotFoundPatterns.contains(where: { lower.contains($0) }) {
            return .threadNotFound(error.message)
        }
        return .rpcError(code: error.code, message: error.message)
    }

    private func shutdown(reason: DisconnectReason) async {
#if os(macOS)
        guard connected || session != nil || localProcess != nil else { return }
#else
        guard connected || session != nil else { return }
#endif

        connected = false

        let listenTask = self.listenTask
        self.listenTask = nil
        listenTask?.cancel()

        let pendingRequests = self.pendingRequests
        self.pendingRequests.removeAll()
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: CodexClientError.connectionClosed(reason))
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()

        webSocketTask = nil
        session = nil
        delegate = nil

#if os(macOS)
        if let localProcess {
            self.localProcess = nil
            await localProcess.stop()
        }
#endif

        emit(.connectionStateChanged(.disconnected(reason)))
        streamIsFinished = true
        for (_, continuation) in subscribers {
            continuation.finish()
        }
        subscribers.removeAll()
        subscriberDropCounts.removeAll()
    }

    private func emit(_ event: CodexEvent) {
        if case .connectionStateChanged(let state) = event {
            currentConnectionState = state
        }
        for (id, continuation) in subscribers {
            let pendingLag = subscriberDropCounts[id, default: 0]
            if pendingLag > 0 {
                let laggedResult = continuation.yield(.lagged(skipped: pendingLag))
                switch laggedResult {
                case .enqueued:
                    subscriberDropCounts[id] = 0
                case .dropped:
                    subscriberDropCounts[id] = pendingLag
                case .terminated:
                    continue
                @unknown default:
                    break
                }
            }
            switch continuation.yield(event) {
            case .enqueued:
                break
            case .dropped:
                subscriberDropCounts[id, default: 0] += 1
            case .terminated:
                break
            @unknown default:
                break
            }
        }
    }
}

private struct IncomingEnvelope: Decodable {
    let id: IncomingRequestID?
    let method: String?
    let error: IncomingError?
}

struct IncomingError: Decodable, Sendable {
    let code: Int
    let message: String
}

private enum IncomingRequestID: Decodable {
    case integer(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
            return
        }
        self = .string(try container.decode(String.self))
    }

    var integerValue: Int? {
        if case .integer(let value) = self {
            return value
        }
        return nil
    }
}

enum IncomingMessageDisposition: Sendable {
    case response(id: Int, data: Data, error: IncomingError?)
    case event(CodexEvent)
    case ignored
}

func routeIncomingData(_ data: Data, decoder: JSONDecoder) -> IncomingMessageDisposition {
    let envelope: IncomingEnvelope
    do {
        envelope = try decoder.decode(IncomingEnvelope.self, from: data)
    } catch {
        return .event(.invalidMessage(rawJSON: data, errorDescription: error.localizedDescription))
    }

    if let integerID = envelope.id?.integerValue, envelope.method == nil {
        return .response(id: integerID, data: data, error: envelope.error)
    }

    if let method = envelope.method, envelope.id == nil {
        if let event = try? ServerNotificationEvent(from: data, decoder: decoder) {
            return .event(.notification(event))
        }
        return .event(.unknownMessage(method: method, rawJSON: data))
    }

    if envelope.id != nil, let method = envelope.method {
        if let request = try? AnyTypedServerRequest(from: data, decoder: decoder) {
            return .event(.serverRequest(request))
        }
        return .event(.unknownMessage(method: method, rawJSON: data))
    }

    return .event(
        .invalidMessage(
            rawJSON: data,
            errorDescription: "unrecognized JSON-RPC message shape"
        )
    )
}

struct JSONRPCRequest<Params: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Params
}

struct JSONRPCClientNotification<Params: Encodable>: Encodable {
    let method: String
    let params: Params

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        if let params = params as? OptionalEncodable, params.isNil {
            return
        }
        try container.encode(params, forKey: .params)
    }

    private enum CodingKeys: String, CodingKey { case method, params }
}

private protocol OptionalEncodable {
    var isNil: Bool { get }
}

extension Optional: OptionalEncodable {
    var isNil: Bool {
        if case .none = self { return true }
        return false
    }
}

struct JSONRPCSuccessEnvelope<Result: Encodable>: Encodable {
    let id: RequestId
    let result: Result
}

struct JSONRPCOutgoingErrorResponse: Encodable {
    let id: RequestId
    let error: JSONRPCErrorPayload
}

struct JSONRPCErrorPayload: Encodable {
    let code: Int
    let message: String
}

struct JSONRPCSuccessResponse<Result: Decodable>: Decodable {
    let result: Result

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.result),
           try container.decodeNil(forKey: .result) == false {
            self.result = try container.decode(Result.self, forKey: .result)
        } else if let empty = EmptyResponse() as? Result {
            self.result = empty
        } else {
            self.result = try container.decode(Result.self, forKey: .result)
        }
    }

    private enum CodingKeys: String, CodingKey { case result }
}

private final class WebSocketOpenDelegate: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let state = WebSocketOpenState()

    func waitUntilOpen() async throws {
        try await state.waitUntilOpen()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task {
            await state.open()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task {
            await state.fail(with: error)
        }
    }
}

private actor WebSocketOpenState {
    private enum State {
        case pending([CheckedContinuation<Void, Error>])
        case open
        case failed(Error)
    }

    private var state: State = .pending([])

    func waitUntilOpen() async throws {
        switch state {
        case .open:
            return
        case .failed(let error):
            throw error
        case .pending(var continuations):
            try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
                state = .pending(continuations)
            }
        }
    }

    func open() {
        guard case .pending(let continuations) = state else { return }
        state = .open
        for continuation in continuations {
            continuation.resume()
        }
    }

    func fail(with error: Error) {
        guard case .pending(let continuations) = state else { return }
        state = .failed(error)
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}

private func supportsBearerToken(url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
        return false
    }
    if scheme == "wss" {
        return true
    }
    guard scheme == "ws" else { return false }
    if host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" {
        return true
    }
    return false
}
