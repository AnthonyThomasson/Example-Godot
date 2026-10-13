---
name: show-me
description: Open the Godot editor on this worktree with autorun, named after the worktree, so the user has a live copy of the game to verify the change on. Use it once a ticket's plan is accepted (or a bug's grilling is agreed) in the ticket workflows, again when the user should see finished work running, and whenever asked to "show me" the change.
model: haiku
---

# Show me

Leave a live copy of the change running for the user. In the ticket workflows this runs right after planning (the
`ticket` skill, "Work in phases"), so the user has an editor on the worktree to verify each phase on as it lands;
running it again later is safe, since it reuses an editor already open there.

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
   The editor picks up later file changes when it is focused; a running game needs its Play restarted to see them.
5. Also list the tests created or changed to verify this change, so the user knows what covers
   it. Find the new or modified `tests/**/*_test.gd` files (`git status --short tests/` or the
   session), then give each test's `"name"` from its `describe()` (for example
   `Falling body keeps its draw order`), one per line — not the file name. If none were added yet
   (right after planning), say so. Only name them; do not run them.
