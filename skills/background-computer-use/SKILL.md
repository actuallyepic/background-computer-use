---
name: background-computer-use
description: Launch and use the local BackgroundComputerUse macOS runtime through its self-documenting loopback API. Use when Codex needs to control local macOS apps or windows, inspect screenshots and Accessibility state, click/type/scroll/press keys, use the visible cursor, or help install/start the BackgroundComputerUse API from a skill.
---

# Background Computer Use

Use this skill to start or connect to the local macOS `BackgroundComputerUse` runtime, then rely on the runtime's own documentation endpoints instead of memorizing route schemas.

## Workflow

1. Start or discover the runtime:
   ```bash
   bash "$SKILL_DIR/scripts/ensure-runtime.sh"
   ```
   If `$SKILL_DIR` is not already set by the host, derive it from this skill folder path before running scripts.

2. Read the runtime manifest from:
   ```text
   $TMPDIR/background-computer-use/runtime-manifest.json
   ```
   Never assume a fixed port.

3. Call `GET /v1/bootstrap`.
   - If `instructions.ready` is false, report the returned permission steps to the user.
   - Do not continue with actions until Accessibility and Screen Recording are ready.

4. Call `GET /v1/routes`.
   - Treat this as the source of truth for available routes, request fields, response fields, examples, and error codes.
   - Do not assume browser routes exist; use them only when `/v1/routes` advertises them.

5. For visual tasks, request screenshots with `imageMode: "path"` and inspect the returned image files when useful.

6. For action routes, reuse `stateToken` from the state you inspected. Reuse the same `cursor.id` when the user wants one continuous visible cursor.

## Helpers

- `scripts/ensure-runtime.sh`: find, install, launch, and bootstrap the runtime.
- `scripts/install-runtime.sh`: install `BackgroundComputerUse.app` from an app zip or release URL.
- `scripts/bcu-request.py`: call runtime endpoints from the manifest base URL.

Examples:

```bash
python3 "$SKILL_DIR/scripts/bcu-request.py" GET /v1/bootstrap
python3 "$SKILL_DIR/scripts/bcu-request.py" GET /v1/routes
python3 "$SKILL_DIR/scripts/bcu-request.py" POST /v1/list_apps '{}'
```

## Local Development

When working from a source checkout instead of an installed release:

```bash
BCU_SOURCE_DIR=/path/to/background-computer-use bash "$SKILL_DIR/scripts/ensure-runtime.sh"
```

That runs the repo's `script/start.sh`, which builds, signs, installs, launches, and bootstraps the app.

## More Detail

Read `references/runtime.md` only when you need install modes, release packaging notes, or the permission/debugging checklist.
