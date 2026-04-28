# Error Handling & Reconnect

Catch `CodexClientError` for RPC failures, observe `connectionStateChanged(.disconnected)` for transport failures, and implement reconnect yourself — the library does not auto-reconnect.

## Overview

Errors surface through two distinct paths:

1. **RPC errors** — thrown by ``CodexClient/call(_:params:)`` when a request fails or the connection drops mid-flight.
2. **Transport errors** — emitted as ``CodexEvent/connectionStateChanged(_:)`` carrying ``ConnectionState/disconnected(_:)`` on the event stream.

## The `CodexClientError` taxonomy

| Case | When it fires |
|---|---|
| `rpcError(code:message:)` | Server returned a JSON-RPC error for a specific request |
| `connectionClosed(DisconnectReason)` | The connection dropped while a request was in-flight |
| `threadNotFound(String)` | Server said the thread does not exist (also detectable via `error.isThreadNotFound`) |
| `notConnected` | `call` was invoked before `connect` completed |
| `versionMismatch(expected:actual:)` | Server version doesn't match `VersionPolicy.exact` |
| `handshakeFailed` (via `DisconnectReason`) | `initialize` exchange failed |

Catch at the granularity you care about:

```swift
do {
    let turn = try await client.call(
        RPC.TurnStart.self,
        params: TurnStartParams(input: input, threadId: threadId)
    )
} catch let error as CodexClientError {
    switch error {
    case .rpcError(let code, let message):
        print("Server error \(code): \(message)")
    case .connectionClosed(let reason):
        print("Connection closed: \(reason)")
    case .threadNotFound(let message):
        print("Thread gone: \(message)")
    default:
        print("Other error: \(error.localizedDescription)")
    }
} catch is CancellationError {
    // The calling Task was cancelled — not an error, just cleanup.
}
```

## Observing disconnects on the event stream

A disconnect always arrives as `.connectionStateChanged(.disconnected(reason))`. There is no separate `.disconnected` event case. Watch for it alongside regular events:

```swift
for await event in await client.events() {
    switch event {
    case .connectionStateChanged(.disconnected(let reason)):
        handleDisconnect(reason)
        return  // stream is finished after disconnect
    case .connectionStateChanged(let state):
        print("Connection state:", state)
    default:
        break
    }
}
```

After emitting this event, the stream finishes — `for await` exits naturally.

## `DisconnectReason` for differentiated UI

``DisconnectReason`` carries enough information to show a useful error rather than a generic "disconnected" banner:

```swift
func handleDisconnect(_ reason: DisconnectReason) {
    switch reason {
    case .clientRequested:
        break  // intentional, no error UI needed
    case .webSocketClosed(let code, let message):
        showAlert("Connection closed by server (code \(code?.rawValue ?? -1)): \(message)")
    case .networkError(let urlError):
        showAlert("Network error: \(urlError.localizedDescription)")
    case .processExited(let status, let description):
        showAlert("codex process exited (status \(status ?? -1)): \(description)")
    case .handshakeFailed(let message):
        showAlert("Handshake failed — check codex version: \(message)")
    case .other(let message):
        showAlert("Disconnected: \(message)")
    }
}
```

## Manual reconnect

The library deliberately omits automatic reconnect. This avoids surprising state — a reconnected session starts a fresh ``CodexClient``, and any in-flight operations on the old one are gone. Reconnect by creating a new client:

```swift
func reconnect() async {
    do {
        self.client = try await CodexClient.connect(
            .localManaged(),
            options: CodexClientOptions(clientInfo: clientInfo)
        )
        // Re-subscribe, re-start event loop, etc.
    } catch {
        print("Reconnect failed:", error.localizedDescription)
        // Back off and retry, or surface the error.
    }
}
```

For transient network errors a simple exponential backoff is sufficient. For `processExited` or `handshakeFailed`, inspect the reason before retrying — retrying a version mismatch immediately will fail again.

## `connectionClosed` vs stream ending

If a request is in-flight when the connection drops, ``CodexClient/call(_:params:)`` throws `CodexClientError.connectionClosed(reason)`. The corresponding ``DisconnectReason`` is the same value that appears in the event stream's `.connectionStateChanged(.disconnected(reason))`. You get the reason from whichever path you observe first.
