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

> In the worktree root (`cd` to the checkout you are working in, never another copy), run the commands below with the
> Bash sandbox disabled (`dangerouslyDisableSandbox: true` — under the sandbox Godot hangs with no
> output). Do not edit any files. Reply with ONLY: `PASS` or `FAIL`, and if FAIL the matching error
> lines verbatim (file:line included), max 20 lines. No commentary.
>
> [paste the commands from Steps 1–2 below; include Step 3's `--import` first if the change added a
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

## Step 2 — run the load check

One script loads the main scene and autoloads, runs a few frames, quits, and reads the engine log. It exits 1 and prints the
lines on **any** engine error or warning (parse errors, failed loads, runtime script errors, anything logged while the process
shuts down); 0 means clean. **Sandbox disabled.** Godot exits `0` even when a script fails to parse, which is why the verdict
comes from the log, not the exit code.

```bash
tools/load_check.sh              # headless
tools/load_check.sh --windowed   # with a window (rendering warnings count too)
```

For GDScript warnings (unused variable, integer division, shadowed names; headless runs never print them) run
`tools/lint.sh` as well; `tools/run_tests.sh` does so first.

A failure prints entries like `✗ script error: Parse Error: Expected expression … (res://scenes/character/character.gd:42)` and the
log path. To check a single script instead: `"$GODOT" --headless --path . --check-only --script scenes/character/character.gd`.

Godot's own end-of-process leak report ("ObjectDB instances leaked at exit", "resources still in use at exit", …) is printed as a
`NOTE` and does not fail the check; `--strict-exit` fails it too. Everything else fails.

## Step 3 — stale class cache after adding a `class_name`

If the output says `Identifier "Foo" not declared` right after you added `class_name Foo`, the
global class cache is stale. Rebuild it, then rerun Step 2 (the import's own `progress_dialog` noise is not part of the check):

```bash
"$GODOT" --headless --path . --import
```

## Next rung

A clean load only proves it parses. For behaviour run `tools/run_tests.sh --changed --summary` (only the domains your edit can break; add `--jobs=auto` for a big one; see the `domain-testing` and `test-debug` skills) before reaching for live driving. `tools/run_tests.sh` also imports a fresh checkout by itself, so after a `class_name` change it is often the only check you need; keep this skill for scene/autoload-only edits and quick parse errors.

## When to use

- After editing any `.gd` script or `.tscn` scene, before saying the change works.
- To reproduce a parse error the user reports (Step 2 gives the exact file:line).
- As a pre-commit sanity check.

## Limitations

- `--headless` skips rendering, so it won't catch visual issues, and it can't judge behaviour — use
  `godot-drive`.
- A warning that only a particular renderer or display logs fails the check in that mode, headless or windowed: run both
  (`--windowed`) when a change touches rendering.
