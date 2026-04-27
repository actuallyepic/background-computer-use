# Browser Surface Control Plan

## Goal

Extend BackgroundComputerUse so it can own or register browser-like surfaces and expose low-level DOM, JavaScript, cursor, and action primitives through the same API style it already uses for native macOS windows.

BCU should be the control substrate, not the application platform. A separate user-built app, for example a Vite app running on `localhost`, should be able to call the BCU API, inspect/control a Slack browser target, inject or evaluate JavaScript, subscribe to page events, and render its own UI wherever it wants.

## Core Principle

Keep BCU simple and composable:

- BCU owns targets, state reads, script execution, actions, geometry mapping, cursor movement, and event transport.
- External apps own product-specific UI, workflow logic, sidepanels, dashboards, and provider integrations.
- BCU can create a plain owned browser window for a URL, including `localhost`, but it should not understand that app's business logic.
- BCU can inject JavaScript into an owned or registered browser surface, but it should not have a first-class "extension UI" framework.

The API should make powerful custom apps possible without forcing those apps to live inside this repo.

## Non-Goals

- Do not build a Chrome extension compatibility layer.
- Do not make BCU responsible for rendering Slack-style sidepanels or custom product UIs.
- Do not make BCU own feature-app manifests, app-specific lifecycle, or provider-specific permissions in phase 1.
- Do not start by inspecting arbitrary third-party `WKWebView` instances across process boundaries.
- Do not add a separate `/v1/windows/*` surface for this work. Reuse the existing native window APIs for shell movement and focus.
- Do not replace the existing Accessibility-based native window pipeline.

## Current Repo Shape

BackgroundComputerUse already has the right foundation if browser surfaces are treated as another target provider.

- The route layer is centralized through `Router` and route services.
- Native windows are resolved through `WindowTargetResolver` and stable `w_...` IDs.
- Actions already flow through state reads, dispatch, verification, and optional cursor choreography.
- `RuntimeExecutionQueue` gives a useful per-window execution model for parallelism.
- `CursorCoordinator` can animate against real screen coordinates, so DOM actions only need a reliable DOM-rect-to-screen-point mapper.

The new work is to add browser providers and then expose them through the target/action model. The first provider owns BCU-created `WKWebView` windows. The later provider lets cooperating macOS apps register their own `WKWebView` surfaces.

## Learnings From `../wv-perf`

The `wv-perf` repo validates the core idea.

Useful concepts to port:

- Keep workspace truth separate from page truth. Native window state, screenshot state, and live DOM state are related but not identical.
- Use an atomic action loop: read state, resolve element, move cursor, dispatch DOM/native action, wait, read state again.
- Make interactables a first-class snapshot, not an afterthought.
- Return selector ambiguity instead of hiding it.
- Use stable cursor/session identity across page actions.
- Map DOM rects to world/screen coordinates before moving the cursor.

What should change for BCU:

- Move the experiment-specific TypeScript control scripts into first-class Swift services and route DTOs.
- Reuse the existing BCU cursor sessions instead of a separate cursor daemon.
- Keep the API lower-level than the `wv-perf` experiment. BCU should not know what a Slack sidepanel or Codex panel means.

## Architecture

Use a target provider model.

```text
BackgroundComputerUseRuntime
  Router / direct Swift facade
  RuntimeExecutionQueue
  CursorCoordinator
  TargetRegistry
    NativeWindowProvider
      AX state
      AX/native actions
    OwnedBrowserProvider
      WKWebView windows
      tabs
      DOM state
      JavaScript execution
      script injection
      page event bridge
    RegisteredBrowserProvider
      XPC or loopback IPC
      app-declared WKWebView surfaces
      provider-side JavaScript execution
      provider-side injection
```

Keep browser routes explicit. The same `/v1/browser/*` routes should eventually dispatch to both BCU-owned browser windows and registered browser surfaces from other apps. Do not collapse this into a generic target API in this phase; the existing native macOS API and the browser API should remain different public surfaces.

## Target Model

Suggested IDs:

- `w_...`: existing native Accessibility window.
- `bw_...`: owned browser window.
- `bt_...`: owned browser tab.
- `rb_...`: registered browser surface from another cooperating macOS app.

Every target should declare:

- `id`
- `kind`
- `ownerApp`
- `title`
- `url` when applicable
- `frame`
- `screen`
- `parentTargetId` when applicable
- `capabilities`

Example capabilities:

```json
{
  "readDom": true,
  "evaluateJavaScript": true,
  "injectJavaScript": true,
  "emitPageEvents": true,
  "dispatchDomEvents": true,
  "nativeClickFallback": true,
  "screenshot": true,
  "hostWindowMetadata": true
}
```

## Phase 1: Owned Browser Window

Build one package-owned browser window with one `WKWebView`.

Implementation pieces:

- `BrowserSurfaceRegistry`: owns browser windows, tabs, and target IDs.
- `BrowserWindowHost`: an `NSWindow` plus `WKWebView`, navigation delegate, script manager, and geometry mapper.
- `BrowserTab`: stable tab identity, URL, title, loading state, and DOM snapshot metadata.
- `BrowserBridge`: a minimal `WKScriptMessageHandler` bridge for script results and page events.
- `BrowserBootstrapScript`: always-injected core script for DOM snapshots, interactables, element resolution, event dispatch, and bridge transport.
- `BrowserActionService`: click, type, scroll, wait, and evaluate JavaScript against browser targets.
- `BrowserStateService`: state reads that combine page truth, window geometry, screenshot, and cursor state.

Initial routes:

```text
POST /v1/browser/create_window
POST /v1/browser/list_targets
POST /v1/browser/navigate
POST /v1/browser/get_state
POST /v1/browser/evaluate_js
POST /v1/browser/inject_js
POST /v1/browser/remove_injected_js
POST /v1/browser/list_injected_js
POST /v1/browser/click
POST /v1/browser/type_text
POST /v1/browser/scroll
POST /v1/browser/reload
POST /v1/browser/close
```

These routes should be primitives. They should not include "open Slack sidepanel" or "email search" semantics.

`create_window` is allowed to create a native `NSWindow` because a BCU-owned browser needs a host. That does not mean there should be a separate public window-surface API. The returned browser target should include any containing native window metadata needed to call existing BCU window/frame routes when shell movement is required.

## Native UI Requirements

The first UI should be a simple native macOS browser window, not a custom dashboard.

Requirements:

- One `WKWebView` filling the content area.
- Minimal native toolbar with a URL field, back/forward/reload controls, and a small loading/status affordance.
- Use standard SwiftUI/AppKit controls and system toolbar behavior first.
- Use Liquid Glass/system materials where the app framework provides them; avoid custom opaque chrome, fake blur, decorative gradients, or heavy sidebars.
- Launch and validate as a signed `.app` through the existing `script/build_and_run.sh` path so macOS permissions and foreground activation behave like the rest of BCU.

The browser surface work should feel like a native macOS tool. The implementation should avoid building app-specific UI until external apps consume the API.

## DOM State Contract

The DOM state needs to be useful for agents and external apps.

Minimum state:

- URL, title, ready state, load progress, viewport, scroll offsets, device scale factor.
- Focused element and selection state.
- Interactables: links, buttons, inputs, textareas, contenteditable regions, ARIA controls, selectable rows/items, and visible custom controls.
- For each interactable: stable node handle, role, text, accessible name, selector candidates, bounding rects, visibility, enabled/editable state, and confidence.
- Optional raw DOM or pruned DOM, capped by request size.
- Screenshot path or base64 using the existing image mode pattern.
- State token to detect stale element handles.

Element resolution should accept multiple target styles:

```json
{
  "target": {
    "kind": "dom_selector",
    "value": "button[aria-label='Send']"
  }
}
```

```json
{
  "target": {
    "kind": "browser_node_id",
    "value": "node_178"
  }
}
```

```json
{
  "target": {
    "kind": "display_index",
    "value": 12
  }
}
```

Selector ambiguity should be explicit. If a selector matches multiple visible elements, return candidates unless the caller opts into first-match behavior.

## Cursor Model

Browser DOM control should reuse the same visual cursor system as native app control.

Action flow:

1. Resolve the browser target and tab.
2. Read live DOM state.
3. Resolve the requested element or coordinate.
4. Map DOM rect center to window/screen coordinates.
5. Move the existing BCU cursor to that point.
6. Dispatch DOM event, native event fallback, or JavaScript primitive.
7. Wait for configured settle conditions.
8. Read state again.

This lets one cursor session move from a DOM element in an owned webview to a native app window and back.

## JavaScript Model

Expose low-level JavaScript primitives, not an extension framework.

There should be three script modes:

1. Ephemeral evaluation
   - `evaluate_js` runs JavaScript now and returns the result.
   - Best for one-off reads, writes, debugging, and agent-driven actions.

2. Injected script
   - `inject_js` installs named JavaScript into an owned or registered browser target, tab, or matching URL pattern.
   - Supports `document_start`, `document_end`, and `document_idle`.
   - Can be persistent across reloads when the owning provider supports persistence.
   - Does not imply BCU understands the script's UI or app semantics.

3. Core bootstrap
   - Internal BCU script installed into owned browser tabs and provided to registered browser providers.
   - Provides DOM snapshots, interactables, element resolution, event dispatch, and page event transport.
   - Should remain small and stable.

Adding or changing ordinary JavaScript should not require rebuilding or relaunching all windows. A page reload may be needed for `document_start` scripts. A native rebuild should only be needed for new native APIs, entitlements, window types, provider protocol changes, or bridge capabilities.

## Page Event Bridge

External apps need a way to react to page changes without polling constantly.

BCU should expose a generic event bridge:

```text
GET /v1/events
POST /v1/browser/events/emit
POST /v1/browser/events/clear
```

The exact transport can be Server-Sent Events or WebSocket. The key is that injected scripts can emit typed JSON events and outside apps can subscribe.

The bridge should be intentionally dumb:

- It relays events.
- It scopes events by target ID, tab ID, script ID, and cursor/session ID when available.
- It does not interpret Slack, Gmail, Codex, or any other app-specific concept.
- It enforces size limits and origin/target scoping.

Example page script event:

```json
{
  "targetId": "bt_5",
  "scriptId": "slack-dm-observer",
  "type": "person_context",
  "payload": {
    "name": "Jane Doe",
    "handle": "jane",
    "emailHints": ["jane@example.com"]
  }
}
```

BCU should also allow external clients to send messages back into an injected script:

```text
POST /v1/browser/scripts/send_message
```

This keeps the communication primitive generic while allowing rich apps to be built outside the core runtime.

## Example: External Vite App For Slack Context

The Slack DM sidepanel should be built outside BCU.

Possible flow:

1. User starts a Vite app on `http://localhost:5173`.
2. The Vite app calls `POST /v1/browser/create_window` to open Slack in an owned BCU browser, or discovers an existing owned/registered Slack browser target through `POST /v1/browser/list_targets`.
3. The Vite app calls `POST /v1/browser/inject_js` with a small Slack observer script.
4. The observer reads the active DM person from the Slack DOM and emits `person_context` events through the BCU page event bridge.
5. The Vite app subscribes to `GET /v1/events`.
6. The Vite app renders its own sidepanel UI in its own browser, native shell, or an optional BCU-owned browser window loaded at the Vite URL.
7. If the app wants to act on Slack, it calls BCU primitives such as `evaluate_js`, `click`, `type_text`, or `scroll`.

BCU does not know that this is a Slack sidepanel. It only knows about browser targets, scripts, events, JavaScript, DOM state, cursor movement, and actions.

## No Separate Window Surface

Do not add a standalone `/v1/windows/*` surface for this plan.

BCU already has native window discovery and manipulation routes. Browser work should reuse those where possible instead of duplicating focus, frame, resize, and close behavior under a second API.

The browser API should expose enough host metadata to connect the two worlds:

- browser target ID
- containing app bundle ID and process ID
- containing native window ID when available
- host frame and screen
- tab/frame geometry inside the host window

For BCU-owned browser windows, `POST /v1/browser/create_window` can accept initial title, URL, and frame options as creation parameters. After creation, layout and shell manipulation should go through existing native window/frame APIs when those APIs already cover the behavior.

For registered browser surfaces inside another macOS app, BCU should not assume it can move or rearrange the host window through browser routes. If layout is needed, use existing native macOS window routes or an explicit provider capability later.

## Tabs, Grids, And Layouts

After one browser window is working, add composition primitives.

Tabs:

- Multiple tabs per browser window.
- Active/inactive tab state.
- Per-tab script injection.
- Tab-level target IDs and action lanes.

Grids:

- A browser composition mode that hosts multiple browser tabs or webviews at once.
- Each cell has a target ID and frame.
- Cursor movement maps across cells using the same geometry layer.
- Parallel actions are allowed on independent targets, with serialization per target.

Layouts should stay browser-scoped. BCU can create and place owned browser surfaces inside BCU-owned browser hosts, but external apps decide what their own app layouts mean. For app-wide window layout, reuse existing native window APIs or defer to the registered app provider.

## Registered Browser Surfaces

There are two ways external apps should work with BCU.

First, any app can be a control client by calling the HTTP API. This is enough for the Vite Slack example.

Second, a more advanced macOS app can register its `WKWebView` surfaces with BCU so the same browser endpoints can target them directly. This is the later provider model.

Registered browser provider example:

```json
{
  "providerId": "com.example.custom-app",
  "displayName": "Custom App",
  "protocolVersion": 1,
  "browserSurfaces": [
    {
      "id": "main",
      "kind": "wkwebview",
      "url": "https://app.example.com",
      "title": "Example",
      "hostWindow": {
        "bundleId": "com.example.custom-app",
        "processId": 1234,
        "windowId": "w_abc"
      },
      "capabilities": [
        "read_dom",
        "click",
        "type_text",
        "evaluate_js",
        "inject_js",
        "page_events"
      ]
    }
  ]
}
```

Transport options:

- In-process Swift package provider for apps that embed BCU.
- Local XPC service for signed macOS apps.
- Loopback HTTP or WebSocket provider for rapid development and cross-language app shells.

Provider requirements:

- Register/unregister lifecycle.
- Heartbeat and version negotiation.
- List browser surfaces.
- Read state.
- Perform actions.
- Evaluate scripts if supported.
- Inject scripts if supported.
- Emit page events if supported.
- Report geometry and screen mapping.
- Declare capabilities.
- Handle app relaunch without invalidating the whole BCU server.

Important constraint: BCU cannot inject JavaScript into an arbitrary third-party `WKWebView` from the outside. The owning app must cooperate by embedding the provider, exposing an XPC/loopback bridge, and calling `evaluateJavaScript`/`WKUserScript` on its own webviews. Once it does that, the BCU browser endpoints can treat it like any other browser target.

This is the path to "any `.app` with a `WKWebView` can conform/register something" without making phase 1 depend on cross-process complexity.

## Route Boundary

Keep browser routes and the original native routes separate.

Browser-specific routes:

```text
POST /v1/browser/get_state
POST /v1/browser/click
POST /v1/browser/evaluate_js
POST /v1/browser/inject_js
```

Original native routes should remain responsible for native macOS app/window control. Do not duplicate native focus, resize, or frame manipulation under `/v1/browser/*`.

Avoid adding browser-specific duplicates for window movement, focus, and resize. Browser responses should include enough host-window metadata for clients to call existing native routes when they need shell control.

## Execution And Parallelism

Browser actions should use the same execution principles as native actions:

- Serialize actions per tab or surface.
- Allow independent tabs/windows/apps to run in parallel.
- Keep JavaScript evaluation on the main actor where WebKit requires it.
- Make every action response include before/after state tokens.
- Return clear stale-target and stale-node errors.
- Avoid global locks except around shared cursor state and target registry mutation.

Injected scripts and external client apps should communicate through explicit request IDs and target IDs. BCU should provide the transport, not hidden shared app state.

## Validation Plan

Phase 1 validation:

- Create an owned browser window.
- Navigate to a static fixture page.
- Read DOM state.
- Click a button by selector, display index, and node ID.
- Type into an input.
- Scroll an element and the page.
- Run `evaluate_js`.
- Inject a persistent script and verify it runs after reload.
- Verify cursor animation moves to the DOM element using the existing cursor implementation.
- Verify native and browser targets both appear in target listing.

Cursor validation:

- Click by `dom_selector`, `browser_node_id`, `display_index`, and explicit browser coordinates.
- Confirm the cursor starts from its previous session position, follows the existing BCU animation curve/timing, and lands at the resolved DOM rect center.
- Confirm click/type/scroll do not introduce a second cursor renderer, alternate animation curve, or separate cursor daemon.
- Confirm actions can move the same cursor from a native app target to a browser DOM target and back.
- Confirm scroll targets use DOM element geometry and still show cursor movement to the intended scroll region.
- Confirm nested elements, transformed elements, scrolled containers, and high-DPI displays map to correct screen coordinates.
- Confirm stale DOM nodes fail cleanly and do not move/click a wrong element.
- Record before/after state tokens, cursor coordinates, resolved DOM rect, host window frame, and screenshot path in debug responses.

External client validation:

- Run a local Vite app.
- Have the Vite app create or discover a BCU browser target.
- Have the Vite app inject a page observer script.
- Have the observer emit events through BCU.
- Have the Vite app render its own UI from those events.
- Have the Vite app call BCU actions back against the target.

Parallel validation:

- Open two owned browser windows.
- Run actions against both concurrently.
- Confirm per-target ordering and no cross-target cursor/session corruption.

Security validation:

- Confirm injected scripts are scoped to declared target IDs or URL match patterns.
- Confirm localhost control clients require an explicit API token or development allowlist before remote-control routes are usable.
- Confirm event payload size limits and target scoping.
- Confirm active injected scripts are inspectable and removable.
- Confirm registered providers cannot claim surfaces or capabilities outside their own app identity.

UI validation:

- Launch the app through the signed app bundle path.
- Open a BCU-owned browser window and navigate using the native toolbar.
- Confirm the UI uses standard macOS toolbar/control behavior and does not introduce custom chrome that fights Liquid Glass/system material rendering.
- Confirm the `WKWebView` fills the window, resizes correctly, preserves focus, and does not obscure the cursor overlay.
- Confirm the window remains usable with keyboard focus, tab traversal where applicable, and standard close/minimize/resize behavior.

## Recommended First Implementation Slice

1. Add a browser target registry and one owned `WKWebView` host.
2. Add create/list/navigate/get-state/evaluate routes.
3. Add the core bootstrap script and interactables snapshot.
4. Add DOM click/type/scroll using existing cursor choreography.
5. Add `inject_js`, `remove_injected_js`, and `list_injected_js`.
6. Add a generic page event bridge.
7. Add one fixture page and route-level tests.
8. Add a tiny external Vite example app that calls BCU rather than living inside BCU.
9. Add a minimal registered `WKWebView` provider fixture app.
10. Only then generalize into tabs, grids, and broader external app providers.

## Important Design Principles

- Owned webviews first. Cross-process providers later.
- BCU is a control API, not an app framework.
- Browser endpoints should cover owned browser windows and cooperating registered `WKWebView` surfaces.
- Do not add a separate window surface unless existing native window APIs cannot cover a concrete requirement.
- Do not add generic target routes in this phase. Keep the browser API and original native API explicit.
- Reuse the existing cursor renderer, animation curves, session identity, timing controls, and debug model wherever possible.
- Low-level JavaScript evaluation and injection are primitives.
- Outside apps own sidepanels, workflows, business logic, and provider integrations.
- DOM state and native window state are different kinds of truth, but they should be presented through one target/session model.
- Cursor identity should be stable across native windows, browser tabs, and BCU-owned windows.
- Hot reload should be possible for external apps and injected scripts without rebuilding BCU.
- Security should focus on who can call BCU, which targets/scripts they can access, and what events can flow through the bridge.

## Open Questions

- Should persistent injected scripts be stored in the BCU config directory, passed by clients on startup, or both?
- Should the event stream be Server-Sent Events, WebSocket, or both?
- Should BCU expose an API token by default for localhost clients, or rely on loopback-only access during early development?
- How should a registered provider prove app identity and bind its advertised surfaces to its signed bundle/process?
- How much host-window metadata should browser targets expose so clients can reuse existing native window routes without ambiguity?
- What naming should replace "BrowserKit" if that creates confusion with platform-private framework names?
