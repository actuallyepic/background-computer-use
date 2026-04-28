# Debugging with processLog

Read the codex process's stderr in real time via `.processLog(line:)` events.

## Overview

When you connect with `CodexConnection.localManaged`, the client captures the stderr output of the spawned codex process and forwards each line as a ``CodexEvent/processLog(line:)`` event. This is the raw diagnostic stream codex writes when something goes wrong — approval policy decisions, tool execution errors, JSON-RPC warnings, and version negotiation messages all appear here.

`.processLog` is macOS-only and only fires for `.localManaged` connections. Remote connections do not produce this event.

> Important: codex emits 4–5 banner lines on startup and then nothing else unless
> `RUST_LOG` is set in the child process environment. With `RUST_LOG` unset, only
> `ERROR`-level events surface; the process appears silent during normal operation.
> Set `RUST_LOG=info` (or `RUST_LOG=debug`) via ``LocalServerOptions/environment``
> to get meaningful runtime tracing — websocket dispatch, JSON-RPC routing, thread
> lifecycle, tool execution. Optionally pair with `LOG_FORMAT=json` for
> machine-parseable lines.
>
> ```swift
> CodexConnection.localManaged(LocalServerOptions(
>     environment: ["RUST_LOG": "info"]
> ))
> ```
>
> The startup banner is delivered to every subscriber via a small replay buffer, so
> calling ``CodexClient/processLogs(bufferSize:)`` after `connect` still surfaces
> the banner lines.
>
> With `RUST_LOG` set, lines arrive with ANSI color escapes (e.g. `\u{001B}[32m INFO\u{001B}[0m`).
> Use ``Swift/String/strippingAnsiEscapes`` to remove them at render time:
>
> ```swift
> for await line in await client.processLogs() {
>     logModel.append(line.strippingAnsiEscapes)
> }
> ```

## Basic pattern

```swift
for await event in await client.events() {
    if case .processLog(let line) = event {
        print("[codex stderr]", line)
    }
}
```

That's it for development. Add a `#if DEBUG` guard if you don't want it in production builds.

## Dev drawer pattern

A common UI pattern is a collapsible "Process Log" drawer that accumulates lines:

```swift
@MainActor
class ProcessLogModel: ObservableObject {
    @Published var lines: [String] = []
    private let maxLines = 500

    func append(_ line: String) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}

// In your event loop:
case .processLog(let line):
    await logModel.append(line)
```

Cap the buffer — codex can be verbose during long turns.

## What you'll see

Typical content:

- Startup messages confirming which model and sandbox policy are active.
- Per-tool-call tracing when the agent runs shell commands or applies patches.
- Rate-limit and auth errors when the API key is missing or exhausted.
- Crash backtraces when the process exits unexpectedly — these are most useful when paired with `DisconnectReason.processExited` (see ``ErrorHandlingAndReconnect``).

## Separating process log from other events

If you already have a single event loop handling deltas, approvals, and disconnects, add the `processLog` case without restructuring:

```swift
for await event in await client.events() {
    switch event {
    case .processLog(let line):
        logModel.append(line)
    case .notification(.itemAgentMessageDelta(let d)):
        // ...
    case .connectionStateChanged(.disconnected(let reason)):
        // ...
    default:
        break
    }
}
```

Alternatively, open a *second* subscription from the same client — ``CodexClient/events(bufferSize:)`` is multicast:

```swift
Task {
    for await event in await client.events() {
        if case .processLog(let line) = event {
            logModel.append(line)
        }
    }
}
```

Each call to `events()` returns an independent `AsyncStream`. Both consumers receive every event; the process log consumer will not interfere with your main loop's buffer.

## Shorthand: `processLogs()`

If all you want is the stderr stream with no other event handling, skip the `events()`
switch entirely and use the typed accessor ``CodexClient/processLogs(bufferSize:)``:

```swift
Task {
    for await line in await client.processLogs() {
        logModel.append(line)
    }
}
```

Same multicast guarantees, same macOS/`.localManaged`-only constraint, less boilerplate.

## Gotcha: `.processLog` lines arrive asynchronously

Lines are forwarded as they are read from the pipe — they may arrive slightly after the event that triggered them (e.g. a tool-call result notification). Don't rely on log line ordering relative to notifications for anything load-bearing; treat them as diagnostic context only.
