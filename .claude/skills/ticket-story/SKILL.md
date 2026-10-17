---
name: ticket-story
description: Work a standard ticket (no `bug` or `spike` label; also `ai`, `harness`, `assets`, `graphics` and `audio`) in seven phases - grill, plan on the ticket, tests first, build, green + feedback gate, audit, report. Invoked from `ticket`.
---

# Ticket: story

Seven phases (`ticket`, "Work in phases"). You run 1, 2, 7, the feedback gate and the findings question; 3–6 may go
to workers, the audit always does. Label `ai`: also `ticket-ai`; `harness`: also `ticket-harness`; `assets` /
`graphics` / `audio`: also `ticket-assets`.

## 1. Orient and grill

Load `architecture` and the `domain-<name>` skills the ticket touches; read the code it names. Run `ticket` → "Triage
checks". Answer from the code what the code can answer.

Grill with `mattpocock-skills:grilling` and `mattpocock-skills:domain-modeling`: each round asks the whole frontier
(every question whose prerequisites are settled), a recommended answer on each, through `AskUserQuestion` up to four
at a time; a term the grilling sharpens goes in `GLOSSARY.md`, a hard-to-reverse decision with a real trade-off in
`docs/adr/`. A question only something runnable can settle (does this state model feel right, how should it behave):
a throwaway sandbox under `mattpocock-skills:prototype`'s rules (named as a prototype, kept on a `prototype/<name>`
branch, the verdict on the ticket). Grill until nothing material is open:

- the outcome: what the user or player sees or can do afterwards, and what stays as it is;
- edge cases: wrong moment, nothing to act on, two at once, the thing absent;
- fit: which behaviour it replaces or sits beside, which domains and interfaces it touches;
- tuning and display: tunables, defaults, debug overlays, HUD, sound;
- out of scope, and what "done" means (the behaviour or tests that prove it).

The ticket text is a starting point. Stop when questions would only restate decisions.

## 2. Plan

A brief and a plan someone else could build from (the shape is `ticket` → "Brief and plan on the ticket"):

- **Agent Brief:** current behaviour; **desired behaviour** rule by rule, with the grilling's decisions; key
  interfaces (only those in `architecture`) and tunables with defaults; **acceptance criteria**, one per rule, each
  naming the test scenario and the seam it runs at (the world or `house()` it builds, the switches on); out of scope.
- **Plan:** per domain, files and types added or changed, data; test files; phases (build order and what each
  produces); open risks.

`ticket-assets`: the plan follows the showroom picks. Revise until accepted. Then `ticket` → "Rebase after
acceptance", "Brief and plan on the ticket", "Show the user".

## 3. Tests first

Before any production code, write the tests (`domain-testing`, `test-debug`; `mattpocock-skills:tdd` for what makes a
test worth keeping: behaviour through published interfaces, expected values from the brief, never recomputed the way
the code computes them). All of them come before code on purpose, unlike `tdd`'s one-test-at-a-time loop: they are
the brief's acceptance criteria, fixed at acceptance. Extend an existing test rather than add a
near-duplicate (`tools/run_tests.sh --list <words>`). One test per acceptance criterion, through published interfaces only. Run
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
