---
name: godot-run
description: Check a change loads (headless load check, lint) and, when a test cannot show it, run the game and drive it live with `tools/gcmd.py`. Use after editing GDScript or scenes, before reporting work done, and to watch behaviour in the running game.
---

# Godot run

**Bash sandbox disabled** (`dangerouslyDisableSandbox: true`) for every Godot, `tools/*.sh` and `gcmd.py` command:
under the sandbox Godot busy-spins with no output.

Godot is not on PATH; the scripts find it themselves. For a direct call:

```bash
GODOT="$( command -v godot || command -v godot4 || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )"
# on this machine: /Applications/Godot_mono.app/Contents/MacOS/Godot
```

**Keep logs out of your context:** for a log-heavy run, spawn `Agent` with `model: "haiku"` giving it the worktree root,
the exact commands, the marker lines for success/failure and "sandbox disabled, edit nothing, reply only verdict + up
to ~15 matching lines verbatim". Judge the reply yourself; fix or rerun yourself on FAIL or ambiguity.

## 1. Load check

```bash
tools/load_check.sh               # headless: main scene + autoloads, a few frames, quit
tools/load_check.sh --windowed    # with a window: rendering warnings count too
tools/load_check.sh --strict-exit # also fail on the engine's exit leak report (otherwise a NOTE)
tools/lint.sh [paths]             # GDScript analyzer warnings, which headless runs never print
```

- `load_check.sh` exits 1 and prints every engine error or warning in the log (`✗ script error: Parse Error: … (res://….gd:42)`
  plus the log path); 0 = clean. The verdict comes from the log because Godot exits 0 on a parse error.
- A warning only one renderer or display logs fails only in that mode: run `--windowed` too when a change touches rendering.
- `Identifier "Foo" not declared` right after adding `class_name Foo`: stale class cache. Run
  `"$GODOT" --headless --path . --import` (its `progress_dialog` noise is not a failure), then the check again.
- One script: `"$GODOT" --headless --path . --check-only --script scenes/character/character.gd`.
- Lint: fix the code; silencing a warning is a last resort (`audit`, step 5).
- A clean load only proves it parses. **Prefer a test** for behaviour (`tools/run_tests.sh --changed --summary`, which
  imports a fresh checkout itself). Drive the live game only to explore or for what a puppet cannot reach; N-match
  scoring is `tools/match.py`.

## 2. Launch

Load check first: never drive a game that doesn't parse.

- Worktree editor: `tools/editor.sh --autorun` (presses Play; `show-me`). It prints `editor pid … | command port <port> |
  log <log>` (`$TMPDIR/editor_<worktree>.log`), or `editor already running` with the same fields. Its port is per
  worktree (`--port=N` to choose), so pass `--port <port>` to `gcmd.py`.
- Or from Bash, logging to a file: `"$GODOT" --path . > "$TMPDIR/godot_run.log" 2>&1 &` (port 9080).
- Ready when the log shows `[cmd] listening on 127.0.0.1:<port>`. Nothing after ~10 s (display/GPU init hang): kill it
  and launch again.
- The command server runs only from the editor binary, with a port (`GODOT_CMD_PORT`, else
  `application/debug/command_port` = 9080). Never in an exported build.

## 3. Drive with `tools/gcmd.py`

`python3 tools/gcmd.py [--port N] "<line>"`; port = `--port`, else `$GODOT_CMD_PORT`, else 9080. A line is a verb, or
else a GDScript expression evaluated on the command-server node (helpers `player()`, `scene()`, `node(path)`).

| Verb | Does |
|---|---|
| `help` | list the verbs |
| `pos` / `tp X Y` | player position / teleport |
| `move up\|down\|left\|right [off]`, `stop` | hold or release a direction; release all |
| `slot N` | select item slot 1–9 |
| `fire`, `punch`, `kick`, `reload`, `interact`, `crouch` | LMB, F, V, R, Space, C |
| `aim X Y` | warp the cursor to a world point (windowed only; a no-op headless) |
| `match` | one-line status: each combatant's health/act/alive, verdict, elapsed s |
| `ai` | every NPC's brain as JSON: state text Von saw, menus and pick, contacts (hostile + why, visible, distance), commitment timers, pathing. Use it before guessing from logs |
| `restart [seed]` | reload straight into a new match, optional layout seed |
| `menu` | back to the setup window |
| `eval EXPR` | GDScript, e.g. `eval player().speed` |

## 4. Read the log

Each command replies on the socket (`ok`, a value, `error: …`) and is echoed in the game log as `[cmd] <line> -> <reply>`,
next to the gameplay lines it caused (`Shot penetrated …`, `Punch (hand 0) hit …`). `tail` the editor log or
`$TMPDIR/godot_run.log`. Failure markers: `SCRIPT ERROR`, `error:`.

## 5. Clean up

`kill` the Bash-launched pid (leave a `show-me` editor open). A hard kill skips `_exit_tree`, so the Von decision server
it spawned (port 8000) is orphaned: **always `pkill -f "von serve"` after one.** An orphaned server answers HTTP but its
stdout pipe is dead, so every decision fails (`422 Failed to load Option-Marker decision weights … [Errno 32] Broken
pipe`) and every NPC sits in `HOLD`.
