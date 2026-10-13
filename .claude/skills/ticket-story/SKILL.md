---
name: ticket-story
description: How to field a standard ticket, one with no `bug` or `spike` label (a feature, change or other piece of work). Grill the user about the details, build a detailed plan and add it to the ticket once accepted, write the tests first and see them fail, build it, then ask for feedback. Invoked from the `ticket` skill.
---

# Ticket: story

A story is ordinary work: something to build or change. It runs in seven phases, in order, through
`orchestration` (see the `ticket` skill, "Work in phases"). Phases 1, 2 and 7 talk to the user, so you
(the coordinator) run them yourself; phases 3 to 6 are build phases you may dispatch to workers, and phase 6,
the audit, is always an agent's.

If the ticket carries the `ai` label as well, also follow `ticket-ai` for the test phase (its §2–4: scenarios
from the real world, rest of the AI left on, red before code).

## 1. Orient and grill

Load `architecture` and the `domain-<name>` skills for the domains the ticket touches. Read the code the ticket
names so you ask informed questions; answer from the code what the code can answer instead of asking.

Then **grill the user** about the ticket until nothing material is left open. Use `AskUserQuestion`, a few
questions at a time, each one specific, with your recommended answer first. Cover:

- the outcome: what the user or player sees or can do afterwards, and what stays as it is;
- the edge cases: the wrong moment, nothing to act on, two at once, the thing being absent;
- how it fits what exists: which behaviour it replaces or sits next to, which domains and interfaces it touches;
- how it is tuned and shown: tunables, defaults, debug overlays, HUD, sound;
- what is out of scope, and what "done" means (the behaviour or tests that prove it).

Take the ticket text as the starting point, not the answer. Stop grilling when your questions would only
restate what is already decided; do not pad it.

## 2. Plan, and put it on the ticket

Write a detailed plan of **everything that will be built**, concrete enough that someone else could build it:

- **Behaviour**: what it does, rule by rule, with the decisions made in the grilling.
- **Design**: per domain, the files and types added or changed, the cross-domain interfaces used
  (only the sanctioned ones in `architecture`), data and tunables with their defaults.
- **Tests**: the scenarios and which test files, so each rule above has one.
- **Phases**: the build order and what each phase produces.
- **Out of scope** and **open risks**.

Show the plan and revise it until the user accepts it. **Once they accept**, add it to the ticket's content:
read the current body (`gh issue view <n> --json body`), keep it exactly as it is, and append the plan under a
`## Plan` heading with `gh issue edit <n> --body-file <file>` (write the file in the scratchpad directory).
Re-read the ticket afterwards to check the body is the original plus the plan. Don't edit the ticket before
the plan is accepted, and don't drop or reword what is already there.

## 3. Tests first

Write the tests that verify what the plan builds, before any production code. Use `domain-testing` (how a test
is written) and `test-debug`; extend an existing test rather than adding a near-duplicate
(`tools/run_tests.sh --list <words>`). One test per rule of the plan, through the published interfaces only.

Run each new test on its own, with the Bash sandbox disabled (`tools/run_tests.sh --id=<domain>/<name>`), and
require it to **fail for the right reason**: the feature is missing, not a parse error, a race or a setup
mistake. A test that passes straight away is too loose or the behaviour already exists; tighten it or say so.
`git status` should show only test files before you go on. Tell the user which tests are red and why.

## 4. Build

Build the plan, phase by phase, in the right domains through the published interfaces only. Never loosen,
skip or special-case a test to get green. Check each phase loads and runs (`godot-debug`; `godot-drive` for
behaviour a test cannot see).

## 5. Green and wrap up

Rerun the new tests until they pass (`--repeat=10` for anything timing-dependent), then
`tools/run_tests.sh --changed --summary`, then the whole suite `tools/run_tests.sh --summary --jobs=auto`.
Touched a per-frame path? Run `tools/run_tests.sh --domain=perf` on a quiet machine. An older test that now
fails is a regression your change caused until shown otherwise.

Update every skill whose domain changed (and `architecture` for an interface) and the spec in `docs/` if the
behaviour has one.

## 6. Audit

The last gate before the user sees the work: dispatch **one agent** to run the **`audit` skill** over the branch.
It reads the branch's whole change (commits since `main` plus anything staged), so what phases 3 to 5 produced is
in scope; commit or stage the work first if the user has asked you to commit, otherwise tell the agent which
files are only in the working tree (the audit's load check and tests see them, its diff does not). Start it with
`orca orchestration worker-start --task-title "audit" --spec "<spec>" --worktree current --agent claude`, a
self-contained spec in the five parts `orchestration` asks for:

- **Target:** the worktree and branch, the ticket number, and the base ref (default `origin/main`).
- **Change:** invoke the `audit` skill and run it to its checklist. The agent does every step of the audit itself
  and starts no workers.
- **Constraints:** report only. It does not fix, edit, stage, commit, push or comment on the ticket, and it
  starts the worktree editor only when its checks are green.
- **Ownership:** it owns the audit's scratch directory and one report file, and no file in the tree.
- **Observable acceptance:** its `worker_done` gives the issue count and the report path, and the report is the
  audit's checklist with a verdict line.

Read the report yourself; a failed or missing report is a finding, not a pass. Take each item to the right
place: a real defect in what was built goes back to phase 4 (and its test to phase 3 first when no test would
have caught it), a stale skill or comment is fixed with the phase 5 wrap-up, a finding you disagree with goes to
the user with your reasoning. Then rerun the checks, and rerun the audit once more if code changed beyond the
audit's own list. Go on when it comes back clean or the user has accepted what is left.

## 7. Ask for feedback

Report on the ticket and to the user: what was built against the plan, the tests (red → green), the audit's
verdict and what was done about each finding, the files changed, anything left uncovered or deviating from the
plan and why. Then **ask for their feedback** and wait.
Feedback is a new round: change the plan section on the ticket if the scope moved, add or adjust a test first,
then change the code, and audit again (phase 6) before reporting back. Don't commit or close the ticket unless asked.
