#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BackgroundComputerUse"
INSTALL_DIR="${BACKGROUND_COMPUTER_USE_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
DEFAULT_RELEASE_URL="https://github.com/actuallyepic/background-computer-use/releases/latest/download/$APP_NAME.app.zip"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSET_ZIP="$SKILL_DIR/assets/$APP_NAME.app.zip"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bcu-install.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ZIP_PATH="$WORK_DIR/$APP_NAME.app.zip"

copy_or_download_zip() {
  if [ -n "${BCU_APP_ZIP:-}" ]; then
    cp "$BCU_APP_ZIP" "$ZIP_PATH"
    return 0
  fi

  if [ -f "$ASSET_ZIP" ]; then
    cp "$ASSET_ZIP" "$ZIP_PATH"
    return 0
  fi

  local release_url="${BCU_RELEASE_URL:-$DEFAULT_RELEASE_URL}"
  if curl -fL "$release_url" -o "$ZIP_PATH"; then
    return 0
  fi

  cat >&2 <<EOF
Could not download BackgroundComputerUse app artifact from:
  $release_url

Provide one of:
  BCU_SOURCE_DIR=/path/to/background-computer-use bash "$SCRIPT_DIR/ensure-runtime.sh"
  BCU_APP_ZIP=/path/to/BackgroundComputerUse.app.zip bash "$SCRIPT_DIR/ensure-runtime.sh"
  BCU_RELEASE_URL=https://.../BackgroundComputerUse.app.zip bash "$SCRIPT_DIR/ensure-runtime.sh"
EOF
  return 1
}

verify_checksum() {
  if [ -z "${BCU_RELEASE_SHA256:-}" ]; then
    return 0
  fi

  local actual
  actual="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
  if [ "$actual" != "$BCU_RELEASE_SHA256" ]; then
    echo "Checksum mismatch for $ZIP_PATH" >&2
    echo "Expected: $BCU_RELEASE_SHA256" >&2
    echo "Actual:   $actual" >&2
    return 1
  fi
}

install_app() {
  unzip -q "$ZIP_PATH" -d "$WORK_DIR/unpacked"
  local app
  app="$(find "$WORK_DIR/unpacked" -maxdepth 3 -name "$APP_NAME.app" -type d | head -1)"
  if [ -z "$app" ]; then
    echo "Zip did not contain $APP_NAME.app" >&2
    return 1
  fi

  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALLED_APP_BUNDLE"
  cp -R "$app" "$INSTALLED_APP_BUNDLE"

  if [ "${BCU_REMOVE_QUARANTINE:-0}" = "1" ]; then
    xattr -dr com.apple.quarantine "$INSTALLED_APP_BUNDLE" 2>/dev/null || true
  fi
}

copy_or_download_zip
verify_checksum
install_app

echo "Installed $INSTALLED_APP_BUNDLE"
