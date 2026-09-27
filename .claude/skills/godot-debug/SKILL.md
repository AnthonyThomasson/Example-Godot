---
name: godot-debug
description: Verify a change to this Godot project actually loads and runs. Use after editing GDScript or scenes to catch parse/load/runtime errors before reporting work done. Runs Godot headless via the terminal to capture real error output, then optionally launches the game window for visual checks.
---

# Godot Debug & Verify

Verify that a change to this Godot 4 project compiles, loads, and runs — catching
parse errors, missing-resource errors, and startup runtime errors.

## IMPORTANT: the MCP `get_debug_output` tool does not work here

In this environment `mcp__godot__run_project` launches a game window (you can see
it), but `mcp__godot__get_debug_output` returns **"No active Godot process"** even
while the game is running — it cannot retrieve the output. Do **not** build
verification on `get_debug_output`.

Instead, capture real output by running the Godot binary **headless from the
terminal** (Bash). That prints script/parse/load errors to stderr where you can
read them.

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
guarantees it won't hang (there is no `timeout` on macOS).

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

## Step 4 (optional) — visual / interactive check

For behavior you can only judge by looking (animation, layout, a punch landing),
launch the real window with the MCP tool:

```
mcp__godot__run_project(projectPath="/Users/athomasson/Documents/projects.nosync/Example_Godot")
```

Then verify **visually** — screenshot it or ask the user what they see. Remember:
you cannot read its output via `get_debug_output`, so the user (or a screenshot)
is the feedback channel for runtime behavior. Use `mcp__godot__stop_project` to
close it.

## When to use

- After editing any `.gd` script or `.tscn` scene, before saying the change works.
- To reproduce a parse error the user reports (Step 2 gives the exact file:line).
- As a pre-commit sanity check.

## Limitations

- `--headless` skips rendering, so it won't catch purely visual issues — use Step 4.
- Code that hard-requires a display/GPU may log rendering warnings under
  `--headless`; those are not real errors. Focus on `SCRIPT ERROR` / `Parse Error`
  / `Failed to load` lines.
