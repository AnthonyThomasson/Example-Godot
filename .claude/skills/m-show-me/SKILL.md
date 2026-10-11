---
name: m-show-me
description: Open the Godot editor on this worktree with autorun, named after the worktree, so the user can see the finished change running. Manual only — invoked as `/m-show-me`.
disable-model-invocation: true
model: haiku
---

# Show me

Leave a live copy of the change running for the user.

1. The name is the worktree's directory name: `basename "$PWD"` from the worktree root (for
   example `fix-the-flickering-that-happens-when-a-ragdolls`).
2. Run from the worktree root. The Bash sandbox must be disabled for `tools/editor.sh`
   (`dangerouslyDisableSandbox: true`):

   ```bash
   tools/editor.sh "$(basename "$PWD")" --autorun
   ```

3. The script prints the editor pid, the command-server port and a log path. After about 10 s,
   check the log (`$TMPDIR/editor_<name>.log`) for `[cmd] listening on 127.0.0.1:<port>` and
   for any `SCRIPT ERROR`. Do not run tests or edit files.
4. Report the name, port and pid in a line or two, and say whether the log showed errors. Leave
   the editor open.
5. Also list the tests created or changed to verify this change, so the user knows what covers
   it. Find the new or modified `tests/**/*_test.gd` files (`git status --short tests/` or the
   session), then give each test's `"name"` from its `describe()` (for example
   `Falling body keeps its draw order`), one per line — not the file name. If none were added,
   say so. Only name them; do not run them.
