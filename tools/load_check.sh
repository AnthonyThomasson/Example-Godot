#!/usr/bin/env bash
# Headless start-up check: load the project's main scene and autoloads, run a few frames, quit. Exits 1 on ANY
# engine error or warning in the log (parse errors, failed loads, runtime script errors, shutdown errors),
# printing them; 0 when clean. Engine end-of-process leak lines are a NOTE unless --strict-exit.
#   tools/load_check.sh [--strict-exit] [--windowed]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
[[ -n "$GODOT" ]] || { echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2; exit 2; }
HEADLESS=--headless; STRICT=
for a in "$@"; do
  case "$a" in
    --windowed) HEADLESS= ;;
    --strict-exit) STRICT=--strict-exit ;;
  esac
done
out=$(mktemp -d "${TMPDIR:-/tmp}/load_check.XXXXXX")
"$GODOT" $HEADLESS --path . --quit-after 30 --log-file "$out/godot.log" >"$out/stdout.txt" 2>&1
code=$?
python3 tools/scan_godot_log.py "$out/godot.log" $STRICT || code=1
[[ $code -eq 0 ]] && echo "PASS: project loads and runs with no errors or warnings" || echo "FAIL (log: $out/godot.log)"
exit $code
