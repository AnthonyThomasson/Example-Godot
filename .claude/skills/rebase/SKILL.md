---
name: rebase
description: Rebase this branch onto the latest origin/main, keeping uncommitted changes, and resolve conflicts (asking when intent is unclear). Use on `/rebase`, when asked to rebase or catch up with main, and in the ticket workflow after plan acceptance and before the audit.
---

# Rebase

From the worktree root, onto `origin/main`; uncommitted changes stay uncommitted. Local branch only: never push, force,
or touch `main`'s checkout.

1. **Check.** Stop if on `main`. Note the tip (`git rev-parse --short HEAD`) and any upstream
   (`git rev-parse --abbrev-ref @{u}`).
2. **Fetch.** `git fetch origin main`. `git rev-list --count HEAD..origin/main` is 0: up to date, stop. Else list
   `git log --oneline HEAD..origin/main`.
3. **Clear collisions.** Delete each untracked file an incoming commit adds
   (`git diff --name-only --diff-filter=A HEAD..origin/main` ∩ `??` in `git status --short`), else git refuses. Copy it
   to the scratchpad first unless generated (`*.uid`, `*.import`). By name only: never `git clean`, never any other file.
4. **Rebase.** `git rebase --autostash origin/main`. Never `-i`, `--no-verify`, or bare `git stash` / `git stash pop`
   (the stash stack is shared across worktrees).
5. **Conflicts**, until the rebase finishes: for each `git diff --name-only --diff-filter=U` file, compare theirs
   (`git log origin/main -p -- <file>`) with ours (`git show REBASE_HEAD`).
   - Resolve only when both intents are clear and compatible, keeping both; never take a side just to clear it. Don't
     guess at `*.uid`, `*.import`, `project.godot`: regenerate with `"$GODOT" --headless --path . --import` (`$GODOT`: `godot-run`), or ask.
   - No markers left (`grep -n '^<<<<<<<\|^=======\|^>>>>>>>'`), `git add`, `GIT_EDITOR=true git rebase --continue`.
   - Unclear or contradictory: stop; show the hunks, one sentence per side, and the options (either side, or
     `git rebase --abort`, which restores the branch exactly). Wait for the user.
   - Re-applying the uncommitted changes conflicts (rebase done, files unmerged, stash kept): resolve the same way, then
     `git reset` so they stay unstaged. Keep the stash entry until the tree is right; to bail out,
     `git stash apply <sha>` from `git stash list --format='%H %gs'`.
6. **Verify.** `main` added `class_name` scripts: `"$GODOT" --headless --path . --import`. Run
   `tools/run_tests.sh --changed --summary` (sandbox disabled); fix failures the merge caused.
7. **Report:** commits replayed onto which `origin/main` commit, each conflict and its resolution, files deleted in step
   3 (with backup paths), the test result, the pre-rebase tip, and that uncommitted changes are re-applied (or what
   remains in the stash). With an upstream, warn that pushing now needs `--force-with-lease`, which this skill doesn't do.
