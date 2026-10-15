---
name: audit
description: Audit the branch's change against main (commits + staged): isolation, skills true, current-state comments, load/lint/tests, as a file:line checklist. Use before a push or PR, when asked to review the branch, and as a ticket's audit phase.
model: claude-sonnet-5-5
---

# Audit

Audits every commit since the branch left `main`, plus anything staged. Output: a checklist, each issue a `file:line`
with a concrete fix. Report only: never commit, merge, push, edit or fix unless the user asks. One agent does every
step and starts no workers. Priorities: domains **isolated**, skills **true**, comments **current**. Step 5 runs Godot,
lint and tests (Bash sandbox disabled); nothing edits a tracked file. Two steps raising one line is one item.

## Step 0 — Scope

The change is the index against the merge-base with `origin/main` (else `main`, or `/audit <ref>`).

```bash
cd "$(git rev-parse --show-toplevel)"
BASE_REF=origin/main; git rev-parse --verify -q "$BASE_REF" >/dev/null || BASE_REF=main   # or the user's ref
BASE=$(git merge-base "$BASE_REF" HEAD)
git log --oneline "$BASE"..HEAD            # the branch's commits
git diff --staged --stat "$BASE"           # committed + staged
git diff --staged --name-only --diff-filter=d "$BASE"
git diff --staged "$BASE"                  # the hunks you are verifying; reuse for every step
git diff --stat                            # unstaged edits (not in the diff)
```

Empty diff: say so and stop. Never stage files. Unstaged edits are outside the diff but step 5 sees them: report them.

Load `architecture` (the domain table and "The vital interfaces", the whole sanctioned cross-domain surface) and the
skill of every domain the diff touches, once. `scenes/<folder>/` → `domain-<folder>`; sub-domains have their own:

| Path | Skill |
|---|---|
| `ai/perception/` | `domain-ai-perception` |
| `ai/perception/snapshot/`, `ai/perception/agent_snapshot.gd` | `domain-ai-snapshot` |
| `ai/decision/` | `domain-ai-decision` |
| `ai/behavior/` | `domain-ai-behavior` |
| `ai/behavior/combat.gd` | `domain-ai-combat` |
| `ai/behavior/search_coverage.gd` | `domain-ai-coverage` |
| `ai/behavior/watch.gd` | `domain-ai-watch` |
| `ai/behavior/entry.gd` | `domain-ai-entry` |
| `ai/debug/` | `domain-ai-debug` |
| `ai/goal_controller.gd`, `ai/team/`, the set of AI sub-domains | `domain-ai` |
| `physics/blood/` | `domain-physics-blood` |
| `character/body/` | `domain-character-body` |
| `ui/{menus,hud,overlays,testing}/` | `domain-ui-<folder>` |
| `scenes/main.gd`, `scenes/match_spawner.gd` | `domain-main` |

A change to a parent (`goal_controller.gd`, `character.gd`, a sub-domain's role) goes to the parent skill; keep both the
sub-skill and its parent true. A coupling between sub-domains that bypasses their published interfaces is an isolation
finding, like a cross-domain one.

## Step 1 — Domain isolation (highest priority)

For every cross-domain reference the diff adds or touches (a call into internals or a private member, a cross-boundary
`preload`, a hard-coded child path, a signal wired straight to a foreign node):

- **Published?** A call into another domain must be an `architecture` interface (a `class_name` façade like
  `Physics.spawn_debris`, a contract method like `get_surface()` / `take_hit()`, a named signal). A private method,
  member or child-node name is the smell. Fix: reroute through the interface, or promote a genuinely needed new one to
  a small façade / contract method **and add it to `architecture`**.
- **Leanest?** Reaching in by node name (`get_node("GoalController")`) couples to layout; a duck-typed lookup survives
  refactors. Prefer what knows least about the other side.
- **Direction?** `architecture`'s dependency graph has no cycles and its leaves depend on nothing outward. An edge the
  wrong way is a defect even if it works.

Each violation: `file:line`, the two domains, the reroute. Clean: say so explicitly.

## Step 2 — Should a new domain be extracted?

Signals: one feature adds coupling to three or more domains instead of living behind one new seam; a domain grows a
second, unrelated responsibility (its header would need "and also …"); the same cross-domain glue repeats. Then
recommend concretely, with reasoning: what `scenes/<name>/` owns, which logic moves, the one interface the rest talks
to. Nothing warrants it: one line.

## Step 3 — Skills stay true

Same current-state bar as step 4. `AGENTS.md` is a pointer stub.

- **`architecture`** changes in the same change when: a domain is added or removed (the table with its skill column,
  the domain count in the description and intro, and a new `domain-<folder>/SKILL.md`); a cross-domain interface
  changes (new façade/contract/signal, a changed signature: the vital interfaces list and the dependency graph); a
  cross-cutting convention changes (control/animate/draw layering, runtime shapes).
- **`domain-<folder>`** changes when the domain's internals as the skill describes them change (a pipeline's shape,
  resolution order, item slots, input flow …). Interface signatures live only in `architecture`; the domain skill
  names them by number.

Flag drift as `architecture/SKILL.md:line` or `domain-<name>/SKILL.md:line` → what to change.

## Step 4 — Comments (the comment rules)

The rules every audit uses (`m-audit-everything` points here). Concise, present-tense, current state only:

1. **No history or rationale-for-change.** Remove "was X", "renamed from", "moved to/from", "now emits", "no longer",
   "used to", "formerly", "previously", "(was hardcoded …)", and speculative "today / tomorrow / later / in future".
   Ordinary words describing current behaviour ("old hits", "keep the old collider") are fine.
2. **Concise.** Cut comments that restate the code or over-explain.
3. **Every method and property has a `##` doc comment** directly above, or a trailing `## …` on a one-line
   var/signal. Lifecycle overrides (`_ready`, `_process`, `_physics_process`, `_draw`, `_init`, `_input`, `_unhandled_input`, `_enter_tree`, `_exit_tree`, `_notification`, `_integrate_forces`) are exempt;
   a short inline `#` covers anything non-obvious in one.
4. **Inline `#` only for a real gotcha**: a non-obvious algorithm step, an ordering dependency, a physics/geometry
   subtlety.
5. **File header:** one `##` block at the top saying what the file is and its domain.

Run these over the changed `.gd` files (prefer them to eyeballing):

```bash
cd "$(git rev-parse --show-toplevel)"
CHANGED_GD=$(git diff --staged --name-only --diff-filter=d "$BASE" -- '*.gd')

# Undocumented non-lifecycle functions (should print nothing)
for f in $CHANGED_GD; do
  awk 'prev !~ /^[[:space:]]*##/ && $0 ~ /^[[:space:]]*(static )?func / {
    l=$0; sub(/\(.*/,"",l); gsub(/^[[:space:]]*/,"",l); print FILENAME":"NR": "l } { prev=$0 }' "$f"
done | grep -vE 'func _(ready|process|physics_process|draw|init|input|exit_tree|notification|unhandled_input|enter_tree|integrate_forces)\b'

# Member vars / signals without a preceding `##` (a trailing `## …` counts: skim)
for f in $CHANGED_GD; do
  awk 'prev !~ /^##/ && prev !~ /^@onready/ && ($0 ~ /^@export/ || $0 ~ /^var / || $0 ~ /^signal /) {
    print FILENAME":"NR": "$0 } { prev=$0 }' "$f"
done

# History / speculation (each hit should be an ordinary word)
for f in $CHANGED_GD; do
  grep -nHiE '\b(was |were |renamed|moved to|moved from|used to|formerly|previously|today|tomorrow| later\b|in future|hardcoded|the animator)' "$f"
done
```

## Step 5 — Load, lint, tests, behaviour

- **Load:** `tools/load_check.sh` (`godot-run`; `--import` first if the change added a `class_name` or file). Report
  clean, or the exact `SCRIPT ERROR` / `Parse Error` lines.
- **Lint:** `tools/lint.sh`; each warning is a `file:line` finding. **Never silence a warning: fix the code.**
  `@warning_ignore*`, an underscore prefix hiding a parameter that should go or be used, or a lowered level in
  `project.godot` is accepted only when no code change can remove it, on that one statement, with a comment saying why.
  Flag every one the diff adds (`git diff --staged "$BASE" | grep -n '^+.*warning_ignore'`) and every added `[debug]` /
  `gdscript/warnings` line in `project.godot` unless it meets that bar. After a rename that clears a shadowing warning,
  grep the function for the old name: a stale reference silently binds to the member (`name`, `visible`, `material`).
- **Tests:** `GAME_TEST_CHANGED_FILES="$(git diff --staged --name-only "$BASE")" tools/run_tests.sh --changed --summary`.
  The variable hands `--changed` the branch's files (without it, committed work runs nothing). Add `--jobs=auto` when
  the change touches worldgen, art, general or `main.gd` (runs everything). Scripted-Von tests cover AI without a
  server; `--include-von` adds live-server ones. Report the totals line and every FAIL / TIMEOUT with its ✗ lines; exit
  1 also covers an engine error/warning during a test. Changed behaviour with no test in `tests/<domain>/` covering it
  is a finding (`domain-testing`).
- **Behaviour** (movement, combat, items, interactions, world-gen): also drive it live with `godot-run`
  (`tools/editor.sh` + `tools/gcmd.py`). Report what you drove and what the game did.

## Step 6 — Show

Only when step 5 is green: invoke `show-me`. Report the worktree name, port and pid (or that it was already running).

## Output

Scope line (base ref, merge-base short sha, commit count, anything staged), then the checklist by step, each item
`file:line` — problem — fix, then a one-line verdict. Don't invent issues; clean = ready to push.

```
## Audit
Base origin/main @ 1a2b3c4, 3 commits, nothing staged.

### Domain isolation
- [ ] `scenes/main.gd:48` — couples to the NPC's child node name `"GoalController"`. Fix: find the controller by its `control` duck-type.
- [x] No calls into another domain's private members.

### Architecture & domain skills
- [ ] `domain-physics/SKILL.md:41` — describes the 4-arg `spawn_blood`; the code takes 5. Fix: state the current signature.

### Load check & tests
- [x] Load clean. `tools/lint.sh`: no warnings, no `@warning_ignore` added.
- [x] `tools/run_tests.sh`: 6 passed, 0 failed, 2 skipped.

### Worktree editor
- [x] `fix-the-flicker` running (pid 4242, port 9345).

**Verdict:** 2 issues to address before the branch is pushed.
```
