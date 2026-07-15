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
    print(sum(p["policy"]["installation"] == "INSTALLED_BY_DEFAULT" for p in data["plugins"]))
PY
)
    [[ $count -eq $expected ]] || { echo "$harness $profile count: $count" >&2; exit 1; }
    if [[ $harness == codex ]]; then
        python3 - "$CONSUMER" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
links = list((root / ".agents/skills").glob("charly-*"))
assert links, "Codex profile created no repo-native skills"
assert all(path.is_symlink() for path in links), "Codex profile copied skill content"
assert all((path.resolve() / "SKILL.md").is_file() for path in links), "broken skill link"
PY
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
