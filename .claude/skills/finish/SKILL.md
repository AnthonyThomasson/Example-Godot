---
name: finish
description: Commit this worktree's work, merge it into main and push main. Manual only — invoked as `/finish`.
disable-model-invocation: true
model: haiku
---

# Finish

Commit the work in this worktree, land it on `main` and push `main`. Run from the worktree root.
Push `main` only: do not push the branch, and do not delete the branch or the worktree.

1. **Preconditions.** Get the branch (`git branch --show-current`) and the directory where `main`
   is checked out (the `worktree` entry with `branch refs/heads/main` in
   `git worktree list --porcelain`). Stop and tell the user if the branch is `main`, if there is
   nothing to commit and nothing ahead of `main`, or if `main`'s directory is not clean
   (`git -C <main dir> status --short`).
2. **Verify.** Run `tools/run_tests.sh --changed` (Bash sandbox disabled) and fix any failure before
   committing.
3. **Commit.** Review `git status --short`. Stage the files that belong to this work by name; leave
   out anything unrelated (stray `.uid` files, scratch files) and mention what you left out. Commit
   with a message that says what changed and why, ending with the attribution line the session's
   attribution guidance gives for commits.
4. **Bring in main.** `git merge main`. If it conflicts, resolve only trivial conflicts; otherwise
   stop and show the user the conflicting files. If the merge brought in changes, run
   `tools/run_tests.sh --changed` (Bash sandbox disabled) and fix any failure before going on.
5. **Land it.** `git -C <main dir> merge --ff-only <branch>`. If it refuses because `main` moved,
   go back to step 4. Never force, and never use `--no-verify`.
6. **Push.** `git -C <main dir> push origin main`. If the push is rejected because `origin/main`
   moved, run `git -C <main dir> pull --ff-only origin main`; if that brings in changes, go back to
   step 4 so they are merged into the branch and tested, then land and push again. Never force-push.
7. **Report.** Say which commits landed on `main` (hashes and subjects), that `origin/main` now
   matches, and anything left out of the commit.
