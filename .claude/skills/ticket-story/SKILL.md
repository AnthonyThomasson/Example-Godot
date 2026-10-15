---
name: ticket-story
description: Work a standard ticket (no `bug` or `spike` label; also `ai`, `harness`, `assets`, `graphics` and `audio`) in seven phases - grill, plan on the ticket, tests first, build, green + feedback gate, audit, report. Invoked from `ticket`.
---

# Ticket: story

Seven phases (`ticket`, "Work in phases"). You run 1, 2, 7, the feedback gate and the findings question; 3–6 may go
to workers, the audit always does. Label `ai`: also `ticket-ai`; `harness`: also `ticket-harness`; `assets` /
`graphics` / `audio`: also `ticket-assets`.

## 1. Orient and grill

Load `architecture` and the `domain-<name>` skills the ticket touches; read the code it names. Answer from the code what
the code can answer. Grill the user (`AskUserQuestion`) until nothing material is open:

- the outcome: what the user or player sees or can do afterwards, and what stays as it is;
- edge cases: wrong moment, nothing to act on, two at once, the thing absent;
- fit: which behaviour it replaces or sits beside, which domains and interfaces it touches;
- tuning and display: tunables, defaults, debug overlays, HUD, sound;
- out of scope, and what "done" means (the behaviour or tests that prove it).

The ticket text is a starting point. Stop when questions would only restate decisions.

## 2. Plan

A plan someone else could build from:

- **Behaviour:** rule by rule, with the grilling's decisions.
- **Design:** per domain, files and types added or changed, cross-domain interfaces used (only those in
  `architecture`), data and tunables with defaults.
- **Tests:** scenarios and test files, one per rule.
- **Phases:** build order and what each produces.
- **Out of scope** and **open risks**.

`ticket-assets`: the plan follows the showroom picks. Revise until accepted. Then `ticket` → "Rebase after
acceptance", "Plan on the ticket", "Show the user".

## 3. Tests first

Before any production code, write the tests (`domain-testing`, `test-debug`). Extend an existing test rather than add a
near-duplicate (`tools/run_tests.sh --list <words>`). One test per plan rule, through published interfaces only. Run
each alone, Bash sandbox disabled (`tools/run_tests.sh --id=<domain>/<name>`); it must **fail for the right reason**
(the feature is missing, not a parse error, race or setup mistake). Passes at once: too loose or already built; tighten
or say so. `git status` shows only test files (plus `sandboxes/showroom/` and any variant switch, `ticket-assets`).
Tell the user which tests are red and why.

## 4. Build

Build the plan phase by phase, in the right domains, through published interfaces only. Never loosen, skip or
special-case a test. Check each phase loads and runs (`godot-run`).

## 5. Green and wrap up

New tests pass (`--repeat=10` if timing-dependent), then `tools/run_tests.sh --changed --summary`, then
`tools/run_tests.sh --summary --jobs=auto`. Touched a per-frame path: `tools/run_tests.sh --domain=perf` on a quiet
machine. An older test now failing is your regression until shown otherwise. Update every changed domain's skill,
`architecture` for an interface, and the `docs/` spec if there is one. Then `ticket` → "Feedback gate".

## 6. Audit

`ticket` → "Audit".

## 7. Report, then feedback or finish

`ticket` → "Report, then feedback or finish".
