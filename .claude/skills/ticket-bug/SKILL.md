---
name: ticket-bug
description: Work a ticket labelled `bug` in phases - grill the user to an agreed expected-vs-actual, then reproduce, fix and green it with the `fix` skill, then feedback and report. Invoked from `ticket`.
---

# Ticket: bug

Four phases through `orchestration` (`ticket`, "Work in phases"). You run phase 1 and the user questions; phases 2–4
are `fix`'s steps and may go to workers.

## 1. Grill

Load `architecture` and the `domain-<name>` skill where the bug seems to live; read what the ticket points at. Answer
from the code what it can answer. Grill the user (`AskUserQuestion`) until the bug is *expected vs. actual* with nothing
guessed:

- what should happen and what happens instead (exact symptom, any error text);
- the trigger: map, seed, who is in it, what they carry, the moment;
- how often (always, sometimes, one layout), since when or after which change;
- what they tried or ruled out, anything related;
- what "fixed" looks like to them.

Restate it in one or two lines and get agreement. Then `ticket` → "Rebase after acceptance" (a change in the bug's area,
already fixed or moved, reopens the questions) and "Show the user".

## 2–4. Reproduce, fix, green

Invoke `fix` with the agreed expected-vs-actual (plus the ticket title and useful comments) and follow it: red for the
bug's reason (tell the user the red result; passes at once or not visible headless: agree the next step with the user,
don't fix blind), root-cause fix, green, skills updated.

Then:

- **Feedback:** you point the user at the `show-me` editor (Play restarted) and ask (`AskUserQuestion`) whether the bug
  is gone. Anything still seen is a new round: failing test, fix, green, ask again.
- **Report** on the ticket: the root cause, the covering test, the red → green lines. Then ask feedback or finish as in
  `ticket` → "Report, then feedback or finish"; a bug has no audit, so a feedback round is the one above (failing test,
  fix, green).
