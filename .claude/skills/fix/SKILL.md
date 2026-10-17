---
name: fix
description: Fix a bug - reproduce it as a failing game test, fix the root cause, then green. Use whenever asked to fix a bug, for a `bug` ticket (via `ticket-bug`), or as `/fix <what is going wrong>`.
argument-hint: <description of what is going wrong>
effort: high
---

# Fix

The bug: **$ARGUMENTS**

Empty, or too vague to tell expected from actual: ask one concise question first.

1. **Orient.** Load `architecture`, the `domain-<name>` skill where the bug lives, `domain-testing` and `test-debug`.
2. **Place it.** Write it as *expected vs. actual* in one or two lines. The test goes in
   `tests/<domain>/<name>_test.gd`; check `tools/run_tests.sh --list <words>` first and extend an existing test rather
   than add a near-duplicate.
3. **Red.** Write the smallest test that triggers the symptom through published interfaces only (world/`house()` plus
   behaviour switches; `--seed=N` if it depends on layout). Run it inline, Bash sandbox disabled:
   `tools/run_tests.sh --id=<domain>/<name>`. It must FAIL *for the bug's reason*: read the `✗` lines and the `bundle:`
   JSON. A parse error, fixed-sleep race or harness mistake is not a repro (`test-debug`, "Test bug or code bug?"): fix
   the test and rerun. Passes at once: the repro is wrong or the bug is gone; say so and stop. Not visible headless
   (purely visual, windowed-only): say so, reproduce with `godot-run` or `--shots`, and tell the user the fix has no
   regression test.
4. **Fix** the root cause with the smallest production change. Cross-domain calls only through `architecture`'s
   interfaces. Never loosen, skip or delete the test, or special-case its scenario. The cause is not plain from the red
   test and the bundle: follow `mattpocock-skills:diagnosing-bugs` phases 2–4 (shrink the repro until every part is
   load-bearing; 3–5 ranked, falsifiable hypotheses shown to the user before testing; one variable per probe, logs
   tagged `[DEBUG-<id>]` and grepped out before green). A perf regression: its perf branch, a baseline measured on a
   quiet machine first, then bisect.
5. **Green.** The test passes (`--id=<id> --repeat=10` for an intermittent bug; no `FLAKY`). Then
   `tools/run_tests.sh --changed --summary`, last `tools/run_tests.sh --summary --jobs=auto`. On a failure, fix and rerun
   with `tools/run_tests.sh --failed`. Report unrelated failures; don't paper over them.
6. **Wrap up.** A changed domain internal or interface: update that `domain-<name>` skill (and `architecture` for an
   interface). Don't commit unless asked. Report: root cause (the hypothesis that proved right), the test added (path), red →
   green lines, files changed, anything uncovered.
