---
name: m-show-me
description: Open the Godot editor on this worktree with autorun, named after the worktree, so the user can see the finished change running. Manual only — invoked as `/m-show-me`.
disable-model-invocation: true
model: haiku
---

# Show me

Leave a live copy of the change running for the user.

1. The editor is named after the worktree's directory (for example
   `fix-the-flickering-that-happens-when-a-ragdolls`); the script derives it, so pass no name.
2. Run from the worktree root. The Bash sandbox must be disabled for `tools/editor.sh`
   (`dangerouslyDisableSandbox: true`):

   ```bash
   tools/editor.sh --autorun
   ```

3. If an editor is already open on this worktree the script starts nothing and prints `editor
   already running` with its pid, port and log. Report that and skip to step 5 (Play is not
   pressed again). Otherwise it prints the editor pid, the command-server port and a log path;
   after about 10 s check the log (`$TMPDIR/editor_<name>.log`) for
   `[cmd] listening on 127.0.0.1:<port>` and for any `SCRIPT ERROR`. Do not run tests or edit files.
4. Report the name, port and pid in a line or two, and say whether it was already running or the
   log showed errors. Leave the editor open. The game's setup window shows the worktree name at the top.
5. Also list the tests created or changed to verify this change, so the user knows what covers
   it. Find the new or modified `tests/**/*_test.gd` files (`git status --short tests/` or the
   session), then give each test's `"name"` from its `describe()` (for example
   `Falling body keeps its draw order`), one per line — not the file name. If none were added,
   say so. Only name them; do not run them.
