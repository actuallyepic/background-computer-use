# Handling Server Requests

Respond to prompts the codex server sends to your client.

## Overview

codex occasionally requests information or approval from the client — e.g. confirming a patch
application, approving a shell command, or eliciting input. These arrive as
``CodexEvent/serverRequest(_:)`` events.

Each server request carries a `RequestId` that must be echoed back in the response. Use
``CodexClient/respond(to:result:)`` for a typed success response or
``CodexClient/reject(_:code:message:)`` to decline.

## Example: approving a patch

```swift
for await event in await client.events() {
    guard case .serverRequest(let request) = event else { continue }
    switch request {
    case .applyPatchApproval(let typed):
        let decision = /* ask the user */
        try await client.respond(to: typed, result: ApplyPatchApprovalResponse(decision: decision))
    default:
        try await client.reject(request, message: "unsupported server request")
    }
}
```

## Ignoring unsupported requests

If your app does not implement a particular surface, rejecting with `-32601` ("method not
found") is the polite JSON-RPC response; the server will proceed without waiting.

```swift
try await client.reject(request, code: -32601, message: "not implemented")
```
