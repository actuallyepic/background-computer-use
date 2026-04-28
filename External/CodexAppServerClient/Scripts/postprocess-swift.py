#!/usr/bin/env python3
"""Post-process quicktype Swift output for public SwiftPM consumption.

Adds three passes that the raw quicktype output lacks:

1. Injects `///` DocC comments on public types, stored properties, and string
   enum cases by walking the source JSON Schema ``description`` fields. Most
   protocol symbols are discoverable in Xcode Quick Help only after this pass.

2. Conforms the three method-name enums (``ClientRequestMethod``,
   ``NotificationMethod``, ``ServerRequestMethod``) to ``CaseIterable`` so
   consumers can enumerate the full protocol surface without importing the
   bridge types.

3. Canonical generator banner + import cleanup (existing behaviour).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT_TYPE = "CodexProtocolRoot"

INIT_PATTERN = re.compile(r"^(\s*public init\()(.+)(\)\s*\{)\s*$")
OPTIONAL_PARAM_PATTERN = re.compile(r"^(\s*\w+\s*:\s*.+\?)(\s*=\s*[^,]+)?$")

TYPE_DECL_PATTERN = re.compile(r"^public\s+(struct|enum)\s+(\w+)\b")
PROPERTY_PATTERN = re.compile(r"^(\s+)public\s+var\s+(\w+)\s*:")
STRING_ENUM_CASE_PATTERN = re.compile(r'^(\s+)case\s+(\w+)\s*=\s*"([^"]+)"')

METHOD_ENUMS = {"ClientRequestMethod", "NotificationMethod", "ServerRequestMethod"}


def remove_block(lines: list[str], start_index: int) -> int:
    depth = 0
    index = start_index
    while index < len(lines):
        for character in lines[index]:
            if character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
        lines[index] = None  # type: ignore[assignment]
        index += 1
        if depth <= 0:
            break
    return index


def split_params(params_text: str) -> list[str]:
    params: list[str] = []
    current: list[str] = []
    depth = 0
    for character in params_text:
        if character in "([{<":
            depth += 1
        elif character in ")]}>":
            depth -= 1
        if character == "," and depth == 0:
            params.append("".join(current).strip())
            current = []
            continue
        current.append(character)
    tail = "".join(current).strip()
    if tail:
        params.append(tail)
    return params


def add_optional_defaults_to_init_signature(line: str) -> str:
    match = INIT_PATTERN.match(line)
    if not match:
        return line

    prefix, params_text, suffix = match.groups()
    params = split_params(params_text)
    rewritten: list[str] = []
    for param in params:
        param_match = OPTIONAL_PARAM_PATTERN.match(param)
        if param_match and param_match.group(2) is None:
            rewritten.append(f"{param_match.group(1)} = nil")
        else:
            rewritten.append(param)
    return f"{prefix}{', '.join(rewritten)}{suffix}\n"


def snake_to_camel(name: str) -> str:
    if "_" not in name:
        return name
    parts = name.split("_")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def load_doc_maps(schema_path: Path) -> tuple[dict[str, str], dict[tuple[str, str], str], dict[tuple[str, str], str]]:
    """Build three lookup tables from the combined schema:

    - ``type_docs``: TypeName -> description (covers objects and enums)
    - ``prop_docs``: (TypeName, swiftPropName) -> description
    - ``case_docs``: (TypeName, variantWireName) -> description (for string enums
      whose `enum` entries carry per-variant docs via `oneOf`)
    """
    type_docs: dict[str, str] = {}
    prop_docs: dict[tuple[str, str], str] = {}
    case_docs: dict[tuple[str, str], str] = {}

    with schema_path.open() as handle:
        combined = json.load(handle)

    definitions = combined.get("definitions", {})

    def register(name: str, entry: dict) -> None:
        # Register under both the bare name and the CodexProtocolRoot-prefixed
        # form that quicktype sometimes emits (anonymous root unions).
        aliases = [name, f"{ROOT_TYPE}{name}"]
        desc = entry.get("description")
        if isinstance(desc, str) and desc.strip():
            for alias in aliases:
                type_docs.setdefault(alias, desc)
        properties = entry.get("properties", {})
        if isinstance(properties, dict):
            for prop_name, prop_entry in properties.items():
                if not isinstance(prop_entry, dict):
                    continue
                prop_desc = prop_entry.get("description")
                if not (isinstance(prop_desc, str) and prop_desc.strip()):
                    continue
                swift_name = snake_to_camel(prop_name)
                for alias in aliases:
                    prop_docs.setdefault((alias, swift_name), prop_desc)
                    # also register under the original (unconverted) name
                    if swift_name != prop_name:
                        prop_docs.setdefault((alias, prop_name), prop_desc)
        # Variant docs for discriminated-oneOf enums appear as a sibling
        # ``oneOf`` list where each entry has a single-key object mapping.
        one_of = entry.get("oneOf")
        if isinstance(one_of, list):
            for variant in one_of:
                if not isinstance(variant, dict):
                    continue
                vdesc = variant.get("description")
                if not (isinstance(vdesc, str) and vdesc.strip()):
                    continue
                variant_props = variant.get("properties", {})
                if not isinstance(variant_props, dict):
                    continue
                for variant_key in variant_props.keys():
                    for alias in aliases:
                        case_docs.setdefault((alias, variant_key), vdesc)

    for name, entry in definitions.items():
        if isinstance(entry, dict):
            register(name, entry)

    return type_docs, prop_docs, case_docs


def format_doc_comment(description: str, indent: str) -> list[str]:
    text = description.strip().replace("\r\n", "\n").replace("\r", "\n")
    if not text:
        return []
    # Schema descriptions occasionally contain inline triple-backtick code
    # blocks like "Example: ```toml [apps.bad_app] enabled = false ```". When
    # we split that across multiple `///` lines DocC's Markdown parser sees an
    # unclosed fence and starts interpreting the content as a symbol link.
    # Downgrade triple backticks to single (inline code), which renders cleanly
    # on one line and never triggers false symbol resolution.
    text = text.replace("```", "`")
    lines: list[str] = []
    for raw_line in text.split("\n"):
        stripped = raw_line.rstrip()
        if stripped:
            lines.append(f"{indent}/// {stripped}")
        else:
            lines.append(f"{indent}///")
    return lines


def inject_docs(
    content: str,
    type_docs: dict[str, str],
    prop_docs: dict[tuple[str, str], str],
    case_docs: dict[tuple[str, str], str],
) -> str:
    """Walk generated Swift top-to-bottom injecting `///` comments.

    Uses a column-0 bracket depth heuristic to track which top-level type is
    currently open, so property / enum-case injections land in the right
    declaration. Quicktype always emits top-level types with their opening
    ``{`` on the declaration line and a bare ``}`` at column 0 closing the
    body — nested types (``CodingKeys`` etc.) are always indented and therefore
    skipped by the detector. Safe for this codegen shape.
    """
    lines = content.split("\n")
    out: list[str] = []
    current_type: str | None = None

    def previous_is_doc() -> bool:
        # Walk back over whitespace-only lines to find the previous content line.
        for prior in reversed(out):
            stripped = prior.strip()
            if not stripped:
                continue
            return stripped.startswith("///")
        return False

    for line in lines:
        # Close out the current type when we hit its terminating `}` at column 0.
        if current_type is not None and line == "}":
            current_type = None
            out.append(line)
            continue

        # Detect a new top-level public struct/enum declaration.
        if line.startswith("public "):
            type_match = TYPE_DECL_PATTERN.match(line)
            if type_match:
                _, type_name = type_match.groups()
                # Inject type-level doc comment (skip if something is already there).
                description = type_docs.get(type_name)
                if description and not previous_is_doc():
                    out.extend(format_doc_comment(description, ""))
                current_type = type_name
                out.append(line)
                continue

        # Inside a known type, attempt to inject property-level docs.
        if current_type is not None:
            prop_match = PROPERTY_PATTERN.match(line)
            if prop_match:
                indent, prop_name = prop_match.groups()
                description = prop_docs.get((current_type, prop_name))
                if description and not previous_is_doc():
                    out.extend(format_doc_comment(description, indent))
                out.append(line)
                continue

            # Enum case with raw string value — surface variant docs if the
            # schema carries them.
            case_match = STRING_ENUM_CASE_PATTERN.match(line)
            if case_match:
                indent, _case_name, wire_value = case_match.groups()
                description = case_docs.get((current_type, wire_value))
                if description and not previous_is_doc():
                    out.extend(format_doc_comment(description, indent))
                out.append(line)
                continue

        out.append(line)

    return "\n".join(out)


def add_case_iterable(content: str) -> str:
    """Conform the three method-name enums to CaseIterable.

    This makes the full RPC / notification / server-request surface browsable
    via ``ClientRequestMethod.allCases`` without having to import the bridge
    modules. Property of being ``String`` + no associated values guarantees
    synthesis succeeds.
    """
    for enum_name in METHOD_ENUMS:
        pattern = re.compile(
            rf"^(public enum {enum_name}: String, Codable, Sendable)( *\{{)",
            re.MULTILINE,
        )
        content = pattern.sub(r"\1, CaseIterable\2", content)
    return content


def main() -> int:
    if len(sys.argv) != 6:
        print(
            "usage: postprocess-swift.py <input> <output> <codex-version> <installed-version> <schema-combined-json>",
            file=sys.stderr,
        )
        return 1

    input_file, output_file, codex_version, installed_version, schema_path = sys.argv[1:6]

    with open(input_file) as handle:
        lines = handle.readlines()

    for index, line in enumerate(lines):
        if line.startswith("import Foundation"):
            break
        lines[index] = None  # type: ignore[assignment]

    index = 0
    while index < len(lines):
        line = lines[index]
        if line is None:
            index += 1
            continue
        stripped = line.strip()
        if stripped in {
            f"// MARK: - {ROOT_TYPE}",
            f"// MARK: {ROOT_TYPE} convenience initializers and mutators",
        }:
            lines[index] = None  # type: ignore[assignment]
            index += 1
            continue
        if re.match(rf"^(?:public\s+)?(?:struct|extension) {ROOT_TYPE}\b", stripped):
            index = remove_block(lines, index)
            continue
        index += 1

    content = "".join(line for line in lines if line is not None)
    content = "".join(add_optional_defaults_to_init_signature(line) for line in content.splitlines(keepends=True))
    content = re.sub(r"\binternal\s+(?=(?:class|struct|enum|func|let|var)\b)", "public ", content)
    content = content.replace(
        "class JSONCodingKey: CodingKey",
        "final class JSONCodingKey: CodingKey",
    )
    content = content.replace(
        "class JSONAny: Codable",
        "final class JSONAny: Codable, @unchecked Sendable",
    )
    content = content.replace(
        "class JSONNull: Codable",
        "final class JSONNull: Codable, @unchecked Sendable",
    )
    content = content.replace(
        "func newJSONDecoder() -> JSONDecoder {",
        "public func newJSONDecoder() -> JSONDecoder {",
    )
    content = content.replace(
        "func newJSONEncoder() -> JSONEncoder {",
        "public func newJSONEncoder() -> JSONEncoder {",
    )
    content = content.replace(
        "public var hashValue: Int {\n            return 0\n    }",
        "public func hash(into hasher: inout Hasher) {}",
    )
    content = re.sub(r"\n{4,}", "\n\n\n", content)

    # Quicktype copies schema descriptions into its own `///` comments without
    # normalising fenced code blocks, which trips DocC's symbol resolver when
    # the fence ends up split across multiple comment lines (see
    # ``format_doc_comment`` for the same fix). Sweep all existing `///`
    # comment lines and downgrade any triple backticks to inline code.
    content = re.sub(
        r"^(\s*///[^\n]*?)```",
        lambda m: m.group(1) + "`",
        content,
        flags=re.MULTILINE,
    )
    # Run again to catch any second occurrence on the same line.
    content = re.sub(
        r"^(\s*///[^\n]*?)```",
        lambda m: m.group(1) + "`",
        content,
        flags=re.MULTILINE,
    )

    # Phase 1: pipe schema descriptions into `///` DocC comments.
    type_docs, prop_docs, case_docs = load_doc_maps(Path(schema_path))
    content = inject_docs(content, type_docs, prop_docs, case_docs)

    # Phase 2: make the three method-name enums CaseIterable.
    content = add_case_iterable(content)

    header = f"""// GENERATED CODE — DO NOT EDIT
//
// Source: codex app-server generate-json-schema --experimental
// Codex version: {codex_version} ({installed_version})
//
// To regenerate: ./Scripts/generate-protocol.sh
//

"""

    with open(output_file, "w") as handle:
        handle.write(header)
        handle.write(content)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
