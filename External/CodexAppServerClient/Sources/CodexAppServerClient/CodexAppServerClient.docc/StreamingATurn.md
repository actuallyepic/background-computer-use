# Streaming an Agent Turn

Subscribe to token-level deltas before starting the turn, then drain the stream until the turn completes.

## Overview

The server emits `ServerNotifications.ItemAgentMessageDelta` notifications as the agent writes each text fragment. Because ``CodexClient/events(bufferSize:)`` only delivers events that arrive *after* subscription, you must subscribe before calling `RPC.TurnStart`. Events emitted before your subscription are gone — the stream has no history buffer.

## Subscribe first, then start the turn

```swift
import CodexAppServerClient

let thread = try await client.call(
    RPC.ThreadStart.self,
    params: ThreadStartParams(ephemeral: true)
)

// Subscribe before TurnStart so no delta arrives before the stream is open.
let deltas = await client.notifications(of: ServerNotifications.ItemAgentMessageDelta.self)

let turn = try await client.call(
    RPC.TurnStart.self,
    params: TurnStartParams(
        input: [UserInput(text: "Explain recursion in two sentences.", textElements: nil,
                          type: .text, url: nil, path: nil, name: nil)],
        threadId: thread.thread.id
    )
)

var output = ""
for await delta in deltas {
    guard delta.turnId == turn.turn.id else { continue }
    output += delta.delta
    // update your UI here
    if delta.turnId != turn.turn.id { continue }
}
```

The `delta.delta` property is the raw text fragment. `delta.threadId` and `delta.turnId` let you ignore notifications from other concurrent turns on the same client.

## Detecting turn completion

`ServerNotifications.TurnCompleted` fires once when the agent finishes or is interrupted. Use it as the loop-exit signal rather than relying on the delta stream going quiet (the server may emit other notifications after the last delta):

```swift
let events = await client.events()

var buffer = ""
eventLoop: for await event in events {
    switch event {
    case .notification(.itemAgentMessageDelta(let d)) where d.turnId == turn.turn.id:
        buffer += d.delta
    case .notification(.turnCompleted(let c)) where c.turn.id == turn.turn.id:
        print("Turn finished. Full output:\n\(buffer)")
        break eventLoop
    case .connectionStateChanged(.disconnected(let reason)):
        throw CodexClientError.connectionClosed(reason)
    default:
        break
    }
}
```

## Gotcha: stream ordering

`RPC.TurnStart` returns only after the server has acknowledged the turn — but the server may emit the very first delta *before* the response reaches your Swift task if the network reorders frames. Subscribing before `RPC.TurnStart` closes that window.

## Using `notifications(of:)` vs `events()`

``CodexClient/notifications(of:bufferSize:)`` is a convenience filter — internally it calls ``CodexClient/events(bufferSize:)`` and discards non-matching events. Use it when you only care about one notification type. Use ``CodexClient/events(bufferSize:)`` when you need to interleave delta handling with approval responses or disconnection handling.
