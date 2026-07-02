# plugins/ — signpost (not the rule-set)

You are in the OpenCharly **plugins** tree: Claude Code skills, sub-agents,
and the marketplace/plugin manifests.

**Load these skills FIRST (R0):**

- `/charly-internals:skills` — skill authoring/maintenance, the plugin/skill
  directory conventions, the agent-discovery + per-directory-signpost rules,
  and where content belongs (CLAUDE.md vs skill vs CHANGELOG vs memory).
- `/charly-internals:agents` — authoring or invoking sub-agents
  (`plugins/internals/agents/*.md`), the dynamic workflows, agent teams, and
  the hooks doctrine.

**Authoritative rules live in the repo-root `CLAUDE.md`** (the superproject's
`CLAUDE.md`, one level up when this is a submodule of `opencharly`). R0–R10,
the hard-cutover policy, AI attribution, and the git-workflow are defined
there — this file only signposts and never restates them. History lives in
this repo's `CHANGELOG/` (one file per CalVer version); skills describe current behavior in present tense.
