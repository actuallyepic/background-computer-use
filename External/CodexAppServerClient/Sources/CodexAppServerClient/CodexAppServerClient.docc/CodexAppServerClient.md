# ``CodexAppServerClient``

A Swift client for the codex app-server JSON-RPC protocol.

## Overview

`CodexAppServerClient` speaks the codex app-server wire protocol over WebSocket. It launches a
local codex subprocess (macOS) or connects to a remote codex instance, performs the `initialize`
handshake, and exposes strongly-typed APIs for requests, responses, notifications, and
server-initiated requests.

The Swift package version is pinned 1:1 with a codex release; each codex bump yields a new
tag. See `.codex-version` in the repo root.

The protocol surface (every `RPC.*`, `ServerNotifications.*`, `ServerRequests.*`, params,
response, and approval type) lives in the companion `CodexAppServerProtocol` module, which
is re-exported automatically via `@_exported import` — `import CodexAppServerClient` is all
you need.

## Topics

### Essentials

- <doc:GettingStarted>
- ``CodexClient``
- ``CodexClientOptions``

### Connecting

- ``CodexConnection``
- ``LocalServerOptions``
- ``RemoteServerOptions``
- ``VersionPolicy``

### Guides

- <doc:StreamingATurn>
- <doc:CancellingATurn>
- <doc:HandlingApprovals>
- <doc:RoutingMultipleThreads>
- <doc:ResumingAThread>
- <doc:ErrorHandlingAndReconnect>
- <doc:DebuggingWithProcessLog>
- <doc:HandlingServerRequests>

### Per-thread routing

- <doc:RoutingMultipleThreads>
- ``CodexClient/events(forThread:bufferSize:)``
- ``CodexClient/notifications(of:forThread:bufferSize:)``

### Convenience streams

- ``CodexClient/streamTurn(input:threadId:)``
- ``TurnStream``
- ``CodexClient/connectionStates(bufferSize:)``
- ``CodexClient/currentConnectionState``
- ``CodexClient/serverRequests(of:bufferSize:)``
- ``CodexClient/processLogs(bufferSize:)``
- ``CodexClient/droppedEventCounts()``
- ``CodexClient/respond(to:intent:)``

### Events & Errors

- ``CodexEvent``
- ``ConnectionState``
- ``DisconnectReason``
- ``CodexClientError``

### Protocol Surface

The full generated protocol — every RPC method, notification, server request,
and approval type — lives in `CodexAppServerProtocol` and is re-exported here.
Browse them in that module's documentation, or enumerate at runtime via
`RPC.allMethods`, `ServerNotifications.all`, and `ServerRequests.all`.
