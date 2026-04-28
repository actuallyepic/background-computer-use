# Getting Started

Connect to a codex app-server, start a thread, observe the turn.

## Add the dependency

```swift
.package(url: "https://github.com/…/codex-app-server-client", from: "0.121.0")
```

Target dependency: `"CodexAppServerClient"`.

## Launch a local codex app-server

```swift
import CodexAppServerClient

let client = try await CodexClient.connect(
    .localManaged(),
    options: CodexClientOptions(
        clientInfo: ClientInfo(name: "my_app", title: "My App", version: "1.0.0")
    )
)
defer { Task { await client.disconnect() } }
```

`LocalServerOptions` lets you override the codex executable, working directory, or environment.

## Connect to a remote codex

```swift
let client = try await CodexClient.connect(
    .remote(RemoteServerOptions(
        url: URL(string: "wss://codex.example.com")!,
        authToken: "…",
        codexVersion: CodexBindingMetadata.codexVersion
    )),
    options: CodexClientOptions(clientInfo: clientInfo)
)
```

Bearer auth requires `wss://` or a loopback `ws://` URL.

## Make a typed request

```swift
let thread = try await client.call(
    RPC.ThreadStart.self,
    params: ThreadStartParams(ephemeral: true)
)
```

## Observe notifications

```swift
for await event in await client.events() {
    switch event {
    case .notification(let note):
        print("notification:", note.method.rawValue)
    case .serverRequest(let request):
        try? await client.reject(request, message: "not supported")
    case .connectionStateChanged(.disconnected(let reason)):
        print("disconnected:", reason.description)
    default:
        break
    }
}
```

Or filter for a single method:

```swift
for await delta in await client.notifications(of: ServerNotifications.ItemAgentMessageDelta.self) {
    print(delta.delta)
}
```

## Stream a whole turn in one call

For the 90% case — send a prompt, render tokens as they arrive, know when the turn is done —
use ``CodexClient/streamTurn(input:threadId:)``. It opens the subscription *before*
issuing `RPC.TurnStart` so no deltas are missed, filters by the captured `turnId`, and
finishes cleanly on `TurnCompleted`:

```swift
let turn = try await client.streamTurn(
    input: [.text("Explain recursion briefly.")],
    threadId: thread.thread.id
)
for await delta in turn.deltas {
    print(delta.delta, terminator: "")
}
```

The returned ``TurnStream`` also exposes ``TurnStream/turnId`` so you can call
`RPC.TurnInterrupt` mid-stream — `Task.cancel()` alone does not stop the server.

## Packaging note: `@main` and `main.swift`

When you scaffold a Swift Package Manager executable target that uses this library,
Swift forbids the `@main` attribute in a file literally named `main.swift` — SPM already
treats that file as the implicit entry point. Name the file anything else (`App.swift`
is conventional) and put `@main struct App: App` there.

```swift
// Sources/MyApp/App.swift    ← NOT main.swift
@main struct MyApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
```

The collision produces the cryptic `"'main' attribute cannot be used in a module that
contains top-level code"` error. This is a SwiftPM rule, not a library rule.
