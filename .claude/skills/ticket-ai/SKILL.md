---
name: ticket-ai
description: How to field a ticket labelled `ai`. When the ticket adds AI functionality (a new action, tactic or reaction), first write tests of real-world situations where the AI should perform it, with the rest of the AI left on, and watch them fail before programming the behaviour. Invoked from the `ticket` skill when a ticket carries the `ai` label.
---

# Ticket: ai

An `ai` ticket changes how NPCs behave. This skill covers the case that most needs discipline: the
ticket **adds AI functionality**, meaning a new action, tactic, reaction or decision the NPCs do not
show today. Write the tests first, from the real world rather than from the code, and see them fail
before you program anything.

If the ticket only fixes or retunes behaviour that already exists (a wrong pick, a stuck NPC, a
threshold), it is not adding functionality: for a bug use `ticket-bug` / `fix`, otherwise field it as
ordinary work (`architecture` + `domain-ai`). If you cannot tell which it is, say so rather than guess.

## 1. Orient

Load `architecture`, `domain-ai` and the `domain-ai-<name>` sub-skills the work will touch, `domain-testing`
(how a test is written) and `test-debug` (failure bundle, `--repeat`, `--seed`, `trace()`). The behaviour specs in
`docs/` (`flanking-behavior.md`, `tactical-entry.md`, `gaze-and-fire.md`, `cover-and-stance.md`) show what a
spec and its tests look like here. Orient only: do **not** go reading how the AI would do the new thing yet.

## 2. Write the scenarios down first, from the real world

State the new behaviour in one line (*when X, the NPC does Y*), then write the situations before any test code.
Base them on how the thing is done in reality: published tactics and doctrine, training material, how people
actually move, shoot, communicate and react in that setting. Search the web when your own knowledge is thin.
Do **not** shape them around what the AI, the snapshot, the decision tree or the navmesh can do today.

- **Real geometry and real people.** Use a realistic layout (`Maps.house`, `Maps.spine`, `Maps.warehouse` in
  `tests/_ai/flank_maps.gd`, or a generated `house(seed)`), real doorways and furniture, and the numbers a
  person would face (distances, how many hostiles, who sees whom, what each carries). Add the other people the
  situation really has: allies, a second hostile, a defender nobody has spotted.
- **Cover three kinds of case:**
  - **should act**: the situations where the real-world answer is to do this, in more than one room shape
    and team size, including a messy one;
  - **should not act**: situations that look similar but where the real-world answer is something else
    (the wrong moment, no threat, an ally already doing it, no safe way to);
  - **under pressure**: the same situation with another need pulling the other way (taking fire, a dry gun,
    a wounded NPC, an ally's call), where the realistic result is a trade-off.
- **Assert what a person watching would see**: where the NPC goes, where it looks, whether and when it fires,
  what it says on the radio, what it leaves alone. Prefer these outcomes to internal ids (a decision-tree
  node, an option name), which do not exist yet and are not the point.
- Record the real-world basis of each scenario in the test's header comment (one or two lines), and name the
  behaviour so a spec in `docs/` can cite it.

If a scenario cannot be built with the current test harness (no actor kind, no way to read the outcome), say
what is missing; fix the harness as its own step, never bend the scenario to fit.

## 3. Write the tests

Tests go in `tests/ai/<name>_test.gd` (tag `ai`, plus the behaviour's own tag), shared setup in
`tests/_ai/<name>_probe.gd`. Run `tools/run_tests.sh --list <words>` first and extend a test rather than adding a
near-duplicate.

**Leave the rest of the AI on.** The point of these tests is to find the systems that fight the new behaviour:
the entry guard, territory, pursuit, posture, hostility rules, the radio, auto-reload, commitment timers, the
decision budget. So:

- Build the world the way a match does and keep the defaults. Do not switch off `ai.*` behaviours, hold the NPC
  still (`speed` 0) or shorten its commit and decide timers to make the new behaviour easier to see.
- A switch or `set_static` is allowed only when it is the scenario's *premise* (e.g. an invader that has not
  spotted anyone yet), never to silence a competitor. Put a comment on each one saying why, and list them in the
  report.
- Never remove an NPC or object that would be in the way in the real situation.

**Who decides.** Von picks the option at each level of the decision tree; a scripted Von (`von_script`) picks
for it, and with no rule matching it takes the *first* offered option. So:

- A test that the AI *chooses* the new thing in a situation needs the real Von: `"requires_von": true`, tag `von`,
  run with `--include-von --require-von`. If no Von server can be started here, say so plainly: those tests are
  written but not run, and nothing about that choice is verified.
- Scripted-Von tests prove the rest: that the NPC *carries out* the pick (movement, gaze, shots, radio), and
  that the situation *offers* the option and the contrasting situation does not (`debug_state()["decision"]["levels"]`).
  Do not script the new pick into a test whose point is that the AI would choose it.

Make a test deterministic where its assertion depends on it (`t.until` rather than fixed sleeps, a pinned
`--seed` for a layout) without taking away what the AI does.

## 4. See them fail (red), before any production code

Run each new test on its own, with the Bash sandbox disabled: `tools/run_tests.sh --id=ai/<name>` (add
`--include-von --require-von` for the Von ones), reading the `✗` lines and the `bundle:` JSON.

- **Every new test must FAIL, and for the right reason**: the NPC does not do the thing (or does it where
  it should not). A parse error, a timeout caused by a setup mistake, an NPC that could never see its target or
  find a path, a fixed-sleep race: none of that is red, it is a broken test. Fix the test and rerun.
- Prove the scenario itself is sound with a precondition (`t.require`) that holds today: the NPC sees the
  hostile, the doorway is reachable, the gun is loaded. A test that fails only because its premise never came
  true will go green for the wrong reason or never.
- **If a test passes straight away**, the behaviour already exists or the assertion is too loose. Tighten it
  (does it fail if the NPC stands still?) or, if the behaviour is truly there, say so and drop that scenario.
  Never let a test that was not red count as proof.
- Check `git status` shows only test files (and their `.uid`) before you go on. Show the red results to the user
  if the scenarios were not agreed earlier: they are the spec you are about to build to.

## 5. Build the behaviour

Make the change in the right sub-domain (`domain-ai-perception`, `-snapshot`, `-decision`, `-behavior`, …),
through the published interfaces only, as data and generic conditions: nothing per weapon, per NPC type or per
scenario. When Von must be told something new, follow the snapshot's wording rules (`domain-ai-snapshot`) and
check the wording against the real Von with `tools/von_probe.py` (add a scenario under `tools/von_scenarios/`).

Never loosen, skip or special-case a test to get it green, and never switch off another behaviour in the test to
make it pass.

## 6. Green, and hunt the conflicts

1. Rerun the new tests until they pass (`--repeat=10` for the scripted ones, and for the Von ones enough runs to
   see they are stable).
2. **A new test that fails because another AI system gets in the way is a finding, not a nuisance.** Find which
   one (`trace()`, the failure bundle, `debug_state()`, the overlays via `--play`) and fix the conflict at its
   cause, in the behaviour that is wrong for the real situation. Do not paper over it by disabling the other
   system in the test.
3. `tools/run_tests.sh --changed --summary`, then the whole suite `tools/run_tests.sh --summary --jobs=auto`.
   An older test that now fails is a regression your change caused until shown otherwise; fix the code, and
   change that test only if it asserted something the real world says is wrong, and say so.
4. Touched a per-frame path (perception, snapshot, a per-tick behaviour)? Run `tools/run_tests.sh --domain=perf`
   on a quiet machine (check `uptime` around it; discard a loaded run).

## 7. Wrap up

Update every skill whose domain's behaviour changed (`domain-ai*`, `architecture` for an interface), and the
spec in `docs/` for a behaviour that has one, or add one when the new behaviour has rules of its own; state what
the code does now. Don't commit or close the ticket unless asked.

Report on the ticket: the behaviour added; the scenarios and their real-world basis; the red results (one line
per test, with why it failed) and the green ones; the conflicts found and how each was fixed; any switch a test
turns off and why; whether the Von tests ran against a real server; anything left uncovered.
