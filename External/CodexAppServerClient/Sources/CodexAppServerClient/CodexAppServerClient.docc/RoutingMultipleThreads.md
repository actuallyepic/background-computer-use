# Managing Multiple Threads

One `CodexClient` instance hosts many concurrent threads; use the `threadId` carried on every notification to route events to the right state object.

## Overview

A single ``CodexClient`` can run many threads simultaneously. There is no per-thread stream — all events arrive through the same ``CodexClient/events(bufferSize:)`` multicast. Every notification struct carries a `threadId` field you can use to demultiplex events to per-thread state.

> Important: ``CodexClient/events(bufferSize:)`` does not buffer events emitted before
> subscription. For RPCs whose follow-up notifications come from a *different* server
> task than the response (notably `RPC.TurnStart`, whose `AgentMessageDelta`
> notifications are emitted concurrently with the response), you must call
> `events()` / ``CodexClient/events(forThread:bufferSize:)`` *before* invoking the
> trigger RPC. ``CodexClient/streamTurn(input:threadId:)`` already does this for
> turns; reach for it instead of rolling your own when you can.

## Starting multiple threads

```swift
let threadA = try await client.call(
    RPC.ThreadStart.self,
    params: ThreadStartParams(ephemeral: true)
)
let threadB = try await client.call(
    RPC.ThreadStart.self,
    params: ThreadStartParams(ephemeral: true)
)
```

Each call returns a `ThreadStartResponse` with a `thread.id` string. Hold onto those IDs.

## A simple thread state router

```swift
actor ThreadRouter {
    struct ThreadState {
        var output: String = ""
        var isComplete: Bool = false
    }

    private var threads: [String: ThreadState] = [:]

    func register(threadId: String) {
        threads[threadId] = ThreadState()
    }

    func handleDelta(_ delta: AgentMessageDeltaNotification) {
        threads[delta.threadId]?.output += delta.delta
    }

    func handleCompletion(_ note: TurnCompletedNotification) {
        threads[note.threadId]?.isComplete = true
    }
}

let router = ThreadRouter()
await router.register(threadId: threadA.thread.id)
await router.register(threadId: threadB.thread.id)

for await event in await client.events() {
    switch event {
    case .notification(.itemAgentMessageDelta(let d)):
        await router.handleDelta(d)
    case .notification(.turnCompleted(let c)):
        await router.handleCompletion(c)
    case .connectionStateChanged(.disconnected(let reason)):
        print("disconnected:", reason)
        break
    default:
        break
    }
}
```

## Which notifications carry `threadId`

Most turn-scoped notifications carry both `threadId` and `turnId`:

- `ServerNotifications.ItemAgentMessageDelta` — `delta.threadId`, `delta.turnId`
- `ServerNotifications.TurnStarted` — `notification.threadId`, `notification.turn.id`
- `ServerNotifications.TurnCompleted` — `notification.threadId`, `notification.turn.id`
- `ServerNotifications.ItemStarted`, `ServerNotifications.ItemCompleted` — `notification.threadId`

Filter by `threadId` first, then by `turnId` if you need turn-level granularity.

## Server requests are also thread-scoped

Approval requests arrive with a `threadId` in their params. Route them the same way:

```swift
case .serverRequest(let request):
    switch request {
    case .applyPatchApproval(let r):
        let threadId = r.params.threadId
        // look up which thread this belongs to and surface the right UI
    default:
        try await client.reject(request, code: -32601, message: "not implemented")
    }
```

## Closing a thread

Threads do not have an explicit close RPC. When you're done with a thread, simply stop handling its events. For non-ephemeral threads, the server persists the history to disk automatically. Call ``CodexClient/disconnect()`` only when you want to tear down the entire client.
