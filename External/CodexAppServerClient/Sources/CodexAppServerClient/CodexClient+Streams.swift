import Foundation
import CodexAppServerProtocol

// MARK: - Per-thread filtered streams

extension CodexClient {
    /// Subscribe to events scoped to a single `threadId`.
    ///
    /// Filters the multicast stream to only events whose payload carries a matching
    /// `threadId` (extracted reflectively from the notification or server-request params).
    /// System events (``CodexEvent/connectionStateChanged(_:)``,
    /// ``CodexEvent/lagged(skipped:)``, ``CodexEvent/processLog(line:)``,
    /// ``CodexEvent/invalidMessage(rawJSON:errorDescription:)``,
    /// ``CodexEvent/unknownMessage(method:rawJSON:)``) are not thread-scoped and pass
    /// through to every per-thread subscriber so per-thread UIs can still observe lifecycle
    /// changes.
    ///
    /// Pair with `RPC.ThreadStart` (or `RPC.ThreadResume`) to drive a single thread's
    /// view without having to maintain a `[threadId: ThreadState]` router yourself.
    ///
    /// ```swift
    /// let thread = try await client.call(RPC.ThreadStart.self, params: ThreadStartParams(ephemeral: true))
    /// for await event in await client.events(forThread: thread.thread.id) {
    ///     // only events for this thread (plus system lifecycle events)
    /// }
    /// ```
    ///
    /// > Important: Subscribe *before* invoking RPCs whose notifications come from a
    /// > separate server task — most importantly `RPC.TurnStart`, whose deltas race
    /// > the response. `RPC.ThreadStart`'s `ThreadStarted` notification is in-task
    /// > and safe to subscribe-after, but for turns prefer
    /// > ``streamTurn(input:threadId:)`` or order your subscribe before the turn
    /// > trigger.
    public func events(
        forThread threadId: String,
        bufferSize: Int = 1024
    ) -> AsyncStream<CodexEvent> {
        let base = events(bufferSize: bufferSize)
        return AsyncStream { continuation in
            let task = Task {
                for await event in base {
                    if Task.isCancelled { break }
                    if eventBelongs(event, toThread: threadId) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Typed notification stream filtered to a single thread.
    ///
    /// Combines ``CodexClient/notifications(of:bufferSize:)`` with the same threadId-extraction
    /// trick used by ``events(forThread:bufferSize:)``. Notifications whose params struct
    /// doesn't carry a matching `threadId` field are dropped.
    public func notifications<Method: CodexServerNotificationMethod>(
        of method: Method.Type,
        forThread threadId: String,
        bufferSize: Int = 1024
    ) -> AsyncStream<Method.Params> where Method.Params: Sendable {
        let base = events(forThread: threadId, bufferSize: bufferSize)
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
}

// MARK: - Typed observability accessors

extension CodexClient {
    /// Stream of connection lifecycle transitions.
    ///
    /// Useful when you want to drive a "Connected / Reconnecting / Disconnected" UI badge
    /// without exhaustively switching on the full ``CodexEvent`` enum.
    ///
    /// If the client already has a ``currentConnectionState``, the stream yields it
    /// immediately on subscription so late-binding consumers don't need a separate
    /// one-shot read. Subsequent state transitions are delivered as they occur.
    public func connectionStates(
        bufferSize: Int = 16
    ) -> AsyncStream<ConnectionState> {
        let base = events(bufferingPolicy: .bufferingNewest(bufferSize))
        let snapshot = currentConnectionState
        return AsyncStream { continuation in
            if let snapshot {
                continuation.yield(snapshot)
            }
            let task = Task {
                for await event in base {
                    if Task.isCancelled { break }
                    if case .connectionStateChanged(let state) = event {
                        continuation.yield(state)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Stream of drop counts from ``CodexEvent/lagged(skipped:)`` markers.
    ///
    /// A consumer that only uses typed streams (``notifications(of:bufferSize:)``,
    /// ``serverRequests(of:bufferSize:)``) will otherwise have no way to observe buffer
    /// overflow, since `.lagged(skipped:)` is a `CodexEvent` case and does not surface
    /// through the typed filters. Subscribing here gives a pure "I just lost N events"
    /// signal suitable for a health-indicator UI or telemetry.
    ///
    /// The returned stream itself uses `.unbounded` buffering so the drop meter cannot
    /// itself drop samples.
    public func droppedEventCounts() -> AsyncStream<Int> {
        let base = events()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                for await event in base {
                    if Task.isCancelled { break }
                    if case .lagged(let skipped) = event {
                        continuation.yield(skipped)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Typed stream of one specific server-to-client request method.
    ///
    /// Mirrors ``CodexClient/notifications(of:bufferSize:)`` for the request side. Each yielded
    /// value is a fully-typed `TypedServerRequest` ready to be answered with
    /// ``respond(to:result:)`` or ``reject(_:code:message:)`` (using the convenience
    /// `ApprovalResponse.init(intent:)` for approval-shaped responses).
    ///
    /// ```swift
    /// for await request in await client.serverRequests(of: ServerRequests.ExecCommandApproval.self) {
    ///     try await client.respond(to: request, result: .init(intent: .allowOnce))
    /// }
    /// ```
    public func serverRequests<Method: CodexServerRequestMethod>(
        of method: Method.Type,
        bufferSize: Int = 1024
    ) -> AsyncStream<TypedServerRequest<Method>> {
        let base = events(bufferSize: bufferSize)
        return AsyncStream { continuation in
            let task = Task {
                for await event in base {
                    if Task.isCancelled { break }
                    if case .serverRequest(let request) = event,
                       let typed = request.typed(as: Method.self) {
                        continuation.yield(typed)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #if os(macOS)
    /// Stream of stderr lines from the locally-managed codex process.
    ///
    /// Available only for ``CodexConnection/localManaged(_:)``. Subscribes directly to
    /// the underlying stderr broadcaster so that subscribers attaching after `connect`
    /// still receive the startup banner lines (replayed from a small buffer). The
    /// `bufferSize` parameter is retained for source compatibility but no longer
    /// affects buffering — the broadcaster manages its own replay buffer.
    ///
    /// Returns an empty, immediately-finished stream for `.remote` connections.
    public func processLogs(
        bufferSize: Int = 256
    ) -> AsyncStream<String> {
        guard let process = localProcess else {
            return AsyncStream { continuation in continuation.finish() }
        }
        return AsyncStream { continuation in
            let task = Task {
                let lines = await process.stderrLines()
                for await line in lines {
                    if Task.isCancelled { break }
                    continuation.yield(line)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #endif
}

// MARK: - Approval dispatch

extension CodexClient {
    /// Answer any approval-shaped server request with a single canonical intent.
    ///
    /// Pattern-matches the `AnyApprovalRequest` case and dispatches the user's intent
    /// into the correct typed response via `ApprovalResponse.init(intent:)`. Callers
    /// get one line of approval UI dispatch instead of one branch per method.
    ///
    /// ```swift
    /// for await event in await client.events() {
    ///     if case .serverRequest(let request) = event,
    ///        let approval = request.asApprovalRequest {
    ///         try await client.respond(to: approval, intent: userChoice)
    ///     }
    /// }
    /// ```
    public func respond(to request: AnyApprovalRequest, intent: ApprovalIntent) async throws {
        switch request {
        case .applyPatchApproval(let typed):
            try await respond(to: typed, result: ApplyPatchApprovalResponse(intent: intent))
        case .execCommandApproval(let typed):
            try await respond(to: typed, result: ExecCommandApprovalResponse(intent: intent))
        case .itemCommandExecutionRequestApproval(let typed):
            try await respond(to: typed, result: CommandExecutionRequestApprovalResponse(intent: intent))
        case .itemFileChangeRequestApproval(let typed):
            try await respond(to: typed, result: FileChangeRequestApprovalResponse(intent: intent))
        }
    }
}

// MARK: - Turn streaming convenience

/// A handle to an in-flight turn and its streaming agent message deltas.
///
/// Returned by ``CodexClient/streamTurn(input:threadId:)``. Holds the captured
/// `turnId` so callers can call `RPC.TurnInterrupt` mid-stream, and exposes
/// `deltas` as the usual token-streaming `AsyncStream`.
///
/// The `deltas` stream finishes when:
/// - the matching `ServerNotifications.TurnCompleted` arrives (normal completion), or
/// - the connection drops (no error is thrown — this matches the library-wide
///   convention; observe `CodexClient.connectionStates()` or
///   `CodexClient.currentConnectionState` if you need to distinguish these cases), or
/// - the consuming task is cancelled.
public struct TurnStream: Sendable {
    /// Server-assigned identifier for this turn. Pass with `threadId` to
    /// `RPC.TurnInterrupt` if you need to stop generation before `TurnCompleted`.
    public let turnId: String
    /// Thread this turn is running on.
    public let threadId: String
    /// Stream of agent message deltas for this turn only. Finishes silently on
    /// connection loss — see the type-level docs.
    public let deltas: AsyncStream<AgentMessageDeltaNotification>
}

extension CodexClient {
    /// Start a turn and return a handle exposing its `turnId` plus a stream of its deltas.
    ///
    /// Wraps the four-step "subscribe before TurnStart, capture turnId, filter deltas by
    /// turnId, finish on TurnCompleted" recipe that every chat-style consumer reinvents.
    ///
    /// The events stream is opened *before* the `RPC.TurnStart` call so no deltas can
    /// arrive in the gap between the server starting the turn and the client knowing the
    /// `turnId`.
    ///
    /// The returned ``TurnStream/deltas`` stream finishes cleanly on `TurnCompleted`.
    /// If the connection drops mid-turn the stream also finishes silently — pair with
    /// ``connectionStates(bufferSize:)`` or ``currentConnectionState`` if you need to
    /// distinguish disconnect from normal completion.
    ///
    /// To stop a turn that is still streaming, call `RPC.TurnInterrupt` with
    /// ``TurnStream/threadId`` and ``TurnStream/turnId`` — `Task.cancel()` alone does
    /// not stop the server.
    ///
    /// ```swift
    /// let turn = try await client.streamTurn(input: [.text("hi")], threadId: thread.id)
    /// for await delta in turn.deltas {
    ///     bubble.text += delta.delta
    /// }
    /// ```
    ///
    /// - Throws: Any error ``call(_:params:)`` would throw from `RPC.TurnStart`.
    public func streamTurn(
        input: [UserInput],
        threadId: String
    ) async throws -> TurnStream {
        let baseEvents = events()
        let response = try await call(
            RPC.TurnStart.self,
            params: TurnStartParams(input: input, threadId: threadId)
        )
        let turnId = response.turn.id

        let deltas = AsyncStream<AgentMessageDeltaNotification> { continuation in
            let task = Task {
                for await event in baseEvents {
                    if Task.isCancelled { break }
                    guard case .notification(let notification) = event else { continue }
                    switch notification {
                    case .itemAgentMessageDelta(let delta) where delta.turnId == turnId:
                        continuation.yield(delta)
                    case .turnCompleted(let completed) where completed.turn.id == turnId:
                        continuation.finish()
                        return
                    default:
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        return TurnStream(turnId: turnId, threadId: threadId, deltas: deltas)
    }
}

// MARK: - Event routing helper

/// True if the event's payload references the given thread, or it's a system event that
/// should be visible to every per-thread subscriber.
///
/// Thread extraction rides on the generated ``ServerNotificationEvent/threadId`` and
/// ``AnyTypedServerRequest/threadId`` accessors — no runtime reflection.
private func eventBelongs(_ event: CodexEvent, toThread threadId: String) -> Bool {
    switch event {
    case .notification(let notification):
        return notification.threadId == threadId
    case .serverRequest(let request):
        return request.threadId == threadId
    case .connectionStateChanged, .lagged, .processLog, .invalidMessage, .unknownMessage:
        return true
    }
}
