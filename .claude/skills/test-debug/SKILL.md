---
name: test-debug
description: Debug a failing or flaky game test, or reproduce a bug as a test before fixing it. Use when `tools/run_tests.sh` reports FAIL / TIMEOUT, a test is intermittent, or you are about to fix a behavioural bug (write the failing test first). Covers the failure bundle, --repeat/--seed, trace(), and --play. Complements `domain-testing` (how tests are written).
---

# Debugging game tests

## 1. Read the failure first

A FAIL/TIMEOUT prints its ✗ checks, each actor's final state (`· name at (x, y) health … act …`), any
`t.trace` series (min/max/last) and a `bundle:` path. That JSON holds the full time-stamped `events`
(EventBus topics, `died`, `hit_landed`, `spawned`/`removed`), the final `snapshot` (actors + objects),
`traces` and logged errors. Read it before rerunning anything; it usually names the cause (e.g. no `hit`
event → the shot never fired; target `health` unchanged → it hit cover).

## 2. Narrow, then reproduce

- One test: `tools/run_tests.sh --id=projectile/pistol_shot_wounds` (exact id; `--list` shows ids). Words
  (`tools/run_tests.sh pistol`) are ANDed word-prefixes of id/name/domain/tags and can match more than you
  mean; `--domain=ai` is exact. After a red run, `tools/run_tests.sh --failed` reruns only what failed last
  time (add `--fail-fast` to stop at the first). Run with the Bash sandbox disabled.
- Flaky? `--repeat=10 <words>` names `FLAKY` (some pass) vs `FAILING` (none). `--seed=N` pins every
  `house()` test to one layout to separate layout luck from logic.
- Add `t.trace("gap", value)` inside the wait loop to see *why* a threshold was missed, rerun, read the
  series in the output.
- Turn behaviours off to isolate (`s.switch(&"ai.callouts", false)`, …) rather than editing production code.
- Need a picture? `tools/run_tests.sh --shots <words>` (windowed) saves a PNG per failed test; Read it.
- Suspect the harness itself? `tools/run_tests.sh --self-test`.
- Need to see it live? `godot --path . res://scenes/testing/test_runner.tscn -- --play <words>` opens it
  windowed with the result banner and the overlay toggle bar; Rerun replays it.

## 3. Test bug or code bug?

- Waited a fixed time instead of `t.until(...)`, or acted before the character's facing caught up
  (aim, wait ~0.5 s, then fire) → test bug.
- Logged engine error/warning → real, fix the code (or `expect_log`/`allowed_logs` if it is intended).
- Passes alone, fails after another test → a leaked `static var`; use `set_static`/a switch so it is
  restored, never assign a config holder directly in a test.

## 4. Bugfix = red test first

Before fixing a behavioural bug, write `tests/<domain>/<name>_test.gd` that reproduces it and confirm it
FAILS with the bug's symptom; fix; confirm it PASSES; then run `tools/run_tests.sh --changed --summary` and
the full suite (`--jobs=auto --summary`).

## Keeping output small

Add `--summary`: it prints only the failing tests (✗ lines, actor state, `bundle:`), any
`Logged outside any test` lines and the totals, so there is nothing to trim or delegate. Every run ends
with a `Slowest:` line (wall-clock ms) when a test is suspiciously slow. A hang with no output usually
means the project was never imported (the wrapper does that on a fresh checkout) or a parse error.
