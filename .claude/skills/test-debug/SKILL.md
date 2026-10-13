---
name: test-debug
description: Debug a failing or flaky game test - read the failure bundle, narrow it down, tell a test bug from a code bug. Use when `tools/run_tests.sh` reports FAIL / TIMEOUT or a test is intermittent. Fixing a bug is `fix`.
---

# Debugging game tests

Runner flags and selection: `domain-testing`, "Running tests". Run Godot with the Bash sandbox disabled.

## 1. Read the failure first

A FAIL/TIMEOUT prints its ✗ checks, each actor's final state (`· name at (x, y) health … act …`), the `t.trace` series
(min/max/last) and a `bundle:` path. The bundle JSON has the time-stamped `events` (EventBus topics, `died`,
`hit_landed`, `spawned`/`removed`), the final `snapshot` (actors + objects), `traces` and logged errors. Read it before
rerunning; it usually names the cause (no `hit` event: the shot never fired; target `health` unchanged: it hit cover).
Add `--summary` to keep output to the failures and totals. A hang with no output: the project was never imported, or a
parse error.

## 2. Narrow it down

- One test: `--id=<domain>/<name>`; then `--failed` (with `--fail-fast` to stop at the first).
- Flaky: `--repeat=10 <words>` names `FLAKY` (some pass) vs `FAILING` (none). `--seed=N` pins every `house()` layout to
  separate layout luck from logic.
- `t.trace("gap", value)` in the wait loop shows *why* a threshold was missed; rerun and read the series.
- Turn behaviours off to isolate (`s.switch(&"ai.callouts", false)`) rather than editing production code.
- A picture: `--shots <words>` (windowed) saves a PNG per failed test; Read it.
- Suspect the harness: `--self-test`.
- Watch it live: `"$GODOT" --path . res://scenes/testing/test_runner.tscn -- --play <words>` (`$GODOT`: `godot-run`)
  (windowed, result banner, overlay bar, Rerun).
- Suspiciously slow: every run ends with a `Slowest:` line (wall-clock ms).

## 3. Test bug or code bug?

- Waited a fixed time instead of `t.until(...)`, or fired before the facing caught up (aim, wait ~0.5 s, fire): test bug.
- An engine error/warning logged: real; fix the code (or `expect_log` / `allowed_logs` if intended).
- Passes alone, fails after another test: a leaked `static var`. Use `set_static` or a switch so it is restored; never
  assign a config holder directly in a test.
