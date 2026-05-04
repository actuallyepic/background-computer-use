# Owned Browser Use Review Issues

Branch: `codex/owned-browser-use-plan`

Date: 2026-05-04

This file captures the current code-review findings for the owned browser use implementation. The branch is directionally organized around generic browser primitives, reusable cursor behavior, persistent profiles, and deferred provider/registry complexity, but these issues should be addressed before merging.

## Summary

- Do not merge as-is.
- The core architecture is promising: browser surfaces are separated from product-specific behavior, routes are in the public catalog, and the visual cursor is reused.
- The remaining blockers are mostly around API contract honesty, background window behavior, popup/grid semantics, and verifier correctness.

## Findings

### 1. [P1] Avoid `orderFrontRegardless` for background browsers

Files:

- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift:449-450`
- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift:759-760`

Visible grid creation and standalone browser window creation call `window.orderFrontRegardless()`. That can force owned browser windows in front of the user current app even though the route catalog advertises `focusStealPolicy=forbidden`, and even though the intended contract is background-safe browser creation.

Expected fix:

- Replace `orderFrontRegardless()` with a non-activating/background-safe presentation path.
- Add a regression check that captures the foreground app or key window before and after browser creation.
- Keep the route catalog focus-steal contract aligned with actual runtime behavior.

Validation target:

- Creating a visible browser window or visible grid does not activate the BCU app and does not steal focus from the current foreground app.

### 2. [P1] Keep click verification tied to the dispatched surface

Files:

- `Sources/BackgroundComputerUse/Browser/BrowserRouteService.swift:646-651`
- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift:305-308`

Post-click verification switches to whichever tab is active after dispatch by calling `surfaceForPostActionState(startingFrom:)`. This is useful for popup discovery, but it conflates popup or tab activation with verifying the surface that actually received the action. A click can be classified from a state-token change on a newly active surface rather than from the dispatched surface.

Expected fix:

- Keep action verification anchored to the original dispatch surface.
- Separately report popup or newly active target evidence in response metadata.
- Treat popup creation as an explicit secondary success signal, not as a substitute for verifying the dispatched surface.

Validation target:

- Clicking a link that opens a popup reports the original surface post-state and separately reports the popup target.
- Clicking a normal button verifies against the same surface that received the dispatch.

### 3. [P2] Reject ambiguous browser click requests

File:

- `Sources/BackgroundComputerUse/Contracts/BrowserContracts.swift:710-743`

`BrowserClickRequest` uses synthesized `Codable`, so HTTP clients can send both `target` and `x`/`y` even though the catalog says coordinates must be supplied without `target`. The route takes the `target` branch and silently ignores coordinates, which can click something different than the caller intended.

Expected fix:

- Add a custom decoder for `BrowserClickRequest`.
- Require exactly one targeting mode:
  - `target`
  - complete `x` and `y`
- Reject partial coordinate requests and target-plus-coordinate requests.

Validation target:

- `{ "target": ..., "x": 10, "y": 20 }` returns `invalid_request`.
- `{ "x": 10 }` returns `invalid_request`.
- Target-only and coordinate-only requests still decode and execute.

### 4. [P2] Do not clamp invalid browser display indexes

File:

- `Sources/BackgroundComputerUse/Contracts/BrowserContracts.swift:274-276`

The public browser target factory maps `displayIndex(-1)` to `0`, while HTTP decoding rejects negative display indexes. SDK callers can accidentally target the first interactable instead of getting the same validation failure as HTTP clients.

Expected fix:

- Make the normal public factory validate like HTTP decoding.
- Prefer a throwing factory, or add a validated replacement and stop exposing clamping as the normal path.
- Update tests so public SDK construction and HTTP decoding have matching semantics.

Validation target:

- Public API callers cannot create a negative browser display-index target without an explicit validation failure.

### 5. [P2] Define popup behavior for grid cells

Files:

- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift:779-780`
- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift:1301-1307`

Popup creation currently requires an opener `tabHost`, but grid cells do not have one. Any `target=_blank` or OAuth-style `window.open` from a grid cell will fail instead of opening in a tab or an explicit fallback surface.

Expected fix:

- Define an explicit grid-cell popup policy.
- Either support grid-cell popups as tabs in an associated owned browser window, or route popup navigations into the same cell with documented behavior.
- Emit response/event metadata that makes popup behavior clear to clients.

Validation target:

- A grid cell running `window.open(...)` has deterministic behavior.
- OAuth-style popups from grid cells no longer silently fail.

### 6. [P2] Broaden click effect verification

Files:

- `Sources/BackgroundComputerUse/Browser/BrowserRouteService.swift:822-829`
- `Sources/BackgroundComputerUse/Browser/BrowserStateToken.swift:8-29`
- `Sources/BackgroundComputerUse/Browser/BrowserBootstrapScript.swift:288`

Click success is currently based on `preStateToken != postStateToken`. The token excludes control values, checked state, ARIA state, and other common click effects. Successful clicks on checkboxes, toggles, value-only controls, or idempotent buttons can return `effect_not_verified`.

Expected fix:

- Include relevant control state in browser snapshots and state tokens.
- Or use click-specific dispatch result fields as additional verification evidence.
- Keep the verifier conservative, but avoid false negatives for common control effects.

Validation target:

- Checkbox/toggle clicks can verify when checked or ARIA state changes.
- Plain buttons that mutate visible/interactable DOM still verify.
- Truly no-op clicks continue to return `effect_not_verified`.

### 7. [P3] Close or reject the final grid cell close

Files:

- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift:345-349`
- `Sources/BackgroundComputerUse/Browser/BrowserSurfaceRegistry.swift:548-555`

Closing a grid cell unregisters that cell, but closing the last cell leaves the grid window and grid target alive with zero cells. That creates an empty grid target in `browser/list_targets` and `browser/get_grid_state`.

Expected fix:

- Close and unregister the grid when the final cell closes, or reject closing the final cell and require clients to close the grid target.
- Add a lifecycle test for last-cell close behavior.

Validation target:

- After the final grid cell is closed, the grid target is either gone or the close request is rejected with a clear error.

### 8. [P3] Do not animate typed text after dispatch failure

File:

- `Sources/BackgroundComputerUse/Browser/BrowserRouteService.swift:372-378`

The defer cleanup calls `finishTypeText` with the requested text even if `dispatchTypeText` throws before delivery. That prevents a stuck cursor, but it can show successful typing effects on a failed transport.

Expected fix:

- Split failure cleanup from success finishing.
- On dispatch failure, release or reset the cursor without rendering typed-text completion effects.

Validation target:

- Failed browser typing does not leave the cursor stuck.
- Failed browser typing also does not show successful typed-text choreography.

## Validation Already Run

- `swift test`: passed all 31 tests.
- `git diff --check`: passed.

## Test Coverage Gaps

- Browser window and grid creation preserving foreground focus.
- Popup creation and tab behavior from standalone browser tabs.
- Popup behavior from grid cells.
- Ambiguous click request decoding.
- Public SDK validation parity for browser target factories.
- Click verification for checkboxes, toggles, ARIA controls, and value-only effects.
- Final grid-cell close lifecycle.
- Cursor cleanup behavior when browser dispatch throws.
