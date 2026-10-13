#!/usr/bin/env bash
# GDScript analyzer lint, headless and fast (a few seconds): exits 1 when any script has a warning or error the
# editor's Debugger > Errors tab would list (UNUSED_VARIABLE, INTEGER_DIVISION, SHADOWED_GLOBAL_IDENTIFIER, ...),
# printing them per file; 0 when clean. tools/run_tests.sh runs it first. The warning levels are the project's
# (Project Settings > GDScript > Warnings). Fix the code; silencing a warning (@warning_ignore, a project setting)
# is a last resort, see the audit skill.
#   tools/lint.sh [--quiet] [PATH...]    --quiet prints nothing when clean; PATHs (scenes/x.gd or res://scenes/x.gd)
#                                        lint only those scripts
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
[[ -n "$GODOT" ]] || { echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2; exit 2; }
# A fresh checkout has no class cache, and without it every script that names a class_name fails to parse.
if [[ ! -f .godot/global_script_class_cache.cfg ]]; then
  echo "importing the project (first run in this checkout)..." >&2
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
flags=(); only=()
for a in "$@"; do
  case "$a" in
    --*) flags+=("$a") ;;
    *) only+=("res://${a#res://}") ;;
  esac
done
extra=(); [[ ${#only[@]} -gt 0 ]] && extra=(-- "--only=$(IFS=,; echo "${only[*]}")")
out=$(mktemp -d "${TMPDIR:-/tmp}/lint.XXXXXX")
# --debug is what makes the engine report analyzer warnings at all; stdin is closed so a script error does not
# park the process at the debugger prompt.
"$GODOT" --headless --debug --path . res://tools/lint_scripts.tscn ${extra[@]+"${extra[@]}"} </dev/null >"$out/lint.log" 2>&1
GODOT="$GODOT" python3 tools/lint_report.py "$out/lint.log" ${flags[@]+"${flags[@]}"}
