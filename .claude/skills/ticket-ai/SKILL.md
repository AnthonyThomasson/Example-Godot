---
name: ticket-ai
description: How to field a ticket labelled `ai`. It follows the `ticket-story` rules, with three additions - search online for real tactics and strategy while grilling the user about the behaviour, write the scenario tests against the whole AI pipeline (the real Von server deciding, nothing scripted), and leave the rest of the AI on in the tests so conflicts show up. Invoked from the `ticket` skill when a ticket carries the `ai` label.
---

# Ticket: ai

An `ai` ticket changes how NPCs behave. It follows the **`ticket-story` rules** (grill, plan on the ticket, tests
first, build, feedback), and load `domain-ai` plus the `domain-ai-<name>` sub-skills the work touches. If the
ticket only fixes a behaviour that already exists, it is a bug: use `ticket-bug`.

## Grilling: search online for tactics and strategy

When grilling the user about the behaviour, **search the web** for how the thing is done in reality: published
tactics and doctrine, training material, how people actually move, shoot, communicate and react in that setting.
Bring what you find into the questions (what the real-world answer is, and the cases where it differs), and into
the plan and the test scenarios. Don't shape the behaviour around what the AI, the snapshot or the navmesh can
do today.

## Testing: the whole pipeline, nothing disabled

Tests go in `tests/ai/<topic>/<name>_test.gd` (the topic folders: `entry`, `flank`, `gaze`, `posture`, `investigate`,
`combat`, `movement`, `decision`, `perception`), shared setup in `tests/_ai/<name>_probe.gd`.

**Run the whole AI pipeline.** A scenario test is a question put to the shipped AI, end to end: perception sees the
world, the snapshot words it, the real Von server picks at every level of the decision tree, the behaviour carries the
pick out, the radio and the guard act on it. So a scenario test leaves every stage in place and scripts nothing:
`"requires_von": true`, tag `von`, run with `--include-von --require-von`. Build the world so the decision the scenario
is about is the natural one (the doorway is the nearest, the room is the one unsearched, the hostile is the one in
view) and `require` that the AI took that path before asserting on what it did there, so a surprising Von pick reads
in the bundle as a set-up finding and not as the behaviour's gap. A scripted Von (`von_script`) is for one mechanism
at a time (that the NPC carries out a given pick, or that a situation offers an option and the contrasting one does
not); it never stands in for the scenario tests.

**Leave the rest of the AI on**, so a conflict with the new behaviour shows up as a failing test instead of being
hidden. Build the world the way a match does and keep the defaults: don't switch off `ai.*` behaviours, hold the NPC
still, shorten or lengthen its timers or remove anything that would be in the way in the real situation. A switch or
a prop is allowed only when it is the scenario's *premise* (e.g. a part-spent magazine, a defender that cannot be
killed); comment why on each one and list them in the report.

A new test that fails because another AI system gets in the way is a finding: fix the conflict at its cause, not
by disabling that system in the test. A red scenario test is tagged `gap` and its behaviour written into the spec in
`docs/` (`docs/tactical-entry.md` E10 to E15 were written this way; `domain-testing`, "Running tests", covers the tag): the runner reports its failure as GAP, expected
and not a failure of the run, and fails it the day it passes until the tag is dropped.
