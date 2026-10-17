---
name: ticket-spike
description: Work a ticket labelled `spike` - investigate in the workspace without changing the game, then plan the work as new, well-scoped GitHub tickets created with `gh`. Invoked from `ticket`.
---

# Ticket: spike

A spike plans work for future tickets. It changes nothing in the game: no feature code, refactors, test changes or
implementation commits. Reading code and running the game or tests to learn is fine.

## Steps

1. Read the ticket (`ticket`), run `ticket` → "Triage checks" (already answered? asked before?) and state the question
   the spike answers.
2. **Investigate.** Load `architecture`, then the domain skills involved. Read code; run `tools/run_tests.sh` or drive
   the game (`godot-run`) where that answers a question. A question only outside sources answer (published tactics, an
   engine or API fact): `mattpocock-skills:research` in the background, its cited notes in `docs/research/<slug>.md`.
   Note the files, domains and interfaces the work would touch, the risks and unknowns, and the order the pieces must
   come in. Still too foggy for one round of tickets (each answer opens new questions, more than a session's worth):
   say so and suggest the user charts it with `/wayfinder` instead.
3. **Break it into tickets** (`to-tickets`' rules), each:
   - a tracer bullet: one narrow behaviour working end to end through every domain it needs, demoable or testable on
     its own; never one domain's layer of a behaviour that only works once a sibling lands. A refactor that makes the
     rest easy comes first, as its own ticket;
   - small enough for one session;
   - its body an `## Agent Brief` (`ticket` → "Brief and plan on the ticket": current and desired behaviour, key
     interfaces and the skills to load, acceptance criteria, out of scope; no file paths, they go stale);
   - labelled by kind (`spike` for a further unknown, else what the repo's labels call for) plus `ready-for-agent`.
4. **Create them with `gh issue create --parent <spike>`** on the spike's repo (`--repo`, `--label` per label),
   blockers first, then wire each blocker as a native GitHub dependency (`docs/agents/issue-tracker.md`, "Blocking").
   Only where that fails, a `Blocked by: #<n>` line at the top of the body.
5. **Report** on the spike ticket: findings, the created tickets (number, title, one line each), and what stays unknown.

## Rules

- Search open issues for duplicates first.
- Only tickets backed by the investigation; a short accurate list beats a long speculative one.
- Creating tickets publishes them: unless the user said to proceed without checking, show the planned list and get a
  go-ahead first.
