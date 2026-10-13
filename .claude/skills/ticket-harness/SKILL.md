---
name: ticket-harness
description: How to field a ticket labelled `harness` — work on the agent harness itself (skills, AGENTS.md, hooks, the tools under tools/, the dev command server, the test runner). It follows the `ticket-story` rules with one difference - a change to skills or other agent instructions gets no tests; only a new or changed tool that lets an agent interact with the application (a command-server verb, a tools/ script, a runner flag) is tested. Invoked from the `ticket` skill when a ticket carries the `harness` label.
---

# Ticket: harness

A `harness` ticket changes how agents work on this project rather than the game: the skills under
`.claude/skills/`, `AGENTS.md`, the hooks, the scripts in `tools/` (`gcmd.py`, `run_tests.sh`, `editor.sh`,
`von_probe.py`, `match.py` …), the dev command server (`scenes/general/command_server.gd`) and the test runner
(`scenes/testing/`). It follows the **`ticket-story` rules** in full (grill, plan on the ticket, rebase, `show-me`,
build, green, the feedback gate, audit, report, feedback or finish), with one difference: **what gets tested**.

## What is tested

- **Skill and instruction changes get no tests.** A new or edited skill, `AGENTS.md`, a doc, a hook's wording or a
  checklist is not a test subject: skip `ticket-story` phase 3 for it. It is checked instead by reading it against
  the code and the other skills (phase 5 and the audit): every skill, file, command, flag and name it mentions
  exists and is spelled as it is now, the frontmatter is valid (`name` matches the folder, a `description` that says
  when to use it), a renamed or removed skill has no reference left (`grep -rn` the old name), and the skills that
  route to it (`ticket`, `architecture`, `AGENTS.md`) list it.
- **A tool that lets an agent interact with the application is tested.** A new or changed command-server verb, a
  `tools/` script that drives, queries or inspects the game, a test-runner flag or report field, a probe or overlay
  an agent reads: write its tests first and see them red, as `ticket-story` phase 3 says. Test it through the way an
  agent uses it: a game test for an in-game surface (`domain-testing`; harness-level ones live in `tests/_harness/`),
  and for a script, a run of the script against the headless game or a fixture that checks its output and its exit
  code. A tool change that only rewords help text or a log line is an instruction change, not a tool change.

A ticket that does both tests only the tool part. A harness ticket that changes game code (a new hook into a
domain so a tool can read it) is a tool change: test it, and keep the domain's interfaces in `architecture` true.

## Wrap-up for skill-only work

With nothing to test, phase 5 is: lint and the load check if any `.gd` changed, a read-through of every changed
skill against the code, and a check that no other skill or doc now says something different. The audit still
runs (its Brief B, skills true, is the main check here).
