---
name: m-finish
description: Commit this worktree's work, merge it into main, push main, then close its ticket and remove the Orca workspace. Manual only — invoked as `/m-finish`.
disable-model-invocation: true
model: haiku
---

# Finish

Commit the work in this worktree, land it on `main`, push `main`, close the ticket and remove the
Orca workspace. Run from the worktree root. Push `main` only: do not push the branch.

1. **Preconditions.** Get the branch (`git branch --show-current`) and the directory where `main`
   is checked out (the `worktree` entry with `branch refs/heads/main` in
   `git worktree list --porcelain`). Stop and tell the user if the branch is `main`, if there is
   nothing to commit and nothing ahead of `main`, or if `main`'s directory is not clean
   (`git -C <main dir> status --short`).
2. **Commit.** No analysis or tests: just land the work. Review `git status --short`. Stage the
   files that belong to this work by name; leave out anything unrelated (stray `.uid` files,
   scratch files) and mention what you left out. Commit with a message that says what changed and
   why, ending with the attribution line the session's attribution guidance gives for commits.
3. **Bring in main.** `git merge main`. If it conflicts, resolve only trivial conflicts; otherwise
   stop and show the user the conflicting files.
4. **Land it.** `git -C <main dir> merge --ff-only <branch>`. If it refuses because `main` moved,
   go back to step 3. Never force, and never use `--no-verify`.
5. **Push.** `git -C <main dir> push origin main`. If the push is rejected because `origin/main`
   moved, run `git -C <main dir> pull --ff-only origin main`; if that brings in changes, go back to
   step 3 so they are merged into the branch, then land and push again. Never force-push.
6. **Close the ticket.** Read the workspace's links with `orca worktree current --json` (resolve
   the Orca CLI as the `orca-cli` skill says; on macOS it is `orca`): `result.worktree.id`,
   `linkedIssue` (GitHub), `linkedLinearIssue` and `linkedGitLabIssue`. Note the worktree `id` now;
   step 8 needs it.
   - GitHub issue: `gh issue close <number> --comment "Fixed in <short hash>, merged to main."`
   - Linear issue: load the `orca-linear` skill and finish the ticket as it describes.
   - GitLab issue, or no link: skip it and say so. Never guess a ticket.
   If closing fails, report the error and skip step 8 so the workspace stays.
7. **Report.** Say which commits landed on `main` (hashes and subjects), that `origin/main` now
   matches, which ticket was closed, and anything left out of the commit. Write this before step 8.
8. **Remove the workspace, last.** `orca worktree rm --worktree id:<worktree id> --json`, using the
   id from step 6 (not `current`: this directory is about to be deleted). No `--force` and no
   `--run-hooks`. Orca removes the git worktree and its merged local branch. If it refuses (for
   example uncommitted changes), report the error and stop. Nothing runs after this command.
