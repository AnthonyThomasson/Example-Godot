---
name: ticket-harness
description: Extra rules for a ticket labelled `harness` (skills, AGENTS.md, hooks, tools/, command server, test runner), with `ticket-story` - instruction changes get no tests, agent-facing tools do. Invoked from `ticket`.
---

# Ticket: harness

Covers `.claude/skills/`, `AGENTS.md`, hooks, `tools/` scripts (`gcmd.py`, `run_tests.sh`, `editor.sh`, `von_probe.py`,
`match.py` …), the dev command server (`scenes/general/command_server.gd`) and the test runner (`scenes/testing/`).
Follow every `ticket-story` phase; only what gets tested differs.

## What is tested

- **Skills and instructions: no tests.** A skill, `AGENTS.md`, a doc, a hook's wording, a checklist, or a tool change
  that only rewords help text or a log line: skip `ticket-story` phase 3. Check instead, in phase 5 and the audit:
  every skill, file, command, flag and name mentioned exists as spelled now; frontmatter valid (`name` = folder,
  `description` says when to use it); no reference left to a renamed or removed skill (`grep -rn` the old name); the
  routing skills (`ticket`, `architecture`, `AGENTS.md`) list it.
- **Tools an agent uses on the app: tests first** (red, per `ticket-story` phase 3): a command-server verb, a `tools/`
  script that drives, queries or inspects the game, a runner flag or report field, a probe or overlay an agent reads.
  Test it the way an agent uses it: a game test for an in-game surface (`domain-testing`; harness ones in
  `tests/_harness/`), or for a script a run against the headless game or a fixture, checking output and exit code.
- Both in one ticket: test only the tool part. Game code added so a tool can read it is a tool change: test it and
  keep `architecture` true.

## Wrap-up for skill-only work

Phase 5 is: lint and load check if any `.gd` changed (`godot-run`), a read-through of each changed skill against the
code, and a check that no other skill or doc now disagrees. The audit still runs; its skills step is the main check.
