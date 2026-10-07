---
name: godot-debug
description: Verify a change to this Godot project actually loads and runs. Use after editing GDScript or scenes to catch parse/load/startup errors before reporting work done. Runs Godot headless and returns a pass/fail with the exact error lines, delegating the run to a cheap Haiku subagent. For behavioural checks in the running game, use the `godot-drive` skill instead.
---

# Godot Debug — headless load check

Verify that a change compiles, loads, and runs — catching parse errors, missing-resource errors, and
startup runtime errors. This is the fast smoke test. For movement/combat/AI behaviour in the live
game, follow up with the **`godot-drive`** skill.

## Delegate the run to a Haiku subagent

The run is mechanical and its raw output is noisy. Don't run it in your own context. Spawn `Agent`
(general-purpose) with **`model: "haiku"`** and a prompt like:

> In `/Users/athomasson/Documents/projects.nosync/Example_Godot`, run the commands below with the
> Bash sandbox disabled (`dangerouslyDisableSandbox: true` — under the sandbox Godot hangs with no
> output). Do not edit any files. Reply with ONLY: `PASS` or `FAIL`, and if FAIL the matching error
> lines verbatim (file:line included), max 20 lines. No commentary.
>
> [paste the commands from Steps 1–3 below; include Step 4's `--import` first if the change added a
> `class_name` or new script]

Then act on the verdict. If the reply is FAIL or ambiguous, fix the code (or re-run) yourself — the
subagent only reports.

## Step 1 — locate the Godot binary

Not on PATH on this machine:

```bash
GODOT="$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )"
echo "Using: $GODOT"
```

Resolves to `/Applications/Godot_mono.app/Contents/MacOS/Godot`.

## Step 2 — headless smoke test

Loads the main scene + autoloads, runs a few frames, then quits. `--quit-after` guarantees it won't
hang (there is no `timeout` command on macOS). **Sandbox disabled.**

```bash
cd /Users/athomasson/Documents/projects.nosync/Example_Godot
"$GODOT" --headless --path . --quit-after 30 2>&1 | tee /tmp/godot_check.log
```

To check a single script instead of the whole project:

```bash
"$GODOT" --headless --path . --check-only --script scenes/player/player.gd 2>&1
```

## Step 3 — pass/fail by GREPPING the output, not the exit code

Godot exits `0` even when a script fails to parse. Judge by the output:

```bash
grep -nE 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|Cannot infer' /tmp/godot_check.log \
  && echo "FAIL: errors found (see above)" \
  || echo "PASS: no errors — project loads and runs"
```

Error lines include file and line, e.g.:

```
SCRIPT ERROR: Parse Error: Expected expression ... after "=".
   at: GDScript::reload (scenes/player/player.gd:42)
```

A clean run prints only the engine version banner (plus any `print()` output).

## Step 4 — stale class cache after adding a `class_name`

If the output says `Identifier "Foo" not declared` right after you added `class_name Foo`, the
global class cache is stale. Rebuild it, then rerun Step 2 (ignore its `progress_dialog` noise):

```bash
"$GODOT" --headless --path . --import
```

## When to use

- After editing any `.gd` script or `.tscn` scene, before saying the change works.
- To reproduce a parse error the user reports (Step 2 gives the exact file:line).
- As a pre-commit sanity check.

## Limitations

- `--headless` skips rendering, so it won't catch visual issues, and it can't judge behaviour — use
  `godot-drive`.
- Code that hard-requires a display/GPU may log rendering warnings under `--headless`; those are not
  real errors. Focus on `SCRIPT ERROR` / `Parse Error` / `Failed to load` lines.
