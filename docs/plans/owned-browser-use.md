# Owned Browser Use Implementation Plan

## Goal

Add first-class browser use to BackgroundComputerUse without carrying over the Spotify product shell.

The API should be able to create and own web views, keep their login state, read DOM state, dispatch browser interactions in the background, and render the same visual cursor choreography already used for native computer-use actions. The first implementation should keep the browser surface simple and owned by this runtime. It should also establish a path for grid browser windows that can render multiple URLs, including a mix of local hosts and normal web pages, in one owned container. It should leave space for a future provider registry, but should not implement the full provider registry in the first pass.

This plan is intentionally split into two stages:

- Stage 1: clean owned-browser baseline with visible and non-visible modes designed into the contract from the start.
- Stage 1B: owned browser grid containers once the single-surface baseline is validated.
- Stage 2: richer background and registry work once the owned-browser baseline is validated.

## Starting Point

Current baseline branch:

- `main`

Previous experimental branch used as source material:

- `codex/spotify-background-computer-use`

The previous branch mixed four concepts:

- Generic browser-control routes and WKWebView ownership.
- Shared cursor mapping for DOM interactions.
- Registered-provider / external-surface plumbing.
- Spotify-specific app shell, injected Spotify chrome, and Codex sidebar.

The clean implementation should keep the first two, defer the third, and drop the fourth.

## Lessons From The Spotify Branch

### What Worked

The branch proved that an API-owned `WKWebView` can be exposed as a browser target and controlled through BCU routes.

Useful references:

- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserBootstrapScript.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserRouteService.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserCursorTargeting.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Contracts/BrowserContracts.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserWebCompatibility.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserMainActor.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserStateToken.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserSurfaceError.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserEventStore.swift`

The useful behavior from those files:

- Inject a bootstrap script at document start.
- Build a model-facing DOM snapshot from interactable elements.
- Resolve DOM targets by `display_index`, `browser_node_id`, or `dom_selector`.
- Dispatch browser clicks, typing, and scrolling through JavaScript.
- Convert DOM viewport coordinates into AppKit screen coordinates.
- Call the existing `CursorRuntime` paths so browser click/type/scroll animations match native computer-use animations.
- Return browser responses with state tokens, target metadata, DOM state, screenshots when available, cursor results, warnings, and notes.

### What Was Too Heavy

The branch also added product and registry pieces that should not be part of the clean baseline.

Do not carry over in Stage 1:

- `Sources/SpotifyWebViewApp`
- `External/CodexAppServerClient`
- Spotify-specific README content
- Spotify-specific scripts and launch flow
- Spotify AI sidebar
- Spotify chrome injection
- App-server model/thread integration
- Registered-provider bridge server
- External provider SDK

Defer or omit in Stage 1:

- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Provider/BCUProvider.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserProviderHTTPBridge.swift`
- `/v1/browser/providers/register`
- `/v1/browser/providers/unregister`
- Generic `/v1/events/*` control-plane routes unless page events become a direct Stage 1 need

### Key Design Correction

The experimental branch used visible app-owned browser windows and had provider registry concepts alongside owned browser targets. The clean design should separate these concerns:

- Owned browser targets are the Stage 1 product.
- Visible vs non-visible is a Stage 1 target mode.
- Browser grids are a Stage 1B product built on the same owned-target primitives, not a registry feature.
- Provider registry is Stage 2 infrastructure.
- Spotify or other app-specific web shells are separate product integrations built on top, not inside the baseline runtime.

## Non-Goals

Stage 1 should not:

- Automate arbitrary already-running browser tabs.
- Patch or inject into unrelated Electron/CEF apps.
- Implement a browser extension.
- Implement the external provider registry.
- Build an app-specific shell such as Spotify.
- Guarantee screenshots for non-visible web views.
- Steal focus from the current foreground app as part of browser creation.

## Stage 1: Owned Browser Baseline

### Stage 1 Outcome

The runtime can create and control its own browser surfaces through `/v1/browser/*`.

Required behavior:

- Browser targets are owned by BackgroundComputerUse.
- Browser targets can be created in visible or non-visible mode.
- Browser windows should not steal focus by default.
- Login state persists by `profileID`.
- The model can read DOM state even when screenshots are unavailable.
- Browser interactions use the same `cursor.id`, visual cursor session, and animation primitives as native app interactions.
- A single cursor can move between native windows and owned browser targets by reusing the same `cursor.id`.
- DOM dispatch is the default interaction path for browser actions.
- Native window movement routes can still move visible browser host windows by `hostWindow.windowID`.

### Stage 1 API Contract

Add browser route IDs and route descriptors:

- `POST /v1/browser/create_window`
- `POST /v1/browser/list_targets`
- `POST /v1/browser/get_state`
- `POST /v1/browser/navigate`
- `POST /v1/browser/evaluate_js`
- `POST /v1/browser/inject_js`
- `POST /v1/browser/remove_injected_js`
- `POST /v1/browser/list_injected_js`
- `POST /v1/browser/click`
- `POST /v1/browser/type_text`
- `POST /v1/browser/scroll`
- `POST /v1/browser/reload`
- `POST /v1/browser/close`

Do not add provider routes in Stage 1.

#### Create Browser

Request shape:

```json
{
  "url": "https://example.com",
  "title": "Example",
  "profileID": "default",
  "visibility": "visible",
  "x": 120,
  "y": 120,
  "width": 1120,
  "height": 760,
  "userAgent": "optional custom user agent",
  "imageMode": "omit",
  "debug": false
}
```

Fields:

- `url`: optional initial URL. If omitted, load a small built-in blank page.
- `title`: optional window title.
- `profileID`: stable login-state bucket. Default `default`.
- `visibility`: `visible` or `non_visible`. Default `visible`.
- `x`, `y`, `width`, `height`: requested visible window geometry.
- `userAgent`: optional override. Default desktop Safari-compatible user agent.
- `imageMode`: `omit`, `path`, or `base64`, same pattern as native state routes.
- `debug`: include timing and lower-level diagnostics.

Response shape should include:

- `target`: browser tab target summary.
- `state`: initial state.
- `notes`: include whether the target is visible or non-visible and whether screenshots are expected.

#### Visibility Modes

The contract should support visibility from the start even if the implementation starts conservative.

`visible` means:

- Create an `NSWindow` with a `WKWebView`.
- Order it without stealing focus.
- Keep it screenshot-capable when macOS allows the capture.
- Include `hostWindow` metadata.
- Support native window motion routes against `hostWindow.windowID`.

`non_visible` means:

- Create a `WKWebView` that is not presented as a normal visible app window.
- Do not promise screenshots.
- DOM state, JS evaluation, JS injection, navigation, click, type, scroll, reload, and close should still work where WebKit allows.
- `hostWindow` may be null or may point to an offscreen/hidden host if required by WebKit.
- `browser/get_state` should return DOM state and an explicit screenshot warning when `imageMode` requests a screenshot but no reliable rendered image is available.

Fallback rule:

- If `non_visible` cannot initialize or cannot reliably load pages, return a clear unsupported response or create a non-activating visible window only when the request explicitly allows fallback.

Optional create field:

```json
{
  "visibility": "non_visible",
  "allowVisibleFallback": false
}
```

If `allowVisibleFallback` is false and non-visible mode is not available, the route should fail honestly.

### Focus And Activation Requirements

Default browser creation must not steal focus.

Implementation details:

- Do not expose or honor an activation path on Stage 1 browser routes.
- Do not call `NSApplication.shared.activate(ignoringOtherApps: true)` from browser route handling.
- For visible windows, prefer ordering the window without making the app active.
- Avoid `makeKeyAndOrderFront` in browser route handling.
- Use a visible-but-background presentation path such as `orderFrontRegardless` or a controlled equivalent, then validate real behavior.
- If WebKit requires a key window for a specific action, the browser route should report that requirement instead of silently focusing the app.

Validation must explicitly check:

- Foreground app before browser creation.
- Foreground app after browser creation.
- Foreground app after browser click/type/scroll.
- Whether the browser window became key or active.

The desired baseline is that the current user app remains foreground while the model interacts through JS dispatch.

### Login State And Profiles

Stage 1 should include profile persistence, not a single global browser jar.

Use a `BrowserProfileStore`:

- Persist `profileID -> UUID` under app support.
- Use `WKWebsiteDataStore.dataStore(forIdentifier:)` on macOS 14+ for persistent profiles.
- Use `WKWebsiteDataStore.nonPersistent()` for explicit ephemeral profiles.
- Validate `profileID` as a short filesystem-safe identifier.
- Default `profileID` to `default`.

Suggested files:

- `Sources/BackgroundComputerUse/Browser/BrowserProfileStore.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserWebEnvironment.swift`

Profile request fields:

```json
{
  "profileID": "gmail-work",
  "ephemeral": false
}
```

Stage 1 does not need profile management routes, but the code should be structured so Stage 2 can add:

- `POST /v1/browser/profiles/list`
- `POST /v1/browser/profiles/delete`
- `POST /v1/browser/profiles/clear_data`

### Target Model

Use a target model that can later support a registry, but only implement owned targets in Stage 1.

Target kinds:

- `owned_browser_window`
- `owned_browser_tab`
- `owned_browser_grid`
- `owned_browser_grid_cell`

Defer:

- `registered_browser_surface`

Target IDs:

- Window: `bw_<stable-ish random id>`
- Tab: `bt_<stable-ish random id>`
- Grid container: `bg_<stable-ish random id>`
- Grid cell: `bc_<stable-ish random id>`

Target summary:

```json
{
  "targetID": "bt_abc123",
  "kind": "owned_browser_tab",
  "ownerApp": "BackgroundComputerUse",
  "title": "Example",
  "url": "https://example.com",
  "isLoading": false,
  "parentTargetID": "bw_def456",
  "visibility": "visible",
  "profileID": "default",
  "hostWindow": {
    "bundleID": "xyz.dubdub.backgroundcomputeruse",
    "pid": 123,
    "windowNumber": 42,
    "windowID": "..."
  },
  "capabilities": {
    "readDom": true,
    "evaluateJavaScript": true,
    "injectJavaScript": true,
    "dispatchDomEvents": true,
    "screenshot": true,
    "nativeClickFallback": false,
    "hostWindowMetadata": true
  }
}
```

For Stage 1, only `owned_browser_window` and `owned_browser_tab` need to be implemented. `owned_browser_grid` and `owned_browser_grid_cell` should be reserved in contracts only if that does not create unnecessary implementation churn. If reserving them complicates Stage 1, add them in Stage 1B with a migration-safe contract version bump.

Grid cells should behave like normal browser targets. The grid container is layout metadata and host-window ownership; actions should target cells unless the route is explicitly about moving, resizing, closing, or reading the full container.

### Cursor Continuity

This is a hard requirement.

Browser sessions must use the same cursor system as native computer-use sessions:

- Same `CursorRequestDTO`.
- Same `CursorRuntime.resolve(requested:)`.
- Same cursor session lookup by `cursor.id`.
- Same visual overlay rendering.
- Same motion pacing and animation primitives.
- Same pressed/released states for click.
- Same scroll animation for scroll.
- Same type animation for type.

The model should be able to do:

1. `POST /v1/click` against a native app with `cursor.id = "agent-1"`.
2. `POST /v1/browser/click` against an owned browser with `cursor.id = "agent-1"`.
3. `POST /v1/scroll` or `POST /v1/browser/scroll` with the same cursor.

Expected behavior:

- One cursor moves continuously across both surfaces.
- Browser actions do not create a separate browser-only cursor.
- Browser action responses include the same `cursor` response shape as native action responses.
- Cursor screenshots include the overlay when a visible browser window is screenshot-capable.

Implementation references:

- Baseline native cursor: `Sources/BackgroundComputerUse/Cursor/AXCursorTargeting.swift`
- Baseline cursor runtime: `Sources/BackgroundComputerUse/Cursor/CursorCoordinator.swift`
- Previous browser cursor bridge: `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserCursorTargeting.swift`
- Previous browser route usage: `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserRouteService.swift`

Implementation approach:

- Add `BrowserCursorTargeting`.
- It should call `CursorRuntime.approach`, `CursorRuntime.prepareScroll`, `CursorRuntime.prepareTypeText`, `CursorRuntime.setPressed`, `CursorRuntime.finishClick`, `CursorRuntime.finishScroll`, and `CursorRuntime.finishTypeText`.
- It should never own cursor state outside `CursorRuntime`.
- It should accept the browser host `windowNumber` when visible.
- For non-visible surfaces, cursor behavior should be explicit:
  - If no host window exists, return `movement: "not_attempted"` with a warning explaining that non-visible targets do not have screen coordinates.
  - Still dispatch the DOM action if the target resolves.
  - Preserve `cursor.session` so the same cursor ID remains the active logical session.

### Browser DOM State

Port and simplify `BrowserBootstrapScript`.

Required DOM snapshot fields:

- viewport size
- scroll position
- device scale factor
- focused element
- interactable list
- node ID
- display index
- tag name
- role
- accessible name
- visible text
- value preview
- selector candidates
- viewport rect
- viewport center
- AppKit rect when visible
- AppKit center when visible
- visibility/enabled/editable booleans
- optional raw text
- node count

Targeting:

- `display_index`
- `browser_node_id`
- `dom_selector`

The DOM state should be useful without a screenshot. This matters for non-visible mode and for pages where screenshots are unavailable.

### Browser Actions

#### Click

Default flow:

1. Read pre-action browser state.
2. Validate supplied `stateToken` when present.
3. Resolve target to DOM element or use supplied viewport point.
4. Map viewport point to AppKit point when visible.
5. Animate cursor when visible and coordinates are available.
6. Dispatch DOM click through JS.
7. Finish cursor click animation.
8. Read post-action browser state.
9. Return action result, cursor result, pre/post state, warnings, and timing.

No physical pointer movement is needed for the DOM dispatch path.

#### Type Text

Default flow:

1. Resolve target if provided.
2. Animate cursor to target when visible.
3. Focus the target through JS.
4. Set or append text through JS.
5. Dispatch input/change events.
6. Finish type animation.
7. Read post-action state.

Request should include:

- `append`: default false or align with existing semantics after review.
- `cursor`: same shape as native actions.

#### Scroll

Default flow:

1. Resolve target or use document scrolling.
2. Animate cursor with the same scroll choreography used by native `scroll`.
3. Dispatch JS scroll.
4. Finish scroll animation.
5. Read post-action state.

### Screenshots

Stage 1 screenshot behavior should be honest and mode-aware.

Visible targets:

- Use the existing `ScreenshotCaptureService.capture`.
- Include cursor overlay when requested and available.
- Return warnings if capture fails.

Non-visible targets:

- Do not promise screenshot output.
- `imageMode: "omit"` should be the default.
- If `imageMode` is `path` or `base64`, attempt only if a reliable rendering path exists.
- If no reliable rendering path exists, return a warning and `screenshot: null` or an omitted image payload per existing contract style.

Stage 1 validation should not block on non-visible screenshot support. DOM state is enough for non-visible v1.

### File-Level Implementation Plan

Port from the previous branch, but simplify while porting.

New files:

- `Sources/BackgroundComputerUse/Browser/BrowserBootstrapScript.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserCursorTargeting.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserMainActor.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserProfileStore.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserRouteService.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserStateToken.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceError.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserWebCompatibility.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserWebEnvironment.swift`
- `Sources/BackgroundComputerUse/Contracts/BrowserContracts.swift`

Modify:

- `Sources/BackgroundComputerUse/API/APIDocumentation.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/Router.swift`
- `Sources/BackgroundComputerUse/App/BackgroundComputerUseRuntime.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift`
- `Sources/BackgroundComputerUse/Actions/WindowMotion/SetWindowFrameRouteService.swift`
- `Sources/BackgroundComputerUse/Shared/JSONSupport.swift` if `JSONValueDTO` support is needed.
- `Tests/BackgroundComputerUseTests/RuntimeFacadePublicAPITests.swift`
- `README.md`

Do not add:

- `Sources/SpotifyWebViewApp`
- `External/CodexAppServerClient`
- `Sources/BackgroundComputerUse/Provider`
- Provider registration routes

### Runtime Wiring

Add `BrowserRouteService` to `RuntimeServices`.

Native route execution lanes should be reused:

- `browser/list_targets`: shared read lane.
- `browser/create_window`: shared write or shared route lane.
- `browser/get_state`: browser read lane keyed by browser target ID.
- `browser/click`, `browser/type_text`, `browser/scroll`, `browser/navigate`, `browser/reload`, `browser/close`: browser write lane keyed by browser target ID.

If the current `RuntimeCoordinator` only has window/shared target summaries, add a browser target summary kind instead of overloading window IDs.

### Stage 1 Tests

Unit/API tests:

- Browser DTOs are constructible from public import.
- `BrowserCreateWindowRequest` validates visibility values.
- `profileID` validation accepts normal IDs and rejects empty/path-like IDs.
- Browser target request decoding supports integer and string `display_index`.
- Route registry includes all Stage 1 browser routes.
- Provider routes are absent from Stage 1.
- `BrowserCursorTargeting` returns a normal cursor session when visual cursor is disabled.
- Non-visible cursor behavior returns a warning rather than crashing when no AppKit point exists.

Runtime smoke tests where feasible:

- Create visible browser.
- Confirm target appears in `browser/list_targets`.
- Confirm `browser/get_state` returns DOM state.
- Evaluate `document.title`.
- Inject simple JS and list/remove it.
- Click a known button on a local fixture page.
- Type into a known input on a local fixture page.
- Scroll a known scroll container on a local fixture page.
- Create non-visible browser.
- Confirm non-visible `browser/get_state` returns DOM state with `imageMode: "omit"`.
- Confirm non-visible `imageMode: "path"` returns an explicit warning if screenshot is unavailable.

Cursor continuity tests/manual validation:

- Use one `cursor.id` for a native app click.
- Use the same `cursor.id` for visible browser click.
- Use the same `cursor.id` for browser scroll.
- Use the same `cursor.id` for native scroll.
- Confirm the cursor response `session.id` is identical across responses.
- Confirm visible behavior shows one cursor moving between surfaces.

Focus validation:

- Record frontmost app before `browser/create_window`.
- Create visible browser.
- Record frontmost app after create.
- Run `browser/click`, `browser/type_text`, `browser/scroll`.
- Record frontmost app after each action.
- Expected: frontmost app remains unchanged.

Build validation:

```bash
swift build
swift test
./script/start.sh
```

Manual API validation:

```bash
BASE="$(python3 - <<'PY'
import json, os
path = os.path.join(os.environ["TMPDIR"], "background-computer-use", "runtime-manifest.json")
print(json.load(open(path))["baseURL"])
PY
)"

curl -s "$BASE/v1/routes" | python3 -m json.tool
curl -s -X POST "$BASE/v1/browser/create_window" \
  -H 'content-type: application/json' \
  -d '{"url":"https://example.com","profileID":"default","visibility":"visible","imageMode":"path"}' \
  | python3 -m json.tool
```

### Stage 1 Acceptance Criteria

Stage 1 is complete when:

- The repo builds from `main` plus the browser changes.
- Existing native computer-use routes still pass tests.
- Browser routes appear in `/v1/routes`.
- Browser targets can be created, listed, read, navigated, evaluated, clicked, typed into, scrolled, reloaded, and closed.
- Visible browser creation defaults to no focus steal.
- Non-visible browser creation is represented in the API and works for DOM state or fails honestly with a clear unsupported reason.
- Login state persists across browser close/reopen for the same `profileID`.
- A different `profileID` does not share that login state.
- Browser action responses include cursor session data.
- Reusing the same `cursor.id` across native and browser routes reuses the same visual cursor session.
- Browser click, type, and scroll animations use the same animation primitives as native click, type, and scroll.
- No Spotify app code, Spotify scripts, external Codex app-server client, or provider SDK is included.

## Stage 1B: Browser Grid Containers

Stage 1B is a planned capability, not an optional someday idea. It should start after Stage 1 proves one owned browser surface end to end.

### Stage 1B Outcome

The runtime can create one owned browser container window that hosts multiple browser cells in a grid. Each cell can load a different URL and can use its own profile. This should support practical workflows such as:

- `http://localhost:3000` beside `http://localhost:5173`.
- A local app beside production documentation.
- A logged-in web app beside an admin dashboard.
- Two independent browser sessions with different profiles in one visible non-activating container.
- A mixed visible/non-visible future where cells can be DOM-readable even when a screenshot is not available.

The model should continue to interact with individual cell targets through the same browser action routes.

### Grid API

Add after Stage 1:

- `POST /v1/browser/create_grid`
- `POST /v1/browser/update_grid`
- `POST /v1/browser/get_grid_state`

Keep existing action routes cell-targeted:

- `POST /v1/browser/get_state`
- `POST /v1/browser/navigate`
- `POST /v1/browser/evaluate_js`
- `POST /v1/browser/click`
- `POST /v1/browser/type_text`
- `POST /v1/browser/scroll`
- `POST /v1/browser/reload`
- `POST /v1/browser/close`

`browser/close` should close a single cell when given a cell target ID and close the entire grid when given the grid/container target ID.

Create request:

```json
{
  "title": "Dev Grid",
  "profileID": "default",
  "visibility": "visible",
  "layout": {
    "kind": "grid",
    "columns": 2,
    "rows": 1,
    "gap": 8
  },
  "cells": [
    {
      "id": "app",
      "url": "http://localhost:3000",
      "profileID": "dev-local"
    },
    {
      "id": "docs",
      "url": "https://developer.apple.com/documentation/webkit",
      "profileID": "default"
    }
  ],
  "width": 1440,
  "height": 900,
  "imageMode": "omit"
}
```

Response:

```json
{
  "targetID": "bg_abc123",
  "kind": "owned_browser_grid",
  "title": "Dev Grid",
  "visibility": "visible",
  "hostWindow": { "windowID": "..." },
  "cells": [
    {
      "targetID": "bc_app123",
      "kind": "owned_browser_grid_cell",
      "cellID": "app",
      "url": "http://localhost:3000",
      "profileID": "dev-local",
      "frameInContainer": { "x": 0, "y": 0, "width": 716, "height": 900 }
    },
    {
      "targetID": "bc_docs456",
      "kind": "owned_browser_grid_cell",
      "cellID": "docs",
      "url": "https://developer.apple.com/documentation/webkit",
      "profileID": "default",
      "frameInContainer": { "x": 724, "y": 0, "width": 716, "height": 900 }
    }
  ]
}
```

### Grid Layout Model

Start with a simple fixed grid:

- `rows`
- `columns`
- `gap`
- equal-size cells

Do not start with arbitrary split panes, draggable dividers, tabs, nested grids, or saved workspace layouts. Those can be added after the fixed grid is stable.

The layout engine should produce stable cell frames:

- container AppKit frame
- cell frame in container coordinates
- cell frame in AppKit screen coordinates
- viewport-to-AppKit transform per cell

### Grid State

`browser/get_grid_state` should return:

- grid target summary
- host window metadata
- layout definition
- computed cell frames
- cell target summaries
- optional full-container screenshot when visible and screenshot-capable
- warnings for cells whose state cannot be read

Individual `browser/get_state` calls against a cell should return normal browser DOM state for that cell.

The model should be able to reason about the grid at two levels:

- container state for layout and screenshot overview
- cell state for DOM and actions

### Grid Cursor Behavior

Cursor behavior is still the same cursor behavior.

For a visible grid:

1. Resolve the cell target.
2. Resolve the DOM target inside that cell.
3. Convert DOM viewport point to cell-local point.
4. Convert cell-local point to AppKit screen point using the cell frame inside the grid container.
5. Call the same `BrowserCursorTargeting` and `CursorRuntime` methods used by single browser targets.

Expected behavior:

- One cursor session can move from a native app to grid cell A.
- The same cursor session can then move to grid cell B.
- The same cursor session can then move back to a normal native window.
- Click, type, and scroll animations must be indistinguishable from Stage 1 browser and native routes.

For a non-visible grid:

- DOM dispatch should still target individual cells when WebKit supports it.
- Cursor response should preserve `cursor.session`.
- If no AppKit point exists, return `movement: "not_attempted"` with a clear warning.

### Grid Profiles

Each cell can specify `profileID`.

Rules:

- If the cell omits `profileID`, inherit the grid-level `profileID`.
- Cells with the same profile share cookies/login state.
- Cells with different profiles do not share cookies/login state.
- Localhost cells should be allowed to use their own profile so local dev sessions do not pollute default browsing state.

### Grid Implementation Files

Add after Stage 1:

- `Sources/BackgroundComputerUse/Browser/BrowserGridLayout.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserGridSurface.swift`
- `Sources/BackgroundComputerUse/Browser/BrowserGridRouteService.swift` if keeping grid code separate makes `BrowserRouteService` easier to read.

Modify:

- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift`
- `Sources/BackgroundComputerUse/Contracts/BrowserContracts.swift`
- `Sources/BackgroundComputerUse/API/RouteRegistry.swift`
- `Sources/BackgroundComputerUse/API/Router.swift`
- `Sources/BackgroundComputerUse/Runtime/RuntimeServices.swift`
- `Sources/BackgroundComputerUse/App/BackgroundComputerUseRuntime.swift`

Do not duplicate browser action logic for grids. Shared action code should operate on a resolved browser surface handle that can be either a single browser tab or a grid cell.

### Grid Validation

Automated and manual validation should cover:

- Create a two-cell visible grid.
- Confirm foreground app does not change.
- Load `http://localhost:3000` in one cell and `https://example.com` in the other.
- Confirm each cell appears in `browser/list_targets`.
- Confirm `browser/get_grid_state` returns both cells and stable frames.
- Confirm `browser/get_state` against each cell returns that cell's DOM state.
- Click an element in cell A with `cursor.id = "agent-1"`.
- Click an element in cell B with the same `cursor.id`.
- Scroll cell A and then a native app with the same `cursor.id`.
- Confirm the cursor moves continuously between cells and native windows.
- Confirm each cell can use a separate `profileID`.
- Confirm closing one cell does not close the whole grid unless the grid target ID is used.
- Confirm closing the grid closes all child cells.

### Stage 1B Acceptance Criteria

Stage 1B is complete when:

- Fixed grid containers can be created and listed.
- Cell targets are individually addressable by browser action routes.
- Visible grid creation defaults to no focus steal.
- Grid screenshots are best-effort and honest.
- Cell DOM state works independently.
- Per-cell profiles work.
- Cursor animations remain shared with native and single-browser routes.
- The implementation does not introduce provider registry code.

## Stage 2: Rich Background Browser And Registry Path

Stage 2 starts after the owned-browser and browser-grid baselines work.

### Stage 2 Goals

- Improve non-visible rendering and screenshots.
- Add profile management routes.
- Add browser lifecycle management.
- Add richer grid lifecycle and saved layout behavior if fixed grids prove useful.
- Reintroduce a minimal registry abstraction only when owned-browser targets prove the target model.
- Optionally add external provider support for app-owned webviews.

### Non-Visible Rendering Work

Investigate:

- Whether hidden or offscreen `WKWebView` instances reliably render.
- Whether an offscreen `NSWindow` outside visible screen bounds can support snapshots without user disruption.
- Whether `WKWebView.takeSnapshot` is enough for model-facing screenshots.
- Whether ScreenCaptureKit/CGWindow capture can capture visible-but-background windows without activation.

Possible outcomes:

- Keep non-visible as DOM-only.
- Add best-effort snapshot through `WKWebView.takeSnapshot`.
- Use visible non-activating windows as the reliable screenshot path.
- Add `visibility: "offscreen_visible"` if it proves useful and honest.

### Profile Management Routes

Add:

- `POST /v1/browser/profiles/list`
- `POST /v1/browser/profiles/delete`
- `POST /v1/browser/profiles/clear_data`

Validation:

- Clearing one profile does not clear another.
- Deleting an active profile is rejected or closes dependent targets first.
- Ephemeral profile state disappears after target close/runtime restart.

### Browser Lifecycle

Add target lifecycle controls:

- Close all targets for profile.
- Reopen last URL for profile.
- Optional target labels.
- Optional default viewport presets.
- Optional target lease/TTL for cleanup.

### Registry Reintroduction

Only add registry after the owned-browser target contract is stable.

Introduce an internal abstraction:

```swift
protocol BrowserTargetStore {
    func listTargets() -> [BrowserTargetSummaryDTO]
    func resolve(targetID: String) throws -> BrowserSurfaceHandle
}
```

Stage 1 implementation:

- `OwnedBrowserTargetStore`

Stage 2 possible implementation:

- `RegisteredProviderTargetStore`

Do not let registry concepts leak into Stage 1 route behavior. The model should not need to know whether a target is owned or registered until registered targets actually exist.

### External Provider Support

If needed, revisit:

- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Provider/BCUProvider.swift`
- `codex/spotify-background-computer-use:Sources/BackgroundComputerUse/Browser/BrowserProviderHTTPBridge.swift`

Design constraints:

- External providers must advertise explicit capabilities.
- JS execution must be opt-in per provider.
- Provider targets should share browser request/response shapes where possible.
- Provider routes must not weaken the security posture of the local loopback API.

### Security And Permissions

Browser JS execution is stronger than native input because it runs inside authenticated web sessions.

Stage 2 should add:

- Optional route-level safety policy for `evaluate_js` and `inject_js`.
- Allowlist/denylist hooks by origin or profile.
- Audit logs for JS execution.
- Profile isolation guidance.
- Clear route docs warning that browser JS acts inside logged-in sessions.

## Implementation Sequence

Recommended order:

1. Create implementation branch from `main`.
2. Port `BrowserContracts` and compile DTOs.
3. Add route IDs and route descriptors, but initially return `not_implemented`.
4. Add `BrowserProfileStore`.
5. Add `BrowserWebEnvironment`.
6. Add `BrowserBootstrapScript`.
7. Add `BrowserSurfaceRegistry` with owned targets only.
8. Add visible target creation with no activation path.
9. Add non-visible target creation as DOM-first.
10. Add `browser/list_targets`.
11. Add `browser/get_state`.
12. Add `browser/navigate`, `browser/reload`, and `browser/close`.
13. Add `browser/evaluate_js` and script injection routes.
14. Add `BrowserCursorTargeting`.
15. Add `browser/click`.
16. Add `browser/type_text`.
17. Add `browser/scroll`.
18. Wire direct Swift facade methods.
19. Add route docs and README examples.
20. Add focused tests.
21. Run build and test validation.
22. Run manual focus/cursor/login validation.
23. Start Stage 1B only after Stage 1 validation passes.
24. Add grid contracts and route descriptors.
25. Add fixed grid layout computation.
26. Add grid container and cell target registration.
27. Add `browser/create_grid`, `browser/update_grid`, and `browser/get_grid_state`.
28. Reuse single-browser action logic for grid cells.
29. Add grid cursor continuity tests.
30. Run manual grid focus/cursor/profile validation.

## Open Questions To Resolve During Implementation

- Which non-activating `NSWindow` ordering method works best for visible background browser windows on the current macOS version?
- Does a non-visible `WKWebView` reliably load and execute JavaScript without being attached to a visible window?
- Is `WKWebView.takeSnapshot` reliable enough for non-visible or offscreen screenshots?
- Should `type_text` append by default or replace by default for browser inputs?
- Should `evaluate_js` be enabled by default for every owned profile, or should it require a runtime option?
- Should browser-created windows appear in `list_windows`, or only through `browser/list_targets` with `hostWindow` metadata?
- Should grid cells be called tabs, cells, or surfaces in public API fields?
- Should `browser/create_grid` support local file URLs, or only HTTP/HTTPS/localhost at first?
- Should grid layout updates preserve cell target IDs when rows/columns change?
- Should a grid cell be closable independently, or should cells be replaceable but the grid shape remain stable?

## Validation Matrix

| Scenario | Stage | Required Result |
| --- | --- | --- |
| Native routes after browser changes | 1 | Existing tests pass and route behavior is unchanged |
| Visible browser create | 1 | Browser target exists and current foreground app is unchanged |
| Visible browser DOM read | 1 | `browser/get_state` returns interactables and optional screenshot |
| Non-visible browser DOM read | 1 | DOM state works or fails with clear unsupported reason |
| Non-visible screenshot request | 1 | Screenshot returned only if reliable; otherwise explicit warning |
| Same profile reopen | 1 | Login/session state persists |
| Different profile reopen | 1 | Login/session state is isolated |
| Browser click with cursor | 1 | DOM action dispatches and cursor click animation is reused |
| Browser type with cursor | 1 | DOM text changes and cursor type animation is reused |
| Browser scroll with cursor | 1 | DOM scroll changes and cursor scroll animation is reused |
| Native-to-browser cursor reuse | 1 | Same `cursor.id` produces one continuous cursor session |
| Visible two-cell grid | 1B | Grid target and cell targets exist and current foreground app is unchanged |
| Localhost plus external URL grid | 1B | One grid can host local and remote URLs side by side |
| Per-cell DOM state | 1B | `browser/get_state` returns the correct DOM for each cell target |
| Per-cell cursor movement | 1B | Same `cursor.id` moves continuously between cells |
| Per-cell profile isolation | 1B | Grid cells can share or isolate login state by `profileID` |
| Grid close semantics | 1B | Closing a cell differs from closing the whole grid |
| Provider registry | 2 | Added only after owned target contract is stable |
| External app-owned webviews | 2 | Capability-advertised provider targets share browser contracts |

## Branch Hygiene

Keep the implementation branch small and reviewable:

- Commit Stage 1 browser baseline separately from docs updates.
- Do not include `.bcu` screenshots/logs.
- Do not include Spotify app files.
- Do not include `External/CodexAppServerClient`.
- Keep provider registry files out until Stage 2.
- Run `git diff --check`, `swift build`, and `swift test` before promotion.
