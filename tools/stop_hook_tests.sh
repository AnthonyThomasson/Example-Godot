#!/usr/bin/env bash
# Claude Code Stop hook: when the turn changed game code, run the affected tests and, on failure,
# block the stop (exit 2) so the agent sees the failures and keeps working.
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

out=$(tools/run_tests.sh --changed 2>&1)
code=$?
[[ $code -eq 0 ]] && exit 0

{
  echo "Game tests failed after your changes (tools/run_tests.sh --changed). Fix them or the tests:"
  echo "$out" | grep -E '^(==|FAIL|TIMEOUT|        [✗·~]|        bundle:|        shot:|Logged outside|[0-9]+ passed)' 
  echo "See the test-debug skill; bundles hold the event log and final state."
} >&2
exit 2
