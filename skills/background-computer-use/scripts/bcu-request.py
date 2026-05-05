#!/usr/bin/env python3
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def usage() -> int:
    print(
        "usage: bcu-request.py METHOD PATH [JSON_BODY]\n"
        "examples:\n"
        "  bcu-request.py GET /v1/bootstrap\n"
        "  bcu-request.py POST /v1/list_apps '{}'",
        file=sys.stderr,
    )
    return 2


def manifest_path() -> Path:
    if os.environ.get("BCU_MANIFEST_PATH"):
        return Path(os.environ["BCU_MANIFEST_PATH"])
    tmpdir = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    return Path(tmpdir) / "background-computer-use" / "runtime-manifest.json"


def base_url() -> str:
    if os.environ.get("BCU_BASE_URL"):
        return os.environ["BCU_BASE_URL"].rstrip("/")
    path = manifest_path()
    try:
        data = json.loads(path.read_text())
        return str(data["baseURL"]).rstrip("/")
    except Exception as exc:
        raise SystemExit(f"Could not read baseURL from {path}: {exc}") from exc


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        return usage()

    method = argv[1].upper()
    route_path = argv[2]
    if not route_path.startswith("/"):
        route_path = "/" + route_path

    body = None
    headers = {"accept": "application/json"}
    if len(argv) == 4:
        try:
            parsed = json.loads(argv[3])
        except json.JSONDecodeError as exc:
            raise SystemExit(f"JSON body is invalid: {exc}") from exc
        body = json.dumps(parsed).encode("utf-8")
        headers["content-type"] = "application/json"

    request = urllib.request.Request(
        base_url() + route_path,
        data=body,
        method=method,
        headers=headers,
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read()
            status = response.status
    except urllib.error.HTTPError as exc:
        payload = exc.read()
        status = exc.code
    except urllib.error.URLError as exc:
        raise SystemExit(f"Request failed: {exc}") from exc

    try:
        print(json.dumps(json.loads(payload), indent=2, sort_keys=True))
    except json.JSONDecodeError:
        sys.stdout.buffer.write(payload)
        if payload and not payload.endswith(b"\n"):
            print()

    return 0 if 200 <= status < 300 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
