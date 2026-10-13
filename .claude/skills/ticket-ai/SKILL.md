---
name: ticket-ai
description: How to field a ticket labelled `ai`. It follows the `ticket-story` rules, with two additions - search online for real tactics and strategy while grilling the user about the behaviour, and leave the rest of the AI on in the tests so conflicts show up. Invoked from the `ticket` skill when a ticket carries the `ai` label.
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

## Testing: don't disable systems

In the tests phase, **leave the rest of the AI on**, so a conflict with the new behaviour shows up as a failing
test instead of being hidden. Build the world the way a match does and keep the defaults: don't switch off
`ai.*` behaviours, hold the NPC still, shorten its timers or remove anything that would be in the way in the real
situation. A switch is allowed only when it is the scenario's *premise* (e.g. an invader that has not spotted
anyone yet); comment why on each one and list them in the report.

A new test that fails because another AI system gets in the way is a finding: fix the conflict at its cause, not
by disabling that system in the test. Where Von has to choose the new behaviour, the test needs the real Von
(`"requires_von": true`, run with `--include-von --require-von`); a scripted Von only proves the NPC carries out
a pick it was told to make.
