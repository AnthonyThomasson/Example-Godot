---
name: ticket-spike
description: How to field a ticket labelled `spike`. A spike produces no code — its job is to investigate in the workspace and plan out work for future tickets, which you create with the GitHub CLI (`gh`). Invoked from the `ticket` skill when a ticket carries the `spike` label.
---

# Ticket: spike

A spike's job is to **plan out work for future tickets**. You investigate the question in your workspace,
then turn what you learned into new, well-scoped tickets that can each be picked up later.

A spike does **not** change the game: no feature code, no refactors, no test changes, no commit of
implementation work. Reading code and running the game or tests to learn things is fine.

## Steps

1. **Read the ticket** (via the `ticket` skill) and state the question the spike must answer.
2. **Investigate in the workspace.** Load the `architecture` skill, then the `domain-<name>` skills for the domains
   involved. Read the code, run `tools/run_tests.sh` or drive the game (`godot-drive`) where that answers a
   question. Note which files, domains and cross-domain interfaces the work would touch, what is risky or
   unknown, and what order the pieces must come in.
3. **Break the work into tickets.** Each future ticket should be:
   - **Small and independent enough** to finish in one go; split along domain boundaries where you can.
   - **Self-contained:** the problem, the intended outcome, the relevant files / interfaces / skills found in
     step 2, acceptance criteria (the tests or behaviour that prove it done), and any ticket it depends on.
   - **Labelled by kind** (e.g. `spike` for a further unknown, otherwise whatever the repo's labels call for).
4. **Create the tickets with the GitHub CLI** (`gh issue create`), not the web UI. Use `--repo` for the repo the spike came
   from, and `--label` for each label. Create them in dependency order so later tickets can link to earlier ones by
   number. Link each back to the spike ticket (`gh issue view <n>` / `gh issue comment <n>`).
5. **Report back** on the spike ticket: a summary of the findings and the list of tickets you created
   (number, title, one line each). Say plainly what stays unknown.

## Rules

- **Create tickets on the repo the spike came from**, unless told otherwise.
- **Check for duplicates** before creating a ticket (search existing open issues).
- **Don't create tickets for work that isn't backed by your investigation.** A short, accurate list beats a long
  speculative one.
- Creating tickets publishes them to an external service; if the user hasn't asked you to proceed without
  checking, show the planned list and get a go-ahead first.
