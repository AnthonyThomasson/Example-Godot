---
name: audit
description: Verify the staged change with the analysis-change-verification checklist. Manual only — invoked as `/audit`.
disable-model-invocation: true
model: claude-sonnet-5-5
---

# Audit

Run the `analysis-change-verification` skill over the staged change and report its checklist.

1. Load the `analysis-change-verification` skill and follow it from Step 0 through its output
   checklist.
2. If nothing is staged (`git diff --staged --stat` is empty), say so and stop. Do not stage files
   yourself.
3. Report the checklist and its one-line verdict. Do not commit, merge or push, and do not fix
   findings unless the user asks.
