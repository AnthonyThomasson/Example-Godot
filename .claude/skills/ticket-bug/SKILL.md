---
name: ticket-bug
description: How to field a ticket labelled `bug`. Grill the user about the issue, reproduce it as a failing game test with the `fix` skill, then implement the fix. Runs in phases through `orchestration`. Invoked from the `ticket` skill when a ticket carries the `bug` label.
---

# Ticket: bug

A bug runs in four phases, in order, through `orchestration` (see the `ticket` skill, "Work in phases"). Phase 1
talks to the user, so you (the coordinator) run it yourself; phases 2 to 4 are the `fix` skill's steps, which you
may dispatch to workers.

## 1. Grill the user about the issue

Before any test or code, load `architecture` and the `domain-<name>` skill for the domain the bug seems to live
in, and read what the ticket points at. Then **grill the user** (`AskUserQuestion`, a few specific questions at a
time) until you can state the bug as *expected vs. actual* with nothing guessed:

- what should happen, and what happens instead (exact symptom, any error text);
- the steps or situation that trigger it: map, seed, who is in it, what they carry, the moment it happens;
- how often (always, only sometimes, only one layout), and since when or after which change, if known;
- what they have already tried or ruled out, and anything that looks related;
- what "fixed" looks like to them.

Answer from the code what the code can answer instead of asking. Restate the bug back in one or two lines and
get the user's agreement before going on. Once they agree, rebase onto `main` and check what came in (the `ticket`
skill, "Work in phases"): a change in the area of the bug (it may already be fixed, or moved) reopens the
questions. Then invoke the `show-me` skill so the user has an editor on the worktree to watch the reproduction and
the fix on.

## 2. Reproduce (red)

Invoke the **`fix` skill** through the `Skill` tool, passing the agreed expected-vs-actual (and the ticket's
title and any useful comments) as the description, and follow its steps 1–3: write the smallest game test that
triggers the symptom, run it, and require it to **fail for the bug's reason** (not a parse error, race or
harness mistake). Tell the user the red result. If it passes straight away, or the bug cannot be seen headless,
say so and agree the next step with the user rather than fixing anything blind.

## 3. Implement the fix

Fix the root cause with the smallest change that addresses it, through the published interfaces only (`fix`
step 4). Never loosen, skip or special-case the test to get green.

## 4. Green and wrap up

`fix` steps 5–6: the repro test passes (`--repeat=10` if it was intermittent), then the changed and full suites;
update the skills whose domain or interface changed.

Once every run is green, ask the user for feedback before reporting (you, not a worker): point them at the editor
`show-me` opened (Play restarted for the latest code), ask with `AskUserQuestion` whether the bug is gone for
them, and wait. Anything they still see is a new round: a failing test for it first, then the fix, then green, and
ask again.

When done, report on the ticket what the root cause was and which test covers it, with the red → green lines.
Then ask the user with `AskUserQuestion` whether they want to give more feedback or finish the ticket. Feedback is
another round as above; on "finish", release every settled worker and invoke the `finish` skill yourself (that answer
is the go-ahead). Without it, never commit or close the ticket.
