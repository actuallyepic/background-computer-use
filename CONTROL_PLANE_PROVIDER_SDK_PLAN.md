# Control Plane Provider SDK Plan

## Purpose

BackgroundComputerUse should become the local control plane for AI-controllable apps.

The important product promise is not that BCU is a browser. The promise is that BCU can discover, observe, script, and act on controllable surfaces across apps that we own or that explicitly cooperate with the runtime.

Browser surfaces remain important because many custom apps will embed `WKWebView`, but they should be treated as one provider surface type, not as the center of the architecture.

## Goals

- Make it cheap to build custom Swift apps whose native windows and embedded `WKWebView` surfaces are controllable through BCU.
- Let a custom app expose multiple related surfaces, for example a main Slack webview and a sidebar webview that visualizes context from the main surface.
- Give BCU a stable provider bridge so registered surfaces are actually controllable, not just listed.
- Add an event stream so apps, agents, dashboards, and demo UIs can subscribe to live surface activity.
- Make JavaScript injection stable enough for reusable observers, visual extensions, and app-specific instrumentation.
- Keep process pool and cookie sharing predictable inside custom apps without making BCU own profile management.
- Preserve BCU as the centralized target registry, action router, cursor system, event bus, and normalization layer.

## Non-Goals

- Do not make BCU responsible for building app-specific sidebars, Slack integrations, CRM views, or product workflows.
- Do not require every app to use BCU-owned browser windows.
- Do not try to inject into arbitrary third-party `WKWebView` instances without cooperation from the owning app.
- Do not build full browser profile management in this slice. Consumer apps can own profile selection and persistence policy.
- Do not rewrite the existing native macOS Accessibility pipeline as part of this work.
- Do not require a route rename before the provider model works. Existing browser routes can remain as compatibility routes while the internal target model becomes provider-based.

## Mental Model

BCU is the control plane.

Custom apps are providers.

Provider surfaces are controllable targets.

Surface groups describe related targets that should be understood as one product setup.

Events describe what happened or changed.

Actions are routed by BCU to the provider that owns the target.

```text
Agent or demo app
  |
  | HTTP/SSE API
  v
BackgroundComputerUse control plane
  - target registry
  - provider registry
  - surface group registry
  - event bus
  - action router
  - cursor choreography
  - screenshot/window normalization
  - per-target execution lanes
  |
  | provider bridge
  v
Custom Swift app
  - native shell
  - main WKWebView surface
  - sidebar WKWebView surface
  - provider SDK
  - app-owned process pool/data store policy
```

## Existing Repo Fit

The repo already has useful pieces:

- Loopback API and route registry.
- Native window discovery, screenshots, and window motion.
- Cursor sessions and visual action choreography.
- BCU-owned `WKWebView` browser surfaces.
- Browser DOM snapshot, action, injection, and event primitives.
- Registered browser provider metadata.

The missing piece is a real provider bridge. Registered providers currently advertise targets, but BCU does not yet dispatch state reads, JavaScript, injection, or actions to those providers.

## Core Deliverables

### 1. Swift Provider SDK

Add a package surface that custom Swift apps can embed.

Intended app code:

```swift
import BackgroundComputerUse
import WebKit

let provider = BCUProvider(
    providerID: "xyz.dubdub.slack-context",
    displayName: "Slack Context"
)

provider.register(
    webView: slackWebView,
    surfaceID: "slack-main",
    role: "primary"
)

provider.register(
    webView: sidebarWebView,
    surfaceID: "context-sidebar",
    role: "extension"
)

try await provider.connect()
```

SDK responsibilities:

- Register and unregister provider lifecycle with BCU.
- Register one or more `WKWebView` surfaces.
- Install the BCU bootstrap script into each registered webview.
- Maintain stable `surfaceID` to target mappings.
- Implement DOM snapshot, target resolution, JavaScript evaluation, script injection, script removal, click, type, and scroll for registered webviews.
- Emit page, script, console, lifecycle, and app-specific events into BCU.
- Report host window metadata and geometry for cursor mapping.
- Send heartbeat and capability updates.
- Recover after app relaunch or BCU relaunch.

BCU responsibilities:

- Store provider registrations.
- Store surface registrations.
- Route control-plane calls to the correct provider bridge.
- Normalize responses into the existing state/action/event DTO style.
- Preserve per-target execution ordering.
- Reuse the existing cursor renderer and action timing.

### 2. Provider Bridge

The provider bridge is the control protocol between BCU and cooperating apps.

Preferred sequence:

1. Loopback HTTP bridge for rapid development and demos.
2. XPC bridge for production Swift apps.
3. Optional in-process bridge for apps that embed more of the BCU runtime directly.

Initial provider protocol methods:

```text
register_provider
unregister_provider
heartbeat
list_surfaces
get_surface_state
evaluate_javascript
inject_javascript
remove_injected_javascript
list_injected_javascript
dispatch_click
dispatch_type_text
dispatch_scroll
send_script_message
capture_surface_screenshot
```

BCU should not assume every provider supports every method. Capabilities stay explicit per surface.

Example surface capabilities:

```json
{
  "readDOM": true,
  "evaluateJavaScript": true,
  "injectJavaScript": true,
  "emitEvents": true,
  "receiveScriptMessages": true,
  "dispatchDOMEvents": true,
  "nativeClickFallback": false,
  "screenshot": true,
  "hostWindowMetadata": true,
  "geometryMapping": true
}
```

### 3. Registered Surface Dispatch

Registered targets must become first-class action targets.

Current behavior:

- Registered browser surfaces can be listed.
- Control calls fail because there is no live provider dispatch.

Desired behavior:

- BCU resolves the target ID.
- If the target is BCU-owned, BCU runs the local implementation.
- If the target is provider-owned, BCU forwards the request to the provider bridge.
- BCU normalizes the response, appends cursor/debug/event metadata, and returns a standard response.

Dispatch path:

```text
Client request
  -> BCU route
  -> target registry lookup
  -> provider bridge lookup
  -> provider method call
  -> response normalization
  -> event emission
  -> client response
```

Provider-owned actions should still use BCU action semantics:

- Read before action when useful.
- Reject stale state tokens when supplied.
- Move the same BCU cursor session to the provider-reported screen point.
- Dispatch the action through the provider.
- Wait for settle.
- Read after action.
- Return post-state token, screenshot, cursor telemetry, and warnings.

### 4. Surface Groups

Surface groups describe a related app setup.

This is important for the main-webview-plus-sidebar pattern.

Example:

```json
{
  "groupID": "slack-context-demo",
  "providerID": "xyz.dubdub.slack-context",
  "displayName": "Slack Context Demo",
  "surfaces": [
    {
      "surfaceID": "slack-main",
      "role": "primary",
      "targetID": "rb_..."
    },
    {
      "surfaceID": "context-sidebar",
      "role": "extension",
      "targetID": "rb_..."
    }
  ]
}
```

BCU should let clients:

- List groups.
- Subscribe to group events.
- Retrieve the primary target.
- Retrieve extension targets by role.
- Route actions to a target within a group.

This makes demos and agents much simpler. They can ask for the "Slack Context Demo" group instead of discovering loose windows.

### 5. Event Stream

The event stream should become a generic BCU feature, not a browser-only side channel.

Keep polling as a fallback, but add Server-Sent Events first:

```text
GET /v1/events/stream
POST /v1/events/poll
POST /v1/events/emit
POST /v1/events/clear
```

SSE is the first choice because:

- It is one-way, which matches the event bus.
- It is easy from JavaScript, Swift, and curl.
- It is demo-friendly.
- It avoids the extra protocol complexity of WebSocket until we need bidirectional low-latency messaging.

Event filters:

```json
{
  "providerID": "xyz.dubdub.slack-context",
  "groupID": "slack-context-demo",
  "surfaceID": "slack-main",
  "targetID": "rb_...",
  "types": [
    "script.ready",
    "dom.active_person",
    "console.error"
  ]
}
```

Event shape:

```json
{
  "eventID": "ev_123",
  "sequence": 123,
  "emittedAt": "2026-04-27T00:00:00Z",
  "providerID": "xyz.dubdub.slack-context",
  "groupID": "slack-context-demo",
  "surfaceID": "slack-main",
  "targetID": "rb_...",
  "source": "script",
  "type": "dom.active_person",
  "scriptID": "slack-observer",
  "correlationID": "act_456",
  "payload": {
    "name": "Jane Doe",
    "channelID": "D123"
  }
}
```

Event source categories:

- `provider`: provider lifecycle, heartbeat, reconnects, capability changes.
- `surface`: navigation, title changes, load failures, geometry changes.
- `script`: script ready, script error, script custom event.
- `console`: console log/warn/error.
- `page`: page error, unhandled promise rejection, DOM observer events.
- `action`: action started, cursor moved, dispatch completed, verification result.
- `client`: external control app emitted event.

Event bus requirements:

- Monotonic sequence numbers.
- Bounded retention.
- Filter by provider, group, surface, target, source, type, and script ID.
- Backpressure behavior for slow SSE clients.
- Replay from `sinceEventID` or `sinceSequence`.
- Payload size limits.
- Clear or expire events by target/group/provider.

### 6. JavaScript Injection Runtime

Injection should be stable enough for app-specific observers.

Script model:

```json
{
  "scriptID": "slack-observer",
  "version": "1.0.0",
  "sourceHash": "sha256:...",
  "targetID": "rb_...",
  "surfaceID": "slack-main",
  "urlMatch": "https://app.slack.com/*",
  "runAt": "document_idle",
  "contentWorld": "page",
  "persistAcrossReloads": true,
  "installedAt": "2026-04-27T00:00:00Z"
}
```

Injection requirements:

- Restore or preserve serialized `evaluate_js` behavior for complex values, DOM elements, async expressions, and thrown errors.
- Enforce `urlMatch` before persistent scripts run.
- Add install acknowledgements.
- Emit `script.ready`, `script.error`, and `script.removed` events.
- Support `send_script_message` so BCU or clients can send messages into a script.
- Include `scriptID`, version, and correlation IDs in emitted events.
- Separate internal bridge code from page-level user scripts where feasible.
- Keep the bootstrap script versioned and small.

Script lifecycle:

```text
registered
  -> installed
  -> ready
  -> active
  -> failed | removed | superseded
```

Provider SDK should make common observer scripts easy:

```swift
try await provider.inject(
    scriptID: "slack-observer",
    into: "slack-main",
    runAt: .documentIdle,
    persistAcrossReloads: true,
    source: observerSource
)
```

### 7. WebView Environment And Process Pool

BCU-owned browser windows should use a shared process pool and persistent website data store.

Custom apps cannot share a `WKProcessPool` with BCU across process boundaries. Instead, the provider SDK should give apps a recommended in-app environment:

```swift
let environment = BCUWebEnvironment.shared
let webView = WKWebView(
    frame: .zero,
    configuration: environment.makeConfiguration()
)
```

`BCUWebEnvironment` should provide:

- Shared `WKProcessPool` inside the custom app.
- Shared persistent `WKWebsiteDataStore.default()` by default.
- Optional non-persistent configuration for test/demo isolation.
- Common `WKUserContentController` setup.
- BCU bootstrap script installation.
- Message handler registration.
- Recommended media/autoplay/preferences defaults.
- App-provided user agent override hook.

Profiles are intentionally deferred. Consumer apps can decide whether to use default storage, app-specific website data stores, app groups, or ephemeral stores.

Acceptance criteria:

- Two webviews created from the same `BCUWebEnvironment` inside one app share cookies and local storage behavior expected from a normal WebKit app.
- A provider app can create a main surface and sidebar surface with one shared environment.
- BCU can control both surfaces independently through target IDs.

## Proposed Implementation Phases

### Phase 1: Provider Dispatch Skeleton

Scope:

- Introduce provider bridge interfaces.
- Store live provider bridge records in BCU.
- Convert registered browser targets from metadata-only to provider-backed targets.
- Route `get_state`, `evaluate_js`, `inject_js`, `remove_injected_js`, `list_injected_js`, `click`, `type_text`, and `scroll` to providers when target kind is registered/provider-owned.

Validation:

- Unit test target registry lookup for owned vs provider-owned targets.
- Unit test unsupported capabilities produce explicit errors.
- Unit test provider disconnect produces actionable errors.
- Fixture provider returns deterministic state and action responses.

Exit criteria:

- A registered provider target can be controlled through the same high-level routes as an owned target.

### Phase 2: Swift Provider SDK

Scope:

- Add `BCUProvider`.
- Add `BCUWebSurface`.
- Add `BCUWebEnvironment`.
- Add provider lifecycle: connect, heartbeat, reconnect, disconnect.
- Add `register(webView:surfaceID:role:)`.
- Add basic state/eval/inject/action bridge for `WKWebView`.

Validation:

- Build a minimal Swift fixture app with two webviews.
- Register both webviews with BCU.
- List both surfaces through BCU.
- Evaluate JavaScript in each webview.
- Inject a script into the main webview and verify a ready event.
- Type into a text input in the main webview.
- Click a button in the sidebar webview.

Exit criteria:

- A new Swift app can become BCU-controllable with a small amount of provider code.

### Phase 3: Generic Event Stream

Scope:

- Add generic `/v1/events/*` routes.
- Add SSE streaming endpoint.
- Preserve polling fallback.
- Add event filters.
- Add provider, group, target, surface, type, source, and script metadata.
- Bridge browser events into the generic event bus.

Validation:

- Unit test filtering by each metadata field.
- Unit test bounded retention.
- Unit test `sinceEventID` and `sinceSequence`.
- Integration test with SSE client receiving script and console events.
- Confirm slow clients do not block event emission.

Exit criteria:

- A demo UI can subscribe to one surface group and show events live without polling loops.

### Phase 4: Script Runtime Hardening

Scope:

- Restore robust serialized async `evaluate_js`.
- Add script lifecycle metadata.
- Enforce URL matching.
- Add script ready/error events.
- Add script messaging.
- Add source hash/version reporting.

Validation:

- Evaluate primitive values, arrays, objects, DOM elements, promises, thrown errors, and circular-ish objects.
- Inject persistent script, reload, verify ready event.
- Inject `document_start` script, navigate, verify it ran early enough.
- Remove script, reload, verify it no longer runs.
- Send message into script, verify page receives it.

Exit criteria:

- Observer scripts are reliable across reloads and can be debugged from the event stream.

### Phase 5: Surface Groups

Scope:

- Let providers register surface groups.
- Add group listing and lookup.
- Add group-scoped event subscription.
- Add primary/extension role metadata.

Validation:

- Register a group with `primary` and `extension` surfaces.
- Subscribe to group events.
- Emit main-surface context and verify sidebar receives or displays it.
- Control each target separately through its target ID.

Exit criteria:

- A main webview plus visual extension webview can be addressed as one setup.

### Phase 6: Demo App

Scope:

- Build a Swift app with two webviews.
- Main webview hosts a Slack-like fixture or real Slack if auth is acceptable.
- Sidebar webview shows context from events.
- Provider SDK registers both surfaces.
- Observer script emits active-person/context events.
- BCU controls both surfaces and shows cursor movement.

Validation:

- Start BCU.
- Start demo app.
- Confirm BCU lists provider, group, and surfaces.
- Subscribe to group event stream.
- Navigate/change selected person in main surface.
- See sidebar update from events.
- Use BCU to type/click/scroll in the main surface.
- Use BCU to interact with the sidebar surface.
- Record screenshots and cursor telemetry.

Exit criteria:

- The demo visually communicates that one central control plane can observe, script, and act across a custom mixed native/web app.

## Testing Matrix

### Unit Tests

- Provider registration validates non-empty IDs and stable target generation.
- Duplicate provider registrations replace old targets cleanly.
- Provider disconnect marks targets unavailable.
- Capability checks block unsupported operations.
- Event store filters by provider, group, surface, target, source, type, and script ID.
- Event retention caps memory.
- Script metadata records version/hash/runAt/urlMatch.
- State-token mismatch rejects action before dispatch.
- Geometry conversion handles viewport coordinates to screen coordinates.

### Integration Tests

- Launch BCU through the signed app bundle path.
- Launch fixture provider app.
- Register two webviews.
- Read state from both.
- Evaluate JavaScript against both.
- Inject a persistent observer script.
- Reload and verify script readiness.
- Click by selector, node ID, display index, and coordinate.
- Type into an input.
- Scroll document and nested scroll container.
- Subscribe through SSE and receive expected events.
- Simulate provider restart and verify re-registration.
- Simulate BCU restart and verify provider reconnect.

### WebView Environment Tests

- Main and sidebar webviews in one app share the configured process pool.
- Cookie set in one webview is visible where WebKit normally allows it in another webview with the same data store.
- Local storage persists across reloads.
- Ephemeral environment does not persist storage.
- User agent override, when supplied by app, is visible in page JavaScript.
- Default environment does not force BCU to own profiles.

### Event Stream Tests

- SSE receives events in order.
- SSE can resume from the last event ID.
- Polling returns the same events as SSE for the same filter.
- Slow clients are disconnected or skipped without blocking producers.
- Oversized payloads are rejected or truncated according to policy.
- Event clear removes only scoped events.

### Script Runtime Tests

- `evaluate_js` supports async expressions.
- `evaluate_js` serializes DOM elements into interactable-like summaries.
- `evaluate_js` returns structured thrown errors.
- `inject_js` waits for `script.ready` when requested.
- `urlMatch` prevents injection on nonmatching URLs.
- Removed scripts do not run after reload.
- Script messages are delivered to the intended script and target.
- Console logs and page errors arrive as events.

### Demo Validation

- A viewer can see the controlled app, cursor, event stream, and sidebar update in one recording.
- The event stream labels which surface emitted each event.
- The action timeline shows read, resolve, cursor move, dispatch, settle, and reread.
- The same cursor session can move between the main webview and sidebar webview.
- The app keeps working after reload.
- The provider app can be quit and relaunched without requiring a BCU rebuild.

## Implemented Spotify WebView Demo

This slice includes a separate SwiftPM macOS executable, `SpotifyWebViewApp`, that proves the provider model against a real embedded web app.

What it demonstrates:

- A separate macOS process embeds `BackgroundComputerUseKit`.
- The app creates a shared `BCUWebEnvironment` webview using the default `WKWebsiteDataStore`, so cookies and storage behave like a normal WebKit browser surface inside the app.
- The app loads `https://open.spotify.com`.
- The app registers the webview with BCU as provider `xyz.dubdub.spotify-webview`, surface `spotify-main`.
- BCU exposes the Spotify webview through `POST /v1/browser/list_targets` as a registered browser surface.
- BCU can call the normal browser routes against that registered target: `get_state`, `evaluate_js`, `inject_js`, `click`, `type_text`, `scroll`, `reload`, and `close`.
- Registered clicks, typing, and scrolls still use BCU's central cursor choreography before dispatching to the provider-owned webview.
- The app injects a visible `BCU` button into the Spotify UI.
- Clicking that button emits a provider page event and opens a native AppKit sidebar in the Spotify app.
- The same event is forwarded into the generic BCU event bus and can be observed through polling or SSE.

Run it:

```bash
swift run BackgroundComputerUse
```

In a second terminal:

```bash
swift run SpotifyWebViewApp
```

The Spotify app discovers BCU from `BCU_BASE_URL`, `BACKGROUND_COMPUTER_USE_BASE_URL`, or the runtime manifest at `$TMPDIR/background-computer-use/runtime-manifest.json`.

Basic validation:

```bash
curl -s -X POST "$BCU_BASE_URL/v1/browser/list_targets" \
  -H 'content-type: application/json' \
  -d '{"includeRegistered":true}'
```

Use the returned registered target ID for browser calls. For the default Spotify demo it is derived from the provider and surface IDs, for example `rb_xyz_dubdub_spotify_webview_spotify_main`.

```bash
curl -s -X POST "$BCU_BASE_URL/v1/browser/get_state" \
  -H 'content-type: application/json' \
  -d '{"browser":"rb_xyz_dubdub_spotify_webview_spotify_main","imageMode":"omit","maxElements":100}'
```

Selector targeting should resolve inside the provider when the snapshot does not already contain the target:

```bash
curl -s -X POST "$BCU_BASE_URL/v1/browser/click" \
  -H 'content-type: application/json' \
  -d '{"browser":"rb_xyz_dubdub_spotify_webview_spotify_main","target":{"kind":"dom_selector","value":"button[title=\"Open native BCU sidebar\"]"}}'
```

Event validation:

```bash
curl -s -X POST "$BCU_BASE_URL/v1/events/poll" \
  -H 'content-type: application/json' \
  -d '{"filter":{"providerID":"xyz.dubdub.spotify-webview"},"limit":20}'
```

## Acceptance Criteria For The First Useful Version

- A separate Swift app can embed the provider SDK.
- That app can register two `WKWebView` surfaces.
- BCU can list both surfaces with target IDs and capabilities.
- BCU can read DOM state from both surfaces.
- BCU can evaluate JavaScript in both surfaces.
- BCU can inject a named script and receive `script.ready`.
- BCU can click, type, and scroll in a provider-owned webview.
- BCU can stream provider/script/page/action events over SSE.
- A group subscription can observe both main and sidebar surfaces.
- The SDK exposes a shared webview environment for process-pool consistency inside the provider app.

## Open Decisions

- Whether the first provider bridge should be loopback HTTP only, or loopback plus XPC from the start.
- Whether generic target routes should be added now, or existing browser routes should route provider targets until a later cleanup.
- Exact auth model for provider registration and event subscription.
- Whether scripts should be stored by BCU, by the provider app, or by the external control client.
- How much screenshot capture should happen in BCU versus provider-side rendering for offscreen or hidden surfaces.
- Whether surface groups should be provider-declared only, or also client-created for ad hoc demos.

## Recommended Next Step

Build Phase 1 and Phase 2 together against a tiny fixture app.

The fixture should have:

- One native window.
- One primary `WKWebView` with a form, buttons, scroll area, and active-person fixture.
- One sidebar `WKWebView` that renders received context.
- Provider SDK registration for both webviews.
- A small observer script that emits `dom.active_person`.

That fixture will force the provider SDK, event bus, injection lifecycle, geometry mapping, and multi-surface story to become real without depending on Slack auth or third-party app behavior.
