---
name: rebase
description: Rebase this branch onto the latest origin/main, keeping uncommitted changes, and resolve conflicts (asking when intent is unclear). Manual only — invoked as `/rebase`.
disable-model-invocation: true
---

# Rebase

Rebase this branch onto `origin/main` from the worktree root. Uncommitted changes are kept
uncommitted. Local branch only: never push, force, or touch `main`'s checkout.

1. **Check.** Stop if the branch is `main`. Note the tip (`git rev-parse --short HEAD`) and whether
   there is an upstream (`git rev-parse --abbrev-ref @{u}`).
2. **Fetch.** `git fetch origin main`. If `git rev-list --count HEAD..origin/main` is 0, say it is
   up to date and stop. Otherwise list `git log --oneline HEAD..origin/main`.
3. **Clear collisions.** Delete any untracked file that an incoming commit adds
   (`git diff --name-only --diff-filter=A HEAD..origin/main` ∩ `git status --short` `??` entries),
   or git refuses. Copy it to the scratchpad first unless it is generated (`*.uid`, `*.import`).
   Delete those paths by name only: never `git clean`, never any other untracked file.
4. **Rebase.** `git rebase --autostash origin/main`. Never `-i`, `--no-verify`, or bare
   `git stash` / `git stash pop` (the stash stack is shared with other worktrees).
5. **Conflicts.** Until the rebase finishes: for each file in `git diff --name-only --diff-filter=U`,
   compare theirs (`git log origin/main -p -- <file>`) with ours (`git show REBASE_HEAD`).
   - Resolve only if both intents are clear and compatible, keeping both. Never take one side just
     to clear the conflict. Don't guess at `*.uid`, `*.import`, `project.godot`: regenerate with
     `godot --headless --path . --import` or ask.
   - Then check no markers remain (`grep -n '^<<<<<<<\|^=======\|^>>>>>>>'`), `git add`, and
     `GIT_EDITOR=true git rebase --continue`.
   - If unclear or contradictory, stop. Show the hunks, one sentence per side, and the options:
     either side, or `git rebase --abort` (restores the branch exactly). Wait for the user.
   - If re-applying the uncommitted changes conflicts (rebase done, files unmerged, stash kept),
     resolve the same way, then `git reset` so they stay unstaged. Keep the stash entry until the
     tree is right; to bail out, `git stash apply <sha>` from `git stash list --format='%H %gs'`.
6. **Verify.** If `main` added `class_name` scripts, run `godot --headless --path . --import`. Run
   `tools/run_tests.sh --changed` (sandbox disabled) and fix failures the merge caused.
7. **Report.** Commits replayed onto which `origin/main` commit, each conflict and its resolution,
   files deleted in step 3 (with backup paths), the test result, the pre-rebase tip, and that the
   uncommitted changes are re-applied (or what remains in the stash). With an upstream, warn that
   pushing now needs `--force-with-lease`, which this skill does not do.
