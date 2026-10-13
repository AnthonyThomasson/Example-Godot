---
name: ticket-spike
description: Work a ticket labelled `spike` - investigate in the workspace without changing the game, then plan the work as new, well-scoped GitHub tickets created with `gh`. Invoked from `ticket`.
---

# Ticket: spike

A spike plans work for future tickets. It changes nothing in the game: no feature code, refactors, test changes or
implementation commits. Reading code and running the game or tests to learn is fine.

## Steps

1. Read the ticket (`ticket`) and state the question the spike answers.
2. **Investigate.** Load `architecture`, then the domain skills involved. Read code; run `tools/run_tests.sh` or drive
   the game (`godot-run`) where that answers a question. Note the files, domains and interfaces the work would touch,
   the risks and unknowns, and the order the pieces must come in.
3. **Break it into tickets**, each:
   - small and independent enough to finish in one go, split along domain boundaries where possible;
   - self-contained: problem, intended outcome, relevant files / interfaces / skills, acceptance criteria (tests or
     behaviour that prove it done), and any ticket it depends on;
   - labelled by kind (`spike` for a further unknown, else what the repo's labels call for).
4. **Create them with `gh issue create`** on the spike's repo (`--repo`, `--label` per label), in dependency order so
   later ones link earlier ones by number, each linked back to the spike (`gh issue comment <n>`).
5. **Report** on the spike ticket: findings, the created tickets (number, title, one line each), and what stays unknown.

## Rules

- Search open issues for duplicates first.
- Only tickets backed by the investigation; a short accurate list beats a long speculative one.
- Creating tickets publishes them: unless the user said to proceed without checking, show the planned list and get a
  go-ahead first.
