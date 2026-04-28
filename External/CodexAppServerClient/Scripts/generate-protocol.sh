#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PINNED_VERSION="${1:-}"
if [ -z "${PINNED_VERSION}" ] && [ -f "${PROJECT_DIR}/.codex-version" ]; then
  PINNED_VERSION="$(tr -d '[:space:]' < "${PROJECT_DIR}/.codex-version")"
fi

if [ -z "${PINNED_VERSION}" ]; then
  echo "missing codex version; set .codex-version or pass one explicitly" >&2
  exit 1
fi

CODEX_BIN="${CODEX_BIN:-codex}"
INSTALLED_VERSION="$("${CODEX_BIN}" --version | awk '{print $NF}')"
if [ "${INSTALLED_VERSION}" != "${PINNED_VERSION}" ]; then
  echo "installed codex version ${INSTALLED_VERSION} does not match pinned version ${PINNED_VERSION}" >&2
  exit 1
fi

SCHEMA_DIR="${PROJECT_DIR}/.schema-cache"
TS_DIR="${PROJECT_DIR}/.ts-cache"
GENERATED_DIR="${PROJECT_DIR}/Sources/CodexAppServerProtocol/Generated"
MODELS_OUT="${GENERATED_DIR}/CodexProtocolGenerated.swift"

rm -rf "${SCHEMA_DIR}" "${TS_DIR}"
mkdir -p "${SCHEMA_DIR}" "${TS_DIR}" "${GENERATED_DIR}"

"${CODEX_BIN}" app-server generate-json-schema --out "${SCHEMA_DIR}" --experimental
"${CODEX_BIN}" app-server generate-ts --out "${TS_DIR}" --experimental

python3 "${SCRIPT_DIR}/combine-schemas.py" "${SCHEMA_DIR}" "${SCHEMA_DIR}/_combined.json"

QUICKTYPE_VERSION="${QUICKTYPE_VERSION:-23.0.171}"
bunx "quicktype@${QUICKTYPE_VERSION}" \
  --src-lang schema \
  --lang swift \
  --top-level CodexProtocolRoot \
  --density normal \
  --acronym-style camel \
  --access-level public \
  --mutable-properties \
  --sendable \
  --quiet \
  "${SCHEMA_DIR}/_combined.json" \
  > "${MODELS_OUT}.tmp"

python3 "${SCRIPT_DIR}/postprocess-swift.py" \
  "${MODELS_OUT}.tmp" \
  "${MODELS_OUT}" \
  "${PINNED_VERSION}" \
  "$("${CODEX_BIN}" --version)" \
  "${SCHEMA_DIR}/_combined.json"

rm "${MODELS_OUT}.tmp"

DOCC_OUT_DIR="${PROJECT_DIR}/Sources/CodexAppServerProtocol/CodexAppServerProtocol.docc/Generated"

python3 "${SCRIPT_DIR}/generate-swift-bridge.py" \
  --swift "${MODELS_OUT}" \
  --client-request-ts "${TS_DIR}/ClientRequest.ts" \
  --server-notification-ts "${TS_DIR}/ServerNotification.ts" \
  --server-request-ts "${TS_DIR}/ServerRequest.ts" \
  --schema "${SCHEMA_DIR}/_combined.json" \
  --out-dir "${GENERATED_DIR}" \
  --docc-out-dir "${DOCC_OUT_DIR}" \
  --approval-decision-swift "${PROJECT_DIR}/Sources/CodexAppServerProtocol/Support/ApprovalDecision.swift" \
  --codex-version "${PINNED_VERSION}"

rm -rf "${SCHEMA_DIR}" "${TS_DIR}"

echo "generated Swift protocol for codex ${PINNED_VERSION}"
