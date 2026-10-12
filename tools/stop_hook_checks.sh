#!/usr/bin/env bash
# Claude Code Stop hook: when the turn changed game code, run the fast checks (GDScript lint + headless load
# check) and, on failure, block the stop (exit 2) so the agent sees the errors and keeps working. The game
# tests run on commit instead (.githooks/pre-commit).
#
# Skips silently when: the hook already fired this turn (stop_hook_active — no loops), nothing under
# scenes/ tests/ or project.godot changed, or those files are identical to the last run (so an
# unfixed failure is reported once, not on every stop). Wired in .claude/settings.json.
set -uo pipefail
cd "$(dirname "$0")/.."

if grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <(cat); then
  exit 0
fi

paths=(scenes tests project.godot)
fingerprint=$( { git diff HEAD -- "${paths[@]}"; git ls-files --others --exclude-standard -- "${paths[@]}" \
  | while read -r f; do echo "$f"; shasum "$f"; done; } | shasum | cut -d' ' -f1 )
changed=$( { git diff --name-only HEAD -- "${paths[@]}"; git ls-files --others --exclude-standard -- "${paths[@]}"; } | head -1 )
[[ -z "$changed" ]] && exit 0

state="${TMPDIR:-/tmp}/example_godot_tests_fingerprint"
[[ -f "$state" && "$(cat "$state")" == "$fingerprint" ]] && exit 0
echo "$fingerprint" > "$state"

out=$({ tools/lint.sh --quiet && tools/load_check.sh; } 2>&1)
code=$?
[[ $code -eq 0 ]] && exit 0

{
  echo "Lint or load check failed after your changes (tools/lint.sh, tools/load_check.sh). Fix:"
  echo "$out"
} >&2
exit 2
