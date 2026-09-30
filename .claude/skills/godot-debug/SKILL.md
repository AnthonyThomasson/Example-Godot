---
name: godot-debug
description: Verify a change to this Godot project actually loads and runs. Use after editing GDScript or scenes to catch parse/load/runtime errors before reporting work done. Runs Godot headless via the terminal to capture real error output, then optionally launches the game window and drives it live via the command server for behavioural checks.
---

# Godot Debug & Verify

Verify that a change to this Godot 4 project compiles, loads, and runs — catching
parse errors, missing-resource errors, and startup runtime errors — and, when the
change affects behaviour, drive the running game to see it actually happen.

## Two ways to run the game (and how they capture output)

| Launch | Output channel | Best for |
|---|---|---|
| **Bash, headless** (`Godot --headless --path .`) | stdout/stderr you pipe to a log | parse/load/startup errors — the fast smoke test |
| **MCP** (`mcp__godot__run_project`) | `mcp__godot__get_debug_output` | a real window + live driving via the command server |

`get_debug_output` **does** work — but only for a game the MCP itself started with
`run_project`; it returns that process's full stdout (engine banner, `print()`s, and
the `[cmd] …` command echoes). It cannot see a game you launched yourself from Bash,
and it returns empty while the process is still initializing (or if it hung — see the
init-hang caveat below).

### Environment caveat: disable the Bash sandbox when launching Godot

In this environment, Godot launched from the Bash tool under the default sandbox
**busy-spins at ~100% CPU and produces no output** (even `--version` never returns).
Run every Godot command below with the sandbox disabled (`dangerouslyDisableSandbox:
true` on the Bash call). The MCP's `run_project` does not go through the Bash sandbox.

### Init-hang caveat (MCP launches)

`run_project` occasionally hangs Godot in display/GPU init: the process sits at
~100% CPU, `get_debug_output` stays empty, and the command socket never opens. It is
intermittent, not a broken tool. If a launch looks dead after ~10s (empty output +
refused socket), `mcp__godot__stop_project` and `run_project` again — it clears on
retry.

## Step 1 — locate the Godot binary

Not on PATH on this machine. Resolve it once:

```bash
GODOT="$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )"
echo "Using: $GODOT"
```

On this machine it resolves to `/Applications/Godot_mono.app/Contents/MacOS/Godot`.

## Step 2 — headless smoke test (catches parse/load/startup errors)

Loads the main scene + autoloads, runs a few frames, then quits. `--quit-after`
guarantees it won't hang (there is no `timeout` command on macOS). **Run with the
Bash sandbox disabled** (see caveat above).

```bash
cd /Users/athomasson/Documents/projects.nosync/Example_Godot
"$GODOT" --headless --path . --quit-after 30 2>&1 | tee /tmp/godot_check.log
```

To check a single script instead of the whole project:

```bash
"$GODOT" --headless --path . --check-only --script scenes/player/player.gd 2>&1
```

## Step 3 — decide pass/fail by GREPPING the output, not the exit code

Godot exits `0` even when a script fails to parse, so the exit code is useless
here. Judge by the output:

```bash
grep -nE 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|Cannot infer' /tmp/godot_check.log \
  && echo "❌ errors found (see above)" \
  || echo "✅ no errors — project loads and runs"
```

Error lines include the file and line, e.g.:

```
SCRIPT ERROR: Parse Error: Expected expression ... after "=".
   at: GDScript::reload (scenes/player/player.gd:42)
```

A clean run prints only the engine version banner (plus any `print()` output).

**New `class_name` scripts:** if the output says `Identifier "Foo" not declared`
right after you added `class_name Foo`, the global class cache is just stale.
Rebuild it, then rerun Step 2 (ignore its `progress_dialog` error noise):

```bash
"$GODOT" --headless --path . --import
```

## Step 4 — behavioural check by driving the running game

For behaviour a smoke test can't judge (movement, a punch landing, a shot
penetrating, an interaction firing), run the game and **drive it with the dev
command server** — the same channel described in `AGENTS.md`.

### 4a. Launch the game

Prefer the MCP so you can read output back:

```
mcp__godot__run_project(projectPath="/Users/athomasson/Documents/projects.nosync/Example_Godot")
```

Or launch windowed from Bash (sandbox disabled), logging to a file you can tail:

```bash
"$GODOT" --path . > /tmp/godot_run.log 2>&1 &
```

Either way, wait a few seconds and confirm the server came up. With the MCP, look
for `[cmd] listening on 127.0.0.1:9080` in `get_debug_output`; from Bash, `grep
listening /tmp/godot_run.log`.

The command server only exists in an **editor build** and only when
`application/debug/command_port` > 0 (it is `9080` in `project.godot`). It never
exists in an exported build.

### 4b. Send commands with `tools/gcmd.py`

The MCP can launch and observe but **cannot open a socket into the game**, so this
Python client is the control channel. Each line is a curated verb or, failing that,
raw GDScript evaluated against the command-server node. Run it with the sandbox
disabled.

```bash
cd /Users/athomasson/Documents/projects.nosync/Example_Godot
python3 tools/gcmd.py help                 # list the verbs
python3 tools/gcmd.py pos                   # -> (440.0, 470.0)
python3 tools/gcmd.py "tp 600 300"          # teleport the player
python3 tools/gcmd.py "move right"          # hold a direction …
python3 tools/gcmd.py "move right off"      # … and release it (or: stop)
python3 tools/gcmd.py "slot 3"              # select item slot 1-9 (3 = pistol)
python3 tools/gcmd.py fire                  # LMB (pistol) — prints a Shot … line
python3 tools/gcmd.py punch                 # F
python3 tools/gcmd.py interact              # Space
python3 tools/gcmd.py "aim 700 300"         # windowed runs only (needs a real cursor)
python3 tools/gcmd.py 'player().speed'      # arbitrary GDScript; helpers: player(), scene(), node(path)
```

Verbs: `help, pos, tp X Y, slot N, move up|down|left|right [off], stop, fire,
punch, interact, aim X Y, eval EXPR`. Port resolves as `--port` → `$GODOT_CMD_PORT`
→ `9080`.

### 4c. Read the reaction

Each command replies on the socket (`ok`, a value, or an `error: …`) **and** is
echoed in the game's output as `[cmd] <line> -> <reply>`, alongside the gameplay
lines it triggers (`Shot penetrated …`, `Punch (hand 0) hit …`). For MCP launches
read these with `get_debug_output`; for Bash launches `tail /tmp/godot_run.log`.

### 4d. Clean up

`mcp__godot__stop_project` (or `kill` the Bash pid). Note: `stop_project`
hard-kills Godot, so its `_exit_tree` doesn't run and the **Von decision server it
spawned is orphaned** on port 8000 — the next launch reuses that server, but if you
want it gone, `pkill -f "von serve"`.

## When to use

- After editing any `.gd` script or `.tscn` scene, before saying the change works.
- To reproduce a parse error the user reports (Step 2 gives the exact file:line).
- To confirm a behavioural change actually works in the running game (Step 4).
- As a pre-commit sanity check.

## Limitations

- `--headless` skips rendering, so it won't catch purely visual issues, and `aim`
  (which warps a real cursor) is a no-op headless — use a windowed run for those.
- Code that hard-requires a display/GPU may log rendering warnings under
  `--headless`; those are not real errors. Focus on `SCRIPT ERROR` / `Parse Error`
  / `Failed to load` lines.
