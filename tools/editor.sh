#!/usr/bin/env bash
# Open a Godot editor on a worktree and tag its game runs with a ticket name.
#
#   tools/editor.sh TICKET-123                 editor on this checkout, ticket shown in the setup menu
#   tools/editor.sh TICKET-123 --autorun       also presses Play once the editor is up
#   tools/editor.sh TICKET-123 --port=9123     command-server port (default: 9080 + hash(ticket) % 500, moved up to the next free one)
#   tools/editor.sh TICKET-123 /path/worktree  a different worktree
#
# The ticket travels as GAME_TICKET (the editor's game child inherits it; Main shows it atop the
# setup menu). The command server listens on GODOT_CMD_PORT, so worktrees don't collide:
#   python3 tools/gcmd.py --port <printed port> 'scene().name'
# The editor runs detached; its log path and pid are printed.
set -euo pipefail

ticket="${1:-}"
[[ -n "$ticket" && "$ticket" != --* ]] || { echo "usage: tools/editor.sh TICKET [--autorun] [--port=N] [path]" >&2; exit 2; }
shift
autorun=""; port=""; path="$(cd "$(dirname "$0")/.." && pwd)"
for a in "$@"; do
  case "$a" in
    --autorun) autorun=1 ;;
    --port=*) port="${a#--port=}" ;;
    *) path="$(cd "$a" && pwd)" ;;
  esac
done
[[ -f "$path/project.godot" ]] || { echo "no project.godot in $path" >&2; exit 2; }

GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
[[ -n "$GODOT" ]] || { echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2; exit 2; }

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
log="${TMPDIR:-/tmp}/editor_${ticket//[^A-Za-z0-9._-]/_}.log"

export GAME_TICKET="$ticket" GODOT_CMD_PORT="$port"
[[ -n "$autorun" ]] && export GAME_AUTORUN=1
nohup "$GODOT" --editor --path "$path" > "$log" 2>&1 &
echo "editor pid $! | ticket $ticket | command port $port | log $log"
