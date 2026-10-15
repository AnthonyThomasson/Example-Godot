---
name: ticket-ai
description: Extra rules for a ticket labelled `ai` (with `ticket-story`) - research real tactics online while grilling, scenario tests on the whole AI pipeline with the real Von server, rest of the AI left on. Invoked from `ticket`.
---

# Ticket: ai

Follow `ticket-story`; load `domain-ai` and the `domain-ai-<name>` skills the work touches. Fixing behaviour that
already exists is a bug: `ticket-bug`.

## Grilling: real tactics

Search the web for how it is done for real: published tactics and doctrine, training material, how people move,
shoot, communicate and react in that setting. Put what you find (and where reality differs) into the questions, the
plan and the test scenarios. Don't shape the behaviour around what the AI, snapshot or navmesh can do today.

## Tests: the whole pipeline

- Location: `tests/ai/<topic>/<name>_test.gd` (topics: `entry`, `flank`, `gaze`, `posture`, `investigate`, `combat`, `grenade`,
  `movement`, `decision`, `perception`, `stack`); shared setup in `tests/_ai/<name>_probe.gd`.
- **Scenario tests script nothing:** perception, snapshot, the real Von server at every tree level, behaviour, radio
  and guard all run. `"requires_von": true`, tag `von`, run with `--include-von --require-von`.
- Build the world so the decision under test is the natural one (nearest doorway, the one unsearched room, the hostile
  in view), and `require` the AI took that path before asserting what it did there, so a surprising Von pick reads as
  a set-up finding in the bundle.
- `von_script` (scripted Von) is for one mechanism at a time (the NPC carries out a given pick; a situation offers an
  option the contrasting one doesn't). It never replaces scenario tests.
- **Leave the rest of the AI on:** build the world as a match does, keep defaults. Don't switch off `ai.*` behaviours,
  hold the NPC still, change its timers or remove what would be in the way. A switch or prop only when it is the
  scenario's premise (a part-spent magazine, an unkillable defender); comment why on each and list them in the report.
- A failure caused by another AI system is a finding: fix the conflict at its cause, never by disabling that system.
- A red scenario test is tagged `gap` and its behaviour written into the `docs/` spec (as `docs/tactical-entry.md`
  E10–E15 were; `domain-testing`, "Running tests"): reported as GAP, not a run failure, and a FAIL the day it passes
  until the tag is dropped.
