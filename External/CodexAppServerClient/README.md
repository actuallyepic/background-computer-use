# codex-app-server-client

Minimal Swift Package Manager client for `codex app-server`.

OpenAI Codex is open source:

- https://github.com/openai/codex

This package is intentionally opinionated:

- generated from a pinned Codex version
- includes experimental API surface in generated bindings
- enables `experimentalApi` by default at runtime
- uses WebSocket transport for local managed launch
- enforces exact Codex version matching by default

The goal is to make native app integration as small as possible while keeping the protocol strongly typed.

## What It Includes

- generated Swift protocol models from `codex app-server generate-json-schema --experimental`
- generated typed RPC method bindings from `codex app-server generate-ts --experimental`
- typed server notification and server request decoding
- local managed launcher for `codex app-server --listen ws://127.0.0.1:0`
- remote WebSocket connection support

## What It Does Not Include

- stdio transport
- reconnect logic
- UI/session abstractions
- version compatibility shims across Codex releases

Those are omitted on purpose to keep the package small and predictable.

## Requirements

- Swift 6.1+
- Apple platforms
- `codex` installed locally for managed local launch on macOS
- exact match between the app-server Codex version and the generated binding version when using exact version policy

Current pinned Codex version: `0.121.0`

## Install

```swift
.package(
    url: "https://github.com/financialvice/codex-app-server-client.git",
    exact: "0.121.0"
)
```

## Documentation

Hosted DocC docs cover concept guides (streaming, cancellation, approvals,
multi-thread routing, resume, error handling, processLog) plus the full
generated reference for every RPC method, notification, and server request.

- Hosted: <https://financialvice.github.io/codex-app-server-client/documentation/codexappserverclient/>
- Build locally: `swift package --disable-sandbox preview-documentation --target CodexAppServerClient`

`SPEC.md` codifies the discoverability and API-shape commitments the package
upholds across regenerations.

## Example

A minimal end-to-end example executable lives in:

- `Sources/CodexAppServerExample/main.swift`

Run it with:

```bash
swift run CodexAppServerExample
```

## Local Managed Example

`localManaged()` is available on macOS.

```swift
import CodexAppServerClient

let client = try await CodexClient.connect(
    .localManaged(),
    options: CodexClientOptions(
        clientInfo: ClientInfo(
            name: "my_native_app",
            title: "My Native App",
            version: "0.1.0"
        )
    )
)

let thread = try await client.call(
    RPC.ThreadStart.self,
    params: ThreadStartParams(ephemeral: true)
)

for await event in client.events {
    switch event {
    case .notification(let notification):
        print(notification.method)
    case .serverRequest(let request):
        print(request.method)
    default:
        break
    }
}
```

## Remote Example

Remote websocket connections are available on every supported platform. For remote connections, exact version policy requires the caller to declare the expected remote Codex version explicitly, and the client verifies it again against the `initialize.userAgent` returned by the server:

```swift
let client = try await CodexClient.connect(
    .remote(
        RemoteServerOptions(
            url: URL(string: "ws://127.0.0.1:4500")!,
            codexVersion: "0.121.0"
        )
    ),
    options: CodexClientOptions(
        clientInfo: ClientInfo(
            name: "my_native_app",
            title: "My Native App",
            version: "0.1.0"
        )
    )
)
```

## Regenerating Bindings

The package is generated from the local `codex` binary and requires that the installed version match `.codex-version`.

```bash
./Scripts/generate-protocol.sh
```

## Release Model

Package versions are intended to match Codex versions exactly.

Example:

- package `0.121.0`
- generated from `codex 0.121.0`

### When the Swift binding is republished without a Codex bump

Swift bindings sometimes need to evolve (new convenience APIs, doc fixes,
footgun fixes) without an upstream `openai/codex` release. We preserve the
1:1 version mapping by **force-moving the codex version tag** rather than
issuing a separate Swift-only patch number.

The cost: SwiftPM caches a per-version SHA in
`~/Library/org.swift.swiftpm/security/fingerprints/` on first resolve. If you
already resolved this package at the prior tag SHA, your next resolve will
fail with:

```
error: Revision <new_sha> for package <pkg> at version 0.121.0 does not match
previously recorded value <old_sha>
```

Recovery is one command:

```bash
rm ~/Library/org.swift.swiftpm/security/fingerprints/codex-app-server-client-*.json
swift package update
```

For CI, you can pass `--resolver-fingerprint-checking warn` to any
`swift package` invocation to downgrade the error to a warning.

## CI And Release

Two GitHub Actions workflows are included:

- `CI`
  - installs the pinned Codex version
  - regenerates bindings
  - verifies generated files are committed
  - runs `swift build` and `swift test`

- `Release`
  - manual workflow
  - requires the input version to match `.codex-version`
  - reruns generation, build, and tests
  - creates and pushes a Git tag
  - creates a GitHub Release

The release workflow assumes the repository state is already committed and ready. It does not auto-commit regenerated files.
