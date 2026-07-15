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
