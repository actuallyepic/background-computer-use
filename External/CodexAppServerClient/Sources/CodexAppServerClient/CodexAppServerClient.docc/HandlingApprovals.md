# Handling Approval Requests

Use `ApprovalIntent` and the unified `init(intent:)` to respond to any of the four approval request types with the same UI code.

## Overview

The codex agent pauses and asks your client for permission before applying patches, running commands, or changing files. These arrive as ``CodexEvent/serverRequest(_:)`` events carrying one of four `AnyTypedServerRequest` cases. Each case has its own wire response type, but they all conform to `ApprovalResponse`, which exposes `init(intent:)`. This means your approval UI only needs to produce an `ApprovalIntent` — the response type does the rest.

## Triggering approvals: choose the right sandbox

Approvals only fire when the agent is *not* allowed to perform the action unsandboxed. The sandbox controls *what* requires asking; `approvalPolicy` controls *whether* the agent may ask. Both live on `ThreadStartParams`:

| `ThreadStartParams.sandbox`  | What triggers approvals                                                  |
|------------------------------|--------------------------------------------------------------------------|
| `.readOnly`                  | Any file write, command execution, or network call. Most chatty.         |
| `.workspaceWrite`            | Commands that escape the workspace; writes outside the workspace.        |
| `.dangerFullAccess`          | Nothing — agent acts directly without prompting.                         |

For example, to surface file-write (`itemFileChangeRequestApproval`) requests, start the thread with `sandbox: .readOnly`:

```swift
let thread = try await client.call(
    RPC.ThreadStart.self,
    params: ThreadStartParams(
        approvalPolicy: .enumeration(.onRequest),
        sandbox: .readOnly
    )
)
```

There is no need to inject `-c sandbox_mode=...` via the CLI when the per-thread param works — but if you want to set a process-wide default for every thread, ``LocalServerOptions/extraConfig`` accepts `["sandbox_mode": "read-only"]`.

> Warning: Models on the *unified-exec* path (currently the gpt-5.x family by default)
> route tool execution through codex's headless exec orchestrator, which **rejects all
> approval server requests** before the app-server can forward them to your client.
> A Swift client on these models with `approvalPolicy: .onRequest` will observe zero
> approval events for any operation, regardless of `sandbox`. The
> `exec_permission_approvals` feature flag (`Stage::UnderDevelopment` upstream) is the
> intended fix but is not wired through yet. Track upstream codex for when this lands.

## The four approval cases

| `AnyTypedServerRequest` case | Response type |
|---|---|
| `.applyPatchApproval` | `ApplyPatchApprovalResponse` |
| `.execCommandApproval` | `ExecCommandApprovalResponse` |
| `.itemCommandExecutionRequestApproval` | `CommandExecutionRequestApprovalResponse` |
| `.itemFileChangeRequestApproval` | `FileChangeRequestApprovalResponse` |

## Handling all four with `ApprovalIntent`

```swift
for await event in await client.events() {
    guard case .serverRequest(let request) = event else { continue }

    // Ask the user — returns .allowOnce, .allowForSession, .deny, or .abort
    let intent: ApprovalIntent = await askUser(for: request)

    switch request {
    case .applyPatchApproval(let r):
        try await client.respond(to: r, result: ApplyPatchApprovalResponse(intent: intent))
    case .execCommandApproval(let r):
        try await client.respond(to: r, result: ExecCommandApprovalResponse(intent: intent))
    case .itemCommandExecutionRequestApproval(let r):
        try await client.respond(to: r, result: CommandExecutionRequestApprovalResponse(intent: intent))
    case .itemFileChangeRequestApproval(let r):
        try await client.respond(to: r, result: FileChangeRequestApprovalResponse(intent: intent))
    default:
        try await client.reject(request, code: -32601, message: "not implemented")
    }
}
```

Each `init(intent:)` maps the canonical intent to the correct underlying wire enum automatically.

## Intent semantics

- **`.allowOnce`** — approve this specific action. The agent may ask again for the next equivalent action.
- **`.allowForSession`** — approve this action and suppress re-prompting for equivalent actions for the rest of the session.
- **`.deny`** — decline the action but let the turn continue. The agent may try an alternate approach.
- **`.abort`** — decline and immediately end the turn. Use this when the user wants the agent to stop entirely, not just skip one step.

`.deny` is a soft decline; `.abort` is a hard stop. If you present a single "Deny" button, decide up front which semantic you want. Most UI patterns map "Deny" to `.deny` and a separate "Stop Turn" button to `.abort`.

## Responding to unrecognised requests

The server may send request types this library knows about but your app does not handle (e.g. `itemPermissionsRequestApproval`). Reject them explicitly rather than leaving them unanswered — an unanswered server request stalls the turn indefinitely:

```swift
default:
    try await client.reject(request, code: -32601, message: "not implemented")
```

JSON-RPC code `-32601` ("method not found") is the conventional signal that the client does not support the method.

## Pairing approvals with `streamTurn`

``CodexClient/streamTurn(input:threadId:)`` handles the subscribe-before-trigger
race for *deltas*, but it does not subscribe to server requests on your behalf.
Approval requests come from the same multicast event stream, and that stream
does not buffer events emitted before subscription. Subscribe to your typed
approval listener *before* invoking `streamTurn`, then run both as concurrent
tasks:

```swift
async let approvals: Void = {
    for await request in await client.serverRequests(of: ServerRequests.ItemFileChangeRequestApproval.self) {
        let intent = await askUser(for: request)
        try? await client.respond(to: request, result: FileChangeRequestApprovalResponse(intent: intent))
    }
}()

let turn = try await client.streamTurn(input: input, threadId: thread.id)
for await delta in turn.deltas {
    bubble.text += delta.delta
}
_ = await approvals  // cancel via Task.cancel() when you're done with the thread
```

Subscribing after `streamTurn` returns can race the first approval request and
silently drop it.

## Per-thread config escape hatch

`ThreadStartParams.config: [String: JSONAny]?` is a freeform map merged into codex's TOML config pipeline *for this thread only*, before any typesafe overrides. It accepts the same dotted keys you would pass to `-c key=value` at the CLI, and reaches knobs that have no first-class typed equivalent on `ThreadStartParams`:

```swift
let thread = try await client.call(
    RPC.ThreadStart.self,
    params: ThreadStartParams(
        config: [
            "features.exec_permission_approvals": .bool(true),
            "model_reasoning_effort": .string("high"),
        ],
        sandbox: .readOnly
    )
)
```

Prefer typed fields (`sandbox`, `model`, `cwd`, `approvalPolicy`) when they exist; reach for `config` for everything else. For process-wide overrides see ``LocalServerOptions/extraConfig`` instead.

## Inspecting request params

Each typed case carries a `params` value with the request details. For example:

```swift
case .applyPatchApproval(let r):
    print("Patch to apply:\n\(r.params.patch)")
    let intent = await askUser(description: r.params.patch)
    try await client.respond(to: r, result: ApplyPatchApprovalResponse(intent: intent))
```

The exact shape of each params type is visible in the generated protocol types.
