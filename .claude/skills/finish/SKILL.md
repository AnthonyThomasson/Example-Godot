---
name: finish
description: Commit this worktree's work, merge it into main, push main, then close its ticket and remove the Orca workspace. Use it at the end of a ticket once the user has answered "finish" to the ticket workflow's feedback-or-finish question (`ticket-story` phase 7, `ticket-bug` phase 4), or when the user asks to finish (`/finish`). Never run it without that answer.
model: haiku
---

# Finish

Commit the work in this worktree, land it on `main`, push `main`, close the ticket and remove the
Orca workspace. Run from the worktree root. Push `main` only: do not push the branch.

It pushes `main` and deletes the workspace, so it runs only on the user's say-so: their "finish" answer at the end of
a ticket workflow, or `/finish`. Release every settled orchestration worker before step 1.

1. **Preconditions.** Get the branch (`git branch --show-current`) and the directory where `main`
   is checked out (the `worktree` entry with `branch refs/heads/main` in
   `git worktree list --porcelain`). Stop and tell the user if the branch is `main`, if there is
   nothing to commit and nothing ahead of `main`, or if `main`'s directory is not clean
   (`git -C <main dir> status --short`).
2. **Commit.** No analysis or tests: just land the work. Review `git status --short`. Stage the
   files that belong to this work by name, including the `.uid` beside every new or moved `.gd`
   (this project tracks them). Commit with a message that says what changed and why, ending with
   the attribution line the session's attribution guidance gives for commits. Anything you leave
   out is dealt with in step 6: the worktree has to end up with a clean `git status`.
3. **Bring in main.** `git merge main`. If it conflicts, resolve only trivial conflicts; otherwise
   stop and show the user the conflicting files.
4. **Land it.** `git -C <main dir> merge --ff-only <branch>`. If it refuses because `main` moved,
   go back to step 3. Never force, and never use `--no-verify`.
5. **Push.** `git -C <main dir> push origin main`. If the push is rejected because `origin/main`
   moved, run `git -C <main dir> pull --ff-only origin main`; if that brings in changes, go back to
   step 3 so they are merged into the branch, then land and push again. Never force-push.
6. **Make the worktree removable.** `git worktree remove` (which `orca worktree rm` runs) refuses
   a worktree with any untracked file that is not gitignored, and a running Godot editor keeps
   writing new ones (`.uid` files) into it. Do this before closing anything, so a failure leaves
   the ticket open.
   - Stop any editor or game opened on this worktree (`show-me` leaves one running):
     `pgrep -f -- "--path $PWD( |\$)"`, then plain `kill <pid>` on each, and wait for them to exit.
   - `git status --short`. Anything left is untracked or modified and must go:
     a `.uid` with no `.gd` beside it, an `.import`, or other generated cruft: delete it.
     Anything that looks like real work was missed in step 2: commit it (back to step 2).
     Scratch files you cannot account for: stop and ask the user; do not delete them silently.
   - Repeat `git status --short` until it prints nothing (ignored files such as `.godot/` are
     fine). If it will not go clean, stop and say why: do not continue to step 7.
7. **Close the ticket.** Read the workspace's links with `orca worktree current --json` (resolve
   the Orca CLI as the `orca-cli` skill says; on macOS it is `orca`): `result.worktree.id`,
   `linkedIssue` (GitHub), `linkedLinearIssue` and `linkedGitLabIssue`. Note the worktree `id` now;
   step 9 needs it.
   - GitHub issue: `gh issue close <number> --comment "Fixed in <short hash>, merged to main."`
   - Linear issue: load the `orca-linear` skill and finish the ticket as it describes.
   - GitLab issue, or no link: skip it and say so. Never guess a ticket.
   If closing fails, report the error and skip step 9 so the workspace stays.
8. **Report.** Say which commits landed on `main` (hashes and subjects), that `origin/main` now
   matches, which ticket was closed, and anything you deleted in step 6. Write this before step 9.
9. **Remove the workspace, last.** `orca worktree rm --worktree id:<worktree id> --json`, using the
   id from step 7 (not `current`: this directory is about to be deleted). No `--force` and no
   `--run-hooks`: step 6 is what makes this succeed, and `--force` would hide a real problem. Orca
   removes the git worktree and its merged local branch. If it refuses, report the error and stop;
   do not retry with `--force`. Nothing runs after this command.
