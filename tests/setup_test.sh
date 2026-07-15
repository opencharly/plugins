#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CONSUMER="$TMP/consumer"
HOME_SENTINEL="$TMP/home"
mkdir -p "$CONSUMER/plugins/.claude-plugin" "$HOME_SENTINEL/.claude" "$HOME_SENTINEL/.codex"
git -C "$CONSUMER" init -q
cp -a "$ROOT/." "$CONSUMER/plugins/"
mkdir -p "$CONSUMER/.claude"
printf '%s\n' \
    '{' \
    '  "consumerSetting": {"owner": "fixture"},' \
    '  "enabledPlugins": {"consumer@example": true}' \
    '}' >"$CONSUMER/.claude/settings.json"
mkdir -p "$CONSUMER/.agents/plugins"
mkdir -p "$CONSUMER/.agents/skills" "$TMP/consumer-owned-skill"
printf '%s\n' '# Consumer-owned skill' >"$TMP/consumer-owned-skill/SKILL.md"
ln -s "$TMP/consumer-owned-skill" "$CONSUMER/.agents/skills/charly-user-owned"
consumer_skill_target=$(readlink "$CONSUMER/.agents/skills/charly-user-owned")
printf '%s\n' \
    '{' \
    '  "name": "consumer-marketplace",' \
    '  "interface": {"displayName": "Consumer", "theme": "dark"},' \
    '  "consumerMetadata": {"owner": "fixture"},' \
    '  "plugins": [' \
    '    {"name": "consumer-before", "source": {"source": "local", "path": "./before"}},' \
    '    {"name": "charly-core", "source": {"source": "local", "path": "./stale"}},' \
    '    {"name": "consumer-after", "source": {"source": "local", "path": "./after"}}' \
    '  ]' \
    '}' >"$CONSUMER/.agents/plugins/marketplace.json"

printf 'user claude sentinel\n' >"$HOME_SENTINEL/.claude/settings.json"
printf 'user codex sentinel\n' >"$HOME_SENTINEL/.codex/config.toml"
before=$(sha256sum "$HOME_SENTINEL/.claude/settings.json" "$HOME_SENTINEL/.codex/config.toml")

assert_profile() {
    local harness=$1 profile=$2 expected=$3 family=${4:-}
    args=("$harness" "$profile")
    [[ -n $family ]] && args+=("$family")
    (cd "$CONSUMER" && HOME="$HOME_SENTINEL" "$ROOT/setup" "${args[@]}")
    (cd "$CONSUMER" && HOME="$HOME_SENTINEL" "$ROOT/setup" "$harness" --check "$profile" ${family:+"$family"})
    count=$(python3 - "$CONSUMER" "$harness" <<'PY'
import json, pathlib, sys
root, harness = pathlib.Path(sys.argv[1]), sys.argv[2]
if harness == "claude":
    data = json.loads((root / ".claude/settings.json").read_text())
    print(sum(name.startswith("charly-") and value for name, value in data["enabledPlugins"].items()))
else:
    data = json.loads((root / ".agents/plugins/marketplace.json").read_text())
    print(sum(
        p["name"].startswith("charly-")
        and p["policy"]["installation"] == "INSTALLED_BY_DEFAULT"
        for p in data["plugins"]
    ))
PY
)
    [[ $count -eq $expected ]] || { echo "$harness $profile count: $count" >&2; exit 1; }
    if [[ $harness == claude ]]; then
        python3 - "$CONSUMER" <<'PY'
import json, pathlib, sys
data = json.loads((pathlib.Path(sys.argv[1]) / ".claude/settings.json").read_text())
assert data["consumerSetting"] == {"owner": "fixture"}
assert data["enabledPlugins"]["consumer@example"] is True
PY
    else
        python3 - "$CONSUMER" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
links = list((root / ".agents/skills").glob("charly-*"))
assert links, "Codex profile created no repo-native skills"
assert all(path.is_symlink() for path in links), "Codex profile copied skill content"
assert all((path.resolve() / "SKILL.md").is_file() for path in links), "broken skill link"
data = json.loads((root / ".agents/plugins/marketplace.json").read_text())
assert data["name"] == "consumer-marketplace"
assert data["interface"] == {"displayName": "Consumer", "theme": "dark"}
assert data["consumerMetadata"] == {"owner": "fixture"}
unmanaged = [p for p in data["plugins"] if p["name"].startswith("consumer-")]
assert unmanaged == [
    {"name": "consumer-before", "source": {"source": "local", "path": "./before"}},
    {"name": "consumer-after", "source": {"source": "local", "path": "./after"}},
]
names = [p["name"] for p in data["plugins"]]
assert len(names) == len(set(names)), "duplicate marketplace entries"
PY
        [[ $(readlink "$CONSUMER/.agents/skills/charly-user-owned") == "$consumer_skill_target" ]] || {
            echo "Codex setup changed a consumer-owned skill link" >&2
            exit 1
        }
    fi
}

for harness in claude codex; do
    assert_profile "$harness" developer 25
    assert_profile "$harness" user 13
    assert_profile "$harness" container 2 coder
    if (cd "$ROOT/.." && "$ROOT/setup" "$harness" user) >/dev/null 2>&1; then
        echo "$harness reduced profile unexpectedly accepted in OpenCharly" >&2
        exit 1
    fi
done

# A malformed ownership inventory must fail closed before any project mutation.
inventory_project="$TMP/inventory-project"
mkdir -p "$inventory_project/.agents/skills" "$inventory_project/.agents/plugins"
git -C "$inventory_project" init -q
ln -s "$CONSUMER/plugins" "$inventory_project/plugins"
printf '%s\n' '{"sentinel": true, "plugins": []}' >"$inventory_project/.agents/plugins/marketplace.json"
python3 - "$ROOT/setup" "$inventory_project" "$TMP/inventory-external" <<'PY'
import hashlib, json, pathlib, subprocess, sys
setup, project, external = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
external.symlink_to(project / "plugins/core/skills/ssh")
inventory = project / ".agents/skills/.charly-profile.json"
marketplace = project / ".agents/plugins/marketplace.json"
payloads = [
    {"version": 1, "links": {str(external): "../../plugins/core/skills/ssh"}},
    {"version": 1, "links": {"../outside": "../../plugins/core/skills/ssh"}},
    {"version": 1, "links": {"nested/name": "../../plugins/core/skills/ssh"}},
    {"version": 1, "links": {"nested\\name": "../../plugins/core/skills/ssh"}},
    {"version": 2, "links": {}},
    {"version": 1, "links": []},
    {"version": 1, "links": {"charly-core--ssh": 7}},
]
before = hashlib.sha256(marketplace.read_bytes()).digest()
for payload in payloads:
    inventory.write_text(json.dumps(payload) + "\n")
    result = subprocess.run(
        [str(setup), "codex", "--project", str(project), "developer"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    assert result.returncode != 0, f"accepted invalid inventory: {payload}"
    assert hashlib.sha256(marketplace.read_bytes()).digest() == before
    assert external.is_symlink(), "invalid inventory changed an external link"
PY

# A schema-valid but semantically wrong owned target must fail before any write or unlink.
collision_project="$TMP/collision-project"
mkdir -p "$collision_project/.agents/skills" "$collision_project/.agents/plugins"
git -C "$collision_project" init -q
ln -s "$CONSUMER/plugins" "$collision_project/plugins"
printf '%s\n' '{"sentinel": true, "plugins": []}' >"$collision_project/.agents/plugins/marketplace.json"
ln -s ../../plugins/core/skills/validate "$collision_project/.agents/skills/charly-core--ssh"
ln -s ../../plugins/core/skills/ssh "$collision_project/.agents/skills/charly-retired--ssh"
printf '%s\n' \
    '{"version": 1, "links": {' \
    '  "charly-core--ssh": "../../plugins/core/skills/validate",' \
    '  "charly-retired--ssh": "../../plugins/core/skills/ssh"' \
    '}}' >"$collision_project/.agents/skills/.charly-profile.json"
collision_before=$(sha256sum \
    "$collision_project/.agents/plugins/marketplace.json" \
    "$collision_project/.agents/skills/.charly-profile.json")
if "$ROOT/setup" codex --project "$collision_project" developer >/dev/null 2>&1; then
    echo "Codex setup accepted a wrong owned skill target" >&2
    exit 1
fi
[[ $collision_before == "$(sha256sum \
    "$collision_project/.agents/plugins/marketplace.json" \
    "$collision_project/.agents/skills/.charly-profile.json")" ]] || {
    echo "Codex collision rejection mutated managed files" >&2
    exit 1
}
[[ $(readlink "$collision_project/.agents/skills/charly-core--ssh") == ../../plugins/core/skills/validate ]]
[[ -L "$collision_project/.agents/skills/charly-retired--ssh" ]] || {
    echo "Codex collision rejection removed an obsolete owned link" >&2
    exit 1
}

# Managed JSON leaves with the wrong type fail before related files or links appear.
for case_name in inventory marketplace claude-settings; do
    type_project="$TMP/type-$case_name"
    mkdir -p "$type_project"
    git -C "$type_project" init -q
    ln -s "$CONSUMER/plugins" "$type_project/plugins"
    case $case_name in
        inventory)
            mkdir -p "$type_project/.agents/skills/.charly-profile.json"
            harness=codex
            ;;
        marketplace)
            mkdir -p "$type_project/.agents/plugins/marketplace.json"
            harness=codex
            ;;
        claude-settings)
            mkdir -p "$type_project/.claude/settings.json"
            harness=claude
            ;;
    esac
    if "$ROOT/setup" "$harness" --project "$type_project" developer >/dev/null 2>&1; then
        echo "$case_name wrong-type destination was accepted" >&2
        exit 1
    fi
    if [[ -d "$type_project/.agents/skills" ]] &&
        find "$type_project/.agents/skills" -mindepth 1 -maxdepth 1 -type l -print -quit | grep -q .; then
        echo "$case_name rejection created skill links" >&2
        exit 1
    fi
done

# Catalog plugin sources are read-only inputs but must remain inside ./plugins.
catalog="$CONSUMER/plugins/.claude-plugin/marketplace.json"
catalog_backup="$TMP/marketplace.catalog.json"
cp "$catalog" "$catalog_backup"
catalog_marketplace_before=$(sha256sum "$CONSUMER/.agents/plugins/marketplace.json")
python3 - "$catalog" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["plugins"][0]["source"] = "../../outside"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if "$ROOT/setup" codex --project "$CONSUMER" developer >/dev/null 2>&1; then
    echo "Codex setup accepted an escaping catalog source" >&2
    exit 1
fi
[[ $catalog_marketplace_before == "$(sha256sum "$CONSUMER/.agents/plugins/marketplace.json")" ]] || {
    echo "catalog-source rejection mutated the project marketplace" >&2
    exit 1
}
cp "$catalog_backup" "$catalog"

[[ ! -e "$CONSUMER/.agents/skills/charly-build--validate" ]] || {
    echo "Codex profile transition retained a deselected generated skill" >&2
    exit 1
}

# Explicit --project, idempotence, dry-run, and managed-drift rejection.
"$ROOT/setup" codex --project "$CONSUMER" developer
"$ROOT/setup" codex --project "$CONSUMER" --check developer
marketplace="$CONSUMER/.agents/plugins/marketplace.json"
stable=$(sha256sum "$marketplace")
"$ROOT/setup" codex --project "$CONSUMER" developer >/dev/null

# Managed roots must never escape the project through symlinks.
for harness in claude codex; do
    escape_project="$TMP/escape-$harness"
    escape_target="$TMP/external-$harness"
    mkdir -p "$escape_project" "$escape_target"
    git -C "$escape_project" init -q
    ln -s "$CONSUMER/plugins" "$escape_project/plugins"
    if [[ $harness == claude ]]; then
        ln -s "$escape_target" "$escape_project/.claude"
    else
        ln -s "$escape_target" "$escape_project/.agents"
    fi
    if "$ROOT/setup" "$harness" --project "$escape_project" developer >/dev/null 2>&1; then
        echo "$harness setup followed a managed-root symlink" >&2
        exit 1
    fi
    if find "$escape_target" -mindepth 1 -print -quit | grep -q .; then
        echo "$harness setup wrote outside the project" >&2
        exit 1
    fi
done
[[ $stable == "$(sha256sum "$marketplace")" ]] || { echo "Codex setup is not idempotent" >&2; exit 1; }
"$ROOT/setup" codex --project "$CONSUMER" --dry-run user >/dev/null
[[ $stable == "$(sha256sum "$marketplace")" ]] || { echo "Codex dry-run changed the marketplace" >&2; exit 1; }
python3 - "$marketplace" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
next(p for p in data["plugins"] if p["name"] == "charly-core")["policy"]["installation"] = "BROKEN"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
if "$ROOT/setup" codex --project "$CONSUMER" --check developer >/dev/null 2>&1; then
    echo "Codex check accepted managed marketplace drift" >&2
    exit 1
fi
"$ROOT/setup" codex --project "$CONSUMER" developer >/dev/null

manifest="$CONSUMER/plugins/core/.codex-plugin/plugin.json"
mv "$manifest" "$manifest.disabled"
if (cd "$CONSUMER" && HOME="$HOME_SENTINEL" "$ROOT/setup" codex --check developer) >/dev/null 2>&1; then
    echo "Codex profile accepted a missing plugin manifest" >&2
    exit 1
fi
mv "$manifest.disabled" "$manifest"

mkdir "$CONSUMER/plugins/core/skills/retired-empty-skill"
if python3 "$CONSUMER/plugins/scripts/validate_skills.py" >/dev/null 2>&1; then
    echo "portable skill validation accepted an empty skill directory" >&2
    exit 1
fi
rmdir "$CONSUMER/plugins/core/skills/retired-empty-skill"
python3 "$CONSUMER/plugins/scripts/validate_skills.py" >/dev/null

after=$(sha256sum "$HOME_SENTINEL/.claude/settings.json" "$HOME_SENTINEL/.codex/config.toml")
[[ $before == "$after" ]] || { echo "user configuration changed" >&2; exit 1; }

echo "project profiles are exact; user configuration is untouched"
