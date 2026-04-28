# ``CodexAppServerProtocol``

Generated Swift bindings for the codex app-server JSON-RPC protocol.

## Overview

`CodexAppServerProtocol` contains every RPC method, server notification, and
server request type emitted by `codex app-server generate-json-schema --experimental`
and `codex app-server generate-ts --experimental` for the pinned codex version.

Most consumers should `import CodexAppServerClient`, which re-exports this
module via `@_exported`. Use this module directly only if you need the
protocol types without the WebSocket client.

Browse the full surface via ``RPC/allMethods``, ``ServerNotifications/all``,
and ``ServerRequests/all`` — each is an array of every typed method this
binding exposes.

## Topics

### Catalog Articles

- <doc:RPCMethodsCatalog>
- <doc:ServerNotificationsCatalog>
- <doc:ServerRequestsCatalog>

### Method Namespaces

- ``RPC``
- ``ServerNotifications``
- ``ServerRequests``

### Method Identifiers

- ``ClientRequestMethod``
- ``NotificationMethod``
- ``ServerRequestMethod``

### Method Protocols

- ``CodexRPCMethod``
- ``CodexServerNotificationMethod``
- ``CodexServerRequestMethod``

### Event Envelopes

- ``ServerNotificationEvent``
- ``AnyTypedServerRequest``
- ``TypedServerRequest``

### Approvals

- ``ApprovalIntent``
- ``ApprovalResponse``
- ``AnyApprovalRequest``

### Empty Payloads

- ``EmptyParams``
- ``EmptyResponse``

### Build Metadata

- ``CodexBindingMetadata``
