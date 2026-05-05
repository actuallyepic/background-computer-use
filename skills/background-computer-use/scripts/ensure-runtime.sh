#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BackgroundComputerUse"
INSTALL_DIR="${BACKGROUND_COMPUTER_USE_INSTALL_DIR:-$HOME/Applications}"
APP_BUNDLE="${BCU_APP_BUNDLE:-$INSTALL_DIR/$APP_NAME.app}"
TMP_ROOT="${TMPDIR:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"
MANIFEST_PATH="${BCU_MANIFEST_PATH:-$TMP_ROOT/background-computer-use/runtime-manifest.json}"
WAIT_ATTEMPTS="${BCU_WAIT_ATTEMPTS:-120}"
WAIT_INTERVAL="${BCU_WAIT_INTERVAL:-0.25}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

read_base_url() {
  python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    sys.exit(1)
try:
    value = json.loads(path.read_text()).get("baseURL", "")
except Exception:
    sys.exit(1)
if not value:
    sys.exit(1)
print(value)
PY
}

health_ok() {
  local base_url="$1"
  curl -fsS "$base_url/health" >/dev/null 2>&1
}

current_runtime_ok() {
  local base_url
  base_url="$(read_base_url 2>/dev/null || true)"
  [ -n "$base_url" ] && health_ok "$base_url"
}

wait_for_runtime() {
  local base_url=""
  for _ in $(seq 1 "$WAIT_ATTEMPTS"); do
    base_url="$(read_base_url 2>/dev/null || true)"
    if [ -n "$base_url" ] && health_ok "$base_url"; then
      printf '%s\n' "$base_url"
      return 0
    fi
    sleep "$WAIT_INTERVAL"
  done
  return 1
}

start_from_source() {
  local source_dir="$1"
  if [ ! -x "$source_dir/script/start.sh" ]; then
    echo "BCU_SOURCE_DIR does not contain executable script/start.sh: $source_dir" >&2
    return 1
  fi
  "$source_dir/script/start.sh"
}

launch_installed_app() {
  if [ ! -d "$APP_BUNDLE" ]; then
    return 1
  fi
  rm -f "$MANIFEST_PATH"
  /usr/bin/open "$APP_BUNDLE"
}

if current_runtime_ok; then
  BASE_URL="$(read_base_url)"
else
  if [ -n "${BCU_SOURCE_DIR:-}" ]; then
    start_from_source "$BCU_SOURCE_DIR"
  elif launch_installed_app; then
    :
  else
    "$SCRIPT_DIR/install-runtime.sh"
    launch_installed_app
  fi
  BASE_URL="$(wait_for_runtime)" || {
    echo "BackgroundComputerUse did not become healthy." >&2
    echo "Expected manifest: $MANIFEST_PATH" >&2
    echo "Set BCU_SOURCE_DIR=/path/to/background-computer-use for local source builds, or set BCU_RELEASE_URL to an app zip." >&2
    exit 1
  }
fi

echo "BackgroundComputerUse running at $BASE_URL"
echo "Runtime manifest: $MANIFEST_PATH"
echo
echo "Bootstrap:"
curl -fsS "$BASE_URL/v1/bootstrap" | python3 -m json.tool
