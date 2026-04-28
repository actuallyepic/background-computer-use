# Cancelling a Turn

Cancel the Swift task to stop waiting for results, and call `RPC.TurnInterrupt` to stop the server agent.

## Overview

There are two separate concerns when the user hits Stop:

1. **Client side** — your Swift task stops waiting and resources are freed.
2. **Server side** — the agent actually stops generating and executing tools.

`Task.cancel()` handles (1) only. It cancels the pending ``CodexClient/call(_:params:)`` continuation, which throws `CancellationError` back to your code. The server is still running. To stop the agent, you must send `RPC.TurnInterrupt`.

## Basic pattern

```swift
let turn = try await client.call(
    RPC.TurnStart.self,
    params: TurnStartParams(input: input, threadId: threadId)
)
let turnId = turn.turn.id

// ... later, when the user taps Stop:
try await client.call(
    RPC.TurnInterrupt.self,
    params: TurnInterruptParams(threadId: threadId, turnId: turnId)
)
```

`TurnInterruptParams` requires both `threadId` and `turnId`. The server sends `ServerNotifications.TurnCompleted` after honouring the interrupt.

## The pre-turnId race window

`RPC.TurnStart` returns a `turnId` only after the server responds. If the user cancels *before* `TurnStart` returns — before you have a `turnId` — you cannot send `TurnInterrupt` yet. The safest approach is to record a pending-cancel flag and check it after `TurnStart` resolves:

```swift
actor TurnController {
    private var pendingInterrupt = false
    private var activeTurnId: String?
    private var activeThreadId: String?

    func startTurn(client: CodexClient, input: [UserInput], threadId: String) async throws {
        activeThreadId = threadId
        let turn = try await client.call(
            RPC.TurnStart.self,
            params: TurnStartParams(input: input, threadId: threadId)
        )
        activeTurnId = turn.turn.id

        if pendingInterrupt {
            pendingInterrupt = false
            try await sendInterrupt(client: client)
        }
    }

    func requestCancel(client: CodexClient) async throws {
        if activeTurnId != nil {
            try await sendInterrupt(client: client)
        } else {
            pendingInterrupt = true
        }
    }

    private func sendInterrupt(client: CodexClient) async throws {
        guard let threadId = activeThreadId, let turnId = activeTurnId else { return }
        try await client.call(
            RPC.TurnInterrupt.self,
            params: TurnInterruptParams(threadId: threadId, turnId: turnId)
        )
    }
}
```

## Also cancel the waiting task

If your code is blocked in a `for await event in events` loop waiting for `ServerNotifications.TurnCompleted`, cancel the enclosing task or break out of the loop when `TurnCompleted` arrives — the server sends one after it processes the interrupt.

## What `Task.cancel()` alone does

Cancelling the Swift task that called `RPC.TurnStart` throws `CancellationError` at the `await` site. Any pending JSON-RPC continuation is freed. But the server-side turn continues until it finishes naturally or a `turn/interrupt` arrives. If you only call `Task.cancel()` without following up with `RPC.TurnInterrupt`, tool calls and file modifications keep running on the server.
