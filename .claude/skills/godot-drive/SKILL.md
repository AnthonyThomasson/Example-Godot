---
name: godot-drive
description: Verify a BEHAVIOURAL change in this Godot project by launching the game and driving it live through the dev command server (tools/gcmd.py) — movement, a punch landing, a shot penetrating, an interaction firing, AI behaviour. Use only when a headless load check (`godot-debug`) isn't enough. Heavier than godot-debug; delegates log-reading to a cheap subagent.
---

# Godot Drive — live behavioural checks

Run the game and **drive it with the dev command server** to see a behaviour actually happen.
Do the headless load check first with the `godot-debug` skill — don't drive a game that doesn't parse.

## Keep it cheap: delegate the mechanics

Launching, sending command sequences, and reading logs is mechanical and log-heavy. **You (the
parent) decide the scenario and what output proves it; a Haiku subagent runs it and reports back.**
Raw `get_debug_output` / log dumps should never land in your own context.

Spawn `Agent` with `model: "haiku"` (general-purpose), and give it:
- the exact command sequence (verbs below) in order,
- the **marker lines** that prove success (e.g. `Shot penetrated`, `Punch (hand 0) hit`) and any
  that prove failure (`SCRIPT ERROR`, `error:`),
- instructions to run Bash with the sandbox disabled, clean up when done, and reply with **only**:
  verdict per check, the matching log lines (max ~15), and any errors verbatim.

Judge the reply yourself. Only read raw logs directly if the summary is ambiguous.

## Environment caveats

- **Disable the Bash sandbox** for every Godot / `gcmd.py` command (`dangerouslyDisableSandbox:
  true`). Under the sandbox Godot busy-spins at ~100% CPU with no output. MCP `run_project` isn't
  affected.
- **Init hang:** `run_project` occasionally hangs in display/GPU init (empty output, refused
  socket). If it looks dead after ~10s, `mcp__godot__stop_project` and `run_project` again.
- Godot binary: not on PATH; on this machine
  `/Applications/Godot_mono.app/Contents/MacOS/Godot`.

## 1. Launch the game

Prefer the MCP so output can be read back:

```
mcp__godot__run_project(projectPath="/Users/athomasson/Documents/projects.nosync/Example_Godot")
```

Or windowed from Bash (sandbox disabled), logging to a file:

```bash
"$GODOT" --path . > /tmp/godot_run.log 2>&1 &
```

Wait a few seconds and confirm the server is up: look for `[cmd] listening on 127.0.0.1:9080` in
`get_debug_output`, or `grep listening /tmp/godot_run.log`. `get_debug_output` only sees a game the
MCP itself started, and is empty while the process is still initializing.

The command server exists only in an **editor build** and only when
`application/debug/command_port` > 0 (`9080` in `project.godot`). Never in an exported build.

## 2. Send commands with `tools/gcmd.py`

The MCP can launch and observe but cannot open a socket into the game, so this Python client is
the control channel. Each line is a curated verb or, failing that, raw GDScript evaluated against
the command-server node. Sandbox disabled.

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

Verbs: `help, pos, tp X Y, slot N, move up|down|left|right [off], stop, fire, punch, interact,
aim X Y, eval EXPR`. Port resolves as `--port` → `$GODOT_CMD_PORT` → `9080`.

## 3. Read the reaction

Each command replies on the socket (`ok`, a value, or `error: …`) **and** is echoed in the game's
output as `[cmd] <line> -> <reply>`, alongside the gameplay lines it triggers (`Shot penetrated …`,
`Punch (hand 0) hit …`). MCP launches: `get_debug_output`. Bash launches: `tail /tmp/godot_run.log`.

## 4. Clean up

`mcp__godot__stop_project` (or `kill` the Bash pid). `stop_project` hard-kills Godot, so its
`_exit_tree` doesn't run and the **Von decision server it spawned is orphaned** on port 8000 — the
next launch reuses it; to remove it, `pkill -f "von serve"`.

## Limitations

- `aim` warps a real cursor, so it's a no-op headless — use a windowed run.
- For N-match scoring runs use `tools/match.py` instead of hand-driving.
