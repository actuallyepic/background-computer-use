#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"
RUNTIME_MANIFEST="$TMP_ROOT/background-computer-use/runtime-manifest.json"
SPOTIFY_TARGET_ID="rb_xyz_dubdub_spotify_webview_spotify_main"
SIDECAR_MANIFEST="$ROOT_DIR/.bcu/spotify-codex-app-server/manifest.json"

read_base_url() {
  python3 - "$RUNTIME_MANIFEST" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["baseURL"])
PY
}

runtime_healthy() {
  [ -f "$RUNTIME_MANIFEST" ] || return 1
  local base_url
  base_url="$(read_base_url 2>/dev/null || true)"
  [ -n "$base_url" ] || return 1
  curl -fsS "$base_url/health" >/dev/null 2>&1
}

wait_for_runtime() {
  for _ in $(seq 1 100); do
    if runtime_healthy; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

spotify_surface_registered() {
  curl -fsS -X POST "$BASE_URL/v1/browser/list_targets" \
    -H 'content-type: application/json' \
    -d '{"includeRegistered":true}' |
    python3 -c 'import json, sys; data=json.load(sys.stdin); target=sys.argv[1]; targets=data.get("targets") or data.get("browsers") or []; sys.exit(0 if any((t.get("targetID") or t.get("id")) == target for t in targets) else 1)' \
      "$SPOTIFY_TARGET_ID" >/dev/null
}

if ! runtime_healthy; then
  rm -f "$RUNTIME_MANIFEST"
  "$ROOT_DIR/script/build_and_run.sh" bcu run
fi

if ! wait_for_runtime; then
  echo "BCU runtime manifest was not created at $RUNTIME_MANIFEST" >&2
  exit 1
fi

BASE_URL="$(read_base_url)"

"$ROOT_DIR/script/build_and_run.sh" spotify run

for _ in $(seq 1 80); do
  if spotify_surface_registered; then
    SPOTIFY_REGISTERED=1
    break
  fi
  sleep 0.25
done

echo "BCU runtime: $BASE_URL"
echo "BCU manifest: $RUNTIME_MANIFEST"
echo "Spotify app: $HOME/Applications/SpotifyWebViewApp.app"
if [ "${SPOTIFY_REGISTERED:-0}" = "1" ]; then
  echo "Spotify browser surface: $SPOTIFY_TARGET_ID"
else
  echo "Spotify browser surface not registered yet; open SpotifyWebViewApp and retry /v1/browser/list_targets."
fi

if [ -f "$SIDECAR_MANIFEST" ]; then
  echo "Codex sidecar manifest: $SIDECAR_MANIFEST"
else
  echo "Codex sidecar manifest will appear after Spotify AI connects: $SIDECAR_MANIFEST"
fi
