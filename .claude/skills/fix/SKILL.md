---
name: fix
description: Fix a bug the user describes by first reproducing it as a failing game test, then fixing the code until it passes. Manual-only — run as `/fix <description of what is going wrong>`.
argument-hint: <description of what is going wrong>
disable-model-invocation: true
model: opus
effort: high
---

# Fix: reproduce with a test, then fix

The bug, as the user described it: **$ARGUMENTS**

If that is empty, or too vague to tell expected from actual behaviour, ask one concise question
before doing anything else.

## 1. Orient

Load `architecture`, then the `domain-<name>` skill for the domain the bug lives in, `domain-testing`
(how a test is written) and `test-debug` (failure bundle, `--repeat`, `--seed`, `trace()`).

## 2. Restate and place it

Write the bug as *expected vs. actual* in one or two lines. Pick the owning domain; the test goes in
`tests/<domain>/<name>_test.gd`. Run `tools/run_tests.sh --list <words>` first — extend an existing test
rather than adding a near-duplicate.

## 3. Reproduce (red)

Write the smallest test that triggers the symptom through the published interfaces only (world/`house()`
plus behaviour switches per `domain-testing`; `--seed=N` if it depends on layout). Run it with
`tools/run_tests.sh --id=<domain>/<name>` (Bash sandbox disabled) and require it to **FAIL**, then check it fails *for the bug's reason*: read the `✗`
lines and the `bundle:` JSON. A parse error, a fixed-sleep race or a harness mistake is not a repro
(`test-debug` §3) — fix the test and rerun. If it passes straight away, the repro is wrong or the bug is
already gone: say so and stop rather than "fixing" anything.

Run this single test inline so its failure output is in your own context.

If the bug cannot be seen headless (purely visual, windowed-only), say so, reproduce it with
`godot-drive` or `--shots` instead, and tell the user the fix ends up with no regression test.

## 4. Fix

Find the root cause and make the smallest change in production code that addresses it. Respect domain
isolation: cross-domain calls only through the interfaces listed in `architecture`. Never loosen, skip or
delete the test to get green, and don't special-case the test's scenario.

## 5. Green

Rerun the test until it PASSES (`--id=<id> --repeat=10` for an intermittent bug; no `FLAKY`). Then run
`tools/run_tests.sh --changed --summary`, and last the full `tools/run_tests.sh --summary --jobs=auto`.
`--summary` prints only the totals plus every FAIL/TIMEOUT with its `✗` and `bundle:` lines (and any
`Logged outside any test` lines), so no subagent is needed to trim the output. If something fails, fix and
rerun just that with `tools/run_tests.sh --failed`. Report unrelated failures; don't paper over them.

## 6. Wrap up

If the fix changed a domain's internals or an interface, update that `domain-<name>` skill (and
`architecture` for an interface). Don't commit unless asked; `analysis-change-verification` is the step
before a commit.

Report: root cause, the test added (path), the red → green result lines, files changed, and anything
left uncovered.
