---
name: show-me
description: Open a Godot editor on this worktree with autorun, named after it, so the user can verify the change live. Use once a ticket's plan is accepted (or a bug agreed), when the user should see finished work, and when asked to "show me".
model: haiku
---

# Show me

Safe to rerun: it reuses an editor already open on the worktree. Do not run tests or edit files.

1. From the worktree root, Bash sandbox disabled (`dangerouslyDisableSandbox: true`); the script names the editor after
   the worktree directory, so pass no name:

   ```bash
   tools/editor.sh --autorun
   ```

2. `editor already running` (with pid, port, log): report it and go to step 4; Play is not pressed again. Otherwise it
   prints the pid, command-server port and log path; after ~10 s check the log (`$TMPDIR/editor_<name>.log`) for
   `[cmd] listening on 127.0.0.1:<port>` and any `SCRIPT ERROR`.
3. Report the name, port and pid in a line or two, whether it was already running, and any log errors. Leave it open.
   The setup window shows the worktree name at the top. The editor picks up file changes when focused; a running game
   needs Play restarted.
4. List the tests created or changed for this change (`git status --short tests/`, or the session) by each one's
   `"name"` from `describe()` (e.g. `Falling body keeps its draw order`), one per line, not the file name. None yet
   (right after planning): say so. Don't run them.
