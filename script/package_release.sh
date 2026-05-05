#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BackgroundComputerUse"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
RELEASE_DIR="$DIST_DIR/release"
ZIP_PATH="$RELEASE_DIR/$APP_NAME.app.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"

BACKGROUND_COMPUTER_USE_RELEASE_BUILD=1 "$ROOT_DIR/script/build_and_run.sh" build

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
/usr/bin/ditto -c -k --keepParent --norsrc "$APP_BUNDLE" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" >"$CHECKSUM_PATH"

echo "Release app zip: $ZIP_PATH"
echo "SHA-256: $(awk '{print $1}' "$CHECKSUM_PATH")"
echo "Checksum file: $CHECKSUM_PATH"
