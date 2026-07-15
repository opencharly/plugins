#!/usr/bin/env python3
"""Validate the portable OpenCharly skill and plugin catalog contract."""

from __future__ import annotations

import json
import pathlib
import re
import sys

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[1]
SKILL_REF = re.compile(r"/charly-([a-z0-9-]+):([a-z][a-z0-9-]*)")
ALLOWED_KEYS = {"name", "description"}


def frontmatter(path: pathlib.Path) -> dict[str, object]:
    text = path.read_text()
    if not text.startswith("---\n"):
        raise ValueError("missing opening ---")
    try:
        raw = text.split("---\n", 2)[1]
    except IndexError as exc:
        raise ValueError("missing closing ---") from exc
    value = yaml.safe_load(raw)
    if not isinstance(value, dict):
        raise ValueError("frontmatter is not a mapping")
    return value


def main() -> int:
    errors: list[str] = []
    skills: dict[tuple[str, str], pathlib.Path] = {}
    raw_names: dict[str, pathlib.Path] = {}
    skill_files = sorted(ROOT.glob("*/skills/*/SKILL.md"))
    skill_dirs = sorted(path for path in ROOT.glob("*/skills/*") if path.is_dir())
    for path in skill_dirs:
        if not (path / "SKILL.md").is_file():
            errors.append(f"{path.relative_to(ROOT)}: skill directory is missing SKILL.md")

    for path in skill_files:
        rel = path.relative_to(ROOT)
        plugin = rel.parts[0]
        folder = rel.parts[2]
        try:
            metadata = frontmatter(path)
        except (ValueError, yaml.YAMLError) as exc:
            errors.append(f"{rel}: invalid YAML frontmatter: {exc}")
            continue
        keys = set(metadata)
        if keys != ALLOWED_KEYS:
            errors.append(f"{rel}: frontmatter keys must be exactly {sorted(ALLOWED_KEYS)}, got {sorted(keys)}")
        name = metadata.get("name")
        description = metadata.get("description")
        if name != folder:
            errors.append(f"{rel}: name {name!r} must match folder {folder!r}")
        if not isinstance(description, str) or not description.strip():
            errors.append(f"{rel}: description must be a non-empty string")
        elif len(description) > 1024:
            errors.append(f"{rel}: description is {len(description)} characters; maximum is 1024")
        elif "<" in description or ">" in description:
            errors.append(f"{rel}: description contains unsupported angle brackets")
        if isinstance(name, str):
            if name in raw_names:
                errors.append(f"{rel}: raw skill name duplicates {raw_names[name].relative_to(ROOT)}")
            raw_names[name] = path
            skills[(plugin, name)] = path

    known_plugins = {plugin for plugin, _ in skills}
    known_agents = {path.stem for path in ROOT.glob("*/agents/*.md")}
    for path in skill_files:
        text = path.read_text()
        for plugin, skill in SKILL_REF.findall(text):
            if plugin in known_plugins and (plugin, skill) not in skills and skill not in known_agents:
                errors.append(
                    f"{path.relative_to(ROOT)}: unresolved skill reference /charly-{plugin}:{skill}"
                )

    catalog = json.loads((ROOT / ".claude-plugin/marketplace.json").read_text())
    for index, entry in enumerate(catalog["plugins"]):
        if "version" in entry:
            errors.append(
                f"marketplace plugins[{index}] duplicates the version owned by its plugin manifest"
            )
    catalog_names = [entry["name"] for entry in catalog["plugins"]]
    catalog_dirs = {entry["source"].removeprefix("./") for entry in catalog["plugins"]}
    manifest_dirs = {
        path.parent.parent.relative_to(ROOT).as_posix()
        for path in ROOT.glob("*/.claude-plugin/plugin.json")
    }
    if catalog_dirs != manifest_dirs:
        errors.append(
            "marketplace/plugin manifest mismatch: "
            f"missing={sorted(manifest_dirs - catalog_dirs)} extra={sorted(catalog_dirs - manifest_dirs)}"
        )

    codex_dirs = {
        path.parent.parent.relative_to(ROOT).as_posix()
        for path in ROOT.glob("*/.codex-plugin/plugin.json")
    }
    if catalog_dirs != codex_dirs:
        errors.append(
            "marketplace/Codex manifest mismatch: "
            f"missing={sorted(catalog_dirs - codex_dirs)} extra={sorted(codex_dirs - catalog_dirs)}"
        )
    for entry in catalog["plugins"]:
        directory = entry["source"].removeprefix("./")
        claude_path = ROOT / directory / ".claude-plugin/plugin.json"
        codex_path = ROOT / directory / ".codex-plugin/plugin.json"
        if not codex_path.is_file():
            continue
        claude_manifest = json.loads(claude_path.read_text())
        codex_manifest = json.loads(codex_path.read_text())
        if codex_manifest.get("name") != entry["name"]:
            errors.append(f"{directory}: Codex manifest name does not match marketplace")
        if codex_manifest.get("version") != claude_manifest.get("version"):
            errors.append(f"{directory}: Claude and Codex manifest versions differ")
        if codex_manifest.get("skills") != "./skills/":
            errors.append(f"{directory}: Codex manifest must use the shared ./skills/ tree")
        has_mcp = (ROOT / directory / ".mcp.json").is_file()
        if (codex_manifest.get("mcpServers") == "./.mcp.json") != has_mcp:
            errors.append(f"{directory}: Codex MCP declaration does not match .mcp.json")
        interface = codex_manifest.get("interface", {})
        required_interface = {
            "displayName",
            "shortDescription",
            "longDescription",
            "developerName",
            "category",
            "capabilities",
            "defaultPrompt",
        }
        missing_interface = required_interface - set(interface)
        if missing_interface:
            errors.append(
                f"{directory}: Codex interface is missing {sorted(missing_interface)}"
            )

    profiles = json.loads((ROOT / "profiles.json").read_text())
    if profiles["developer"] != catalog_names:
        errors.append("developer profile must contain every marketplace plugin in catalog order")
    unknown = set(profiles["user"]) - set(catalog_names)
    if unknown:
        errors.append(f"user profile contains unknown plugins: {sorted(unknown)}")
    for family in profiles["container_families"]:
        if f"charly-{family}" not in catalog_names:
            errors.append(f"container family {family!r} has no marketplace plugin")

    if errors:
        print("skill validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"validated {len(skill_files)} portable skills and {len(catalog_names)} plugins")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
