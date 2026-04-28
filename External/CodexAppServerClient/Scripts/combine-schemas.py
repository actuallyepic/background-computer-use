#!/usr/bin/env python3
"""Combine codex app-server JSON Schema bundles into one schema for quicktype."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def merge_definitions(target: dict, source: dict, source_path: Path | None = None) -> None:
    for key, value in source.items():
        existing = target.get(key)
        if existing is None:
            target[key] = value
            continue
        if existing != value:
            origin = f" ({source_path})" if source_path else ""
            print(
                f"warning: duplicate schema definition {key!r} with differing bodies{origin}; keeping first",
                file=sys.stderr,
            )


def load_json(path: Path) -> dict:
    with path.open() as handle:
        return json.load(handle)


def add_root_definition(definitions: dict, data: dict, fallback_name: str) -> None:
    title = data.get("title", fallback_name)
    if title in definitions:
        return
    root_definition = {
        key: value
        for key, value in data.items()
        if key not in {"$schema", "definitions", "title"}
    }
    if root_definition.get("type") or root_definition.get("properties") or root_definition.get("oneOf"):
        root_definition["title"] = title
        definitions[title] = root_definition


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: combine-schemas.py <schema-dir> <output-file>", file=sys.stderr)
        return 1

    schema_dir = Path(sys.argv[1])
    output_file = Path(sys.argv[2])

    definitions: dict[str, object] = {}

    for path in sorted(schema_dir.glob("*.schemas.json")):
        merge_definitions(definitions, load_json(path).get("definitions", {}), path)

    for child_dir in (schema_dir / "v2", schema_dir / "v1"):
        if not child_dir.is_dir():
            continue
        for path in sorted(child_dir.glob("*.json")):
            if path.name.endswith(".schemas.json"):
                continue
            data = load_json(path)
            merge_definitions(definitions, data.get("definitions", {}), path)
            add_root_definition(definitions, data, path.stem)

    for path in sorted(schema_dir.glob("*.json")):
        if path.name.endswith(".schemas.json") or path.name.startswith("_"):
            continue
        data = load_json(path)
        merge_definitions(definitions, data.get("definitions", {}))
        add_root_definition(definitions, data, path.stem)

    combined = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "CodexProtocol",
        "type": "object",
        "definitions": definitions,
        "properties": {
            key: {"$ref": f"#/definitions/{key}"} for key in sorted(definitions.keys())
        },
    }

    output_file.write_text(json.dumps(combined, indent=2) + "\n")
    print(f"combined {len(definitions)} schema definitions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
