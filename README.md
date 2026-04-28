# Spotify Background Computer Use

A native macOS Spotify webview with an embedded Spotify AI sidebar. The sidebar is powered by the Codex app-server, defaults to GPT-5.5 on the fast service tier, and can use the bundled Background Computer Use control plane to inspect and act inside the Spotify web app.

This branch is focused on the Spotify integration. The lower-level BackgroundComputerUse package remains in the repo because the Spotify app uses it for window state, browser-surface registration, and action dispatch.

## What Is Included

- `SpotifyWebViewApp`: a signed macOS app that hosts `open.spotify.com` in a WKWebView.
- A native Spotify-styled chat sidebar for "Spotify AI".
- Codex app-server integration using `External/CodexAppServerClient`.
- Background Computer Use runtime support for browser and desktop actions.
- Browser-surface registration so agents can call BCU routes against the Spotify webview.

## Requirements

- macOS 14 or newer.
- Swift 6.2 toolchain.
- `codex` CLI 0.125.0 or newer on `PATH`.
- Spotify account access in the hosted web player.
- macOS Accessibility permission for the BCU runtime.
- macOS Screen Recording permission if you want screenshot capture.

Install or upgrade Codex with your preferred package manager. For example:

```bash
bun add -g @openai/codex@latest
codex --version
```

## Start

```bash
./script/start.sh
```

The start script:

1. Builds, signs, and launches the `BackgroundComputerUse` support runtime if it is not already healthy.
2. Waits for the BCU runtime manifest.
3. Builds, signs, installs, and launches `SpotifyWebViewApp`.
4. Waits for the Spotify webview browser surface to register with BCU.
5. Prints the active BCU URL and useful manifest paths.

The Spotify app opens the real Spotify web player and injects a Spotify AI toggle into the Spotify chrome. Open the sidebar from that toggle, or emit the sidebar event through BCU:

```bash
BASE="$(python3 - <<'PY'
import json, os
path = os.path.join(os.environ["TMPDIR"], "background-computer-use", "runtime-manifest.json")
print(json.load(open(path))["baseURL"])
PY
)"

curl -s -X POST "$BASE/v1/browser/evaluate_js" \
  -H 'content-type: application/json' \
  -d '{"browser":"rb_xyz_dubdub_spotify_webview_spotify_main","javaScript":"window.__bcu.emit(\"spotify.sidebar.open\", {source:\"readme\"}); true"}'
```

## Run Pieces Directly

Run only the BCU support runtime:

```bash
./script/build_and_run.sh bcu run
```

Run only the Spotify app:

```bash
./script/build_and_run.sh spotify run
```

Verify either app launches:

```bash
./script/build_and_run.sh spotify verify
./script/build_and_run.sh bcu verify
```

## Runtime Files

BCU runtime manifest:

```text
$TMPDIR/background-computer-use/runtime-manifest.json
```

Spotify Codex sidecar manifest:

```text
.bcu/spotify-codex-app-server/manifest.json
```

Persisted Spotify AI thread:

```text
.bcu/spotify-codex-thread-id.txt
```

Delete the persisted thread file if you want the next app launch to start a fresh Codex thread.

## Useful BCU Calls

List Spotify app windows:

```bash
curl -s -X POST "$BASE/v1/list_windows" \
  -H 'content-type: application/json' \
  -d '{"app":"xyz.dubdub.spotifywebview"}' | python3 -m json.tool
```

List browser surfaces:

```bash
curl -s -X POST "$BASE/v1/browser/list_targets" \
  -H 'content-type: application/json' \
  -d '{"includeRegistered":true}' | python3 -m json.tool
```

Read the Spotify webview DOM state:

```bash
curl -s -X POST "$BASE/v1/browser/get_state" \
  -H 'content-type: application/json' \
  -d '{"browser":"rb_xyz_dubdub_spotify_webview_spotify_main","imageMode":"path"}' | python3 -m json.tool
```

## Project Layout

- `Sources/SpotifyWebViewApp`: Spotify shell, injected chrome, native sidebar, and Codex wiring.
- `Sources/BackgroundComputerUse`: local control plane, browser routes, AX state, screenshots, and actions.
- `External/CodexAppServerClient`: generated Swift client for the Codex app-server protocol.
- `script/start.sh`: Spotify-first launch flow.
- `script/build_and_run.sh`: app bundling/signing helper for both the support runtime and Spotify app.

## Notes

The Spotify sidebar currently defaults to `gpt-5.5` and sends `ServiceTier.fast` when starting or resuming Codex work. Reasoning traces, tool/action activity, thinking, and final assistant output render as separate native message sections in the sidebar.

## License

MIT
