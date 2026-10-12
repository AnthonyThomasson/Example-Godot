---
name: ticket-bug
description: How to field a ticket labelled `bug`. Fix it with the `fix` skill — reproduce it as a failing game test, then fix the code. Invoked from the `ticket` skill when a ticket carries the `bug` label.
---

# Ticket: bug

A bug ticket is fixed with the **`fix` skill**: invoke it through the `Skill` tool, passing the ticket's title and
body (and any useful comments) as the description of what is going wrong, then follow it — reproduce the bug as a
failing game test, fix the root cause, get the test and the suite green.

If the ticket is too vague to tell expected from actual behaviour, say what is missing (a comment on the ticket via
`gh issue comment`, or ask) rather than guessing.

When done, report on the ticket what the root cause was and which test covers it. Don't commit or close the ticket
unless asked.
