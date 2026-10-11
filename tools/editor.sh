#!/usr/bin/env bash
# Open a Godot editor on a worktree, named after it, unless one is already running there.
#
#   tools/editor.sh                       editor on this checkout, named after the worktree directory
#   tools/editor.sh --autorun             also presses Play once the editor is up
#   tools/editor.sh --port=9123           command-server port (default: 9080 + hash(name) % 500, moved up to the next free one)
#   tools/editor.sh /path/worktree        a different worktree (named after its directory)
#   tools/editor.sh NAME                  override the name (any argument that is not a directory)
#
# If an editor is already open on that worktree nothing is started: its pid, port and log are
# printed instead (the port is read from the running editor's GODOT_CMD_PORT).
# The name travels as GAME_TICKET (the editor's game child inherits it; Main shows it atop the
# setup menu). The command server listens on GODOT_CMD_PORT, so worktrees don't collide:
#   python3 tools/gcmd.py --port <printed port> 'scene().name'
# The editor runs detached; its log path and pid are printed.
set -euo pipefail

autorun=""; port=""; ticket=""; path="$(cd "$(dirname "$0")/.." && pwd)"
for a in "$@"; do
  case "$a" in
    --autorun) autorun=1 ;;
    --port=*) port="${a#--port=}" ;;
    --*) echo "usage: tools/editor.sh [NAME] [--autorun] [--port=N] [path]" >&2; exit 2 ;;
    *) if [[ -d "$a" ]]; then path="$(cd "$a" && pwd)"; else ticket="$a"; fi ;;
  esac
done
ticket="${ticket:-$(basename "$path")}"
[[ -f "$path/project.godot" ]] || { echo "no project.godot in $path" >&2; exit 2; }

GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
[[ -n "$GODOT" ]] || { echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2; exit 2; }

log="${TMPDIR:-/tmp}/editor_${ticket//[^A-Za-z0-9._-]/_}.log"

# Already open on this worktree? Report it instead of starting a second editor.
running=$(pgrep -f -- "--editor --path $path( |\$)" | head -1 || true)
if [[ -n "$running" ]]; then
  recorded_port="$(ps eww -p "$running" 2>/dev/null | tr ' ' '\n' | sed -n 's/^GODOT_CMD_PORT=//p' | head -1)"
  recorded_port="${recorded_port:-default (not started by this script)}"
  echo "editor already running | pid $running | name $ticket | command port $recorded_port | log $log"
  exit 0
fi

# A fresh worktree has no import cache (.godot/ is untracked); import before the editor opens.
if [[ ! -d "$path/.godot" ]]; then
  echo "importing $path (first run in this worktree)..."
  "$GODOT" --headless --path "$path" --import > /dev/null 2>&1 || true
fi

# Port: hash of the ticket (stable per ticket), moved up to the next free one so worktrees never share.
if [[ -z "$port" ]]; then
  base=$(( 9080 + $(printf '%s' "$ticket" | cksum | cut -d' ' -f1) % 500 ))
  port=$(python3 - "$base" <<'PY'
import socket, sys
p = int(sys.argv[1])
while True:
    with socket.socket() as s:
        try:
            s.bind(("127.0.0.1", p)); break
        except OSError:
            p += 1
print(p)
PY
)
fi

export GAME_TICKET="$ticket" GODOT_CMD_PORT="$port"
[[ -n "$autorun" ]] && export GAME_AUTORUN=1
nohup "$GODOT" --editor --path "$path" > "$log" 2>&1 &
echo "editor pid $! | name $ticket | command port $port | log $log"
