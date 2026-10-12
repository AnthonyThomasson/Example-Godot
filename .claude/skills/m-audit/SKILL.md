---
name: m-audit
description: Audit the staged change before it is committed — domain isolation, architecture and domain skills in sync, current-state comments, load check and tests — as a checklist of file:line fixes. Manual only — invoked as `/m-audit`.
disable-model-invocation: true
model: claude-sonnet-5-5
---

# Audit

Run this over the **staged** change, before it is committed — it is the last gate between a
diff and a commit. The output is always a **checklist of concrete issues**, each tied to a
`file:line` and a specific fix, so the author can act on it directly (or a clean bill of health
when there is nothing to fix). Do not commit, merge or push, and do not fix findings unless the
user asks.

Three things make a change healthy in this project, in priority order: the domains stay
**isolated**, the architecture skills stay **true**, and the comments describe the code **as it
is now**. Each has its own section below. Work through them in order and collect findings into the
checklist at the end.

The architecture docs are split across skills (`AGENTS.md` itself is just a stub that points to
them): the **`architecture`** skill is the **map** (the domain table, the vital interfaces, the
dependency graph, the cross-cutting conventions), and each domain has a
`.claude/skills/domain-<folder>/` skill holding that domain's **deep implementation detail**. Both
are held to the same current-state bar as code comments — see Step 3.

## Step 0 — Gather the change and the ground truth

If nothing is staged (`git diff --staged --stat` is empty), say so and stop. Do not stage files
yourself.

```bash
git diff --staged --stat
git diff --staged --name-only --diff-filter=d
git diff --staged            # the actual hunks — read them, this is what you are verifying
```

Then load the **`architecture`** skill. It is the source of truth for this codebase's
architecture: the domain table (one folder per domain under `scenes/`) and, crucially, **"The
vital interfaces"** — the *entire* sanctioned cross-domain surface. Everything not on that list is
private to its domain. You are checking the staged change against that contract, so you need it
fresh in mind.

Also read the `domain-<folder>/SKILL.md` for **every domain the diff touches** (map a changed
`scenes/<folder>/…` file to `.claude/skills/domain-<folder>/SKILL.md`). That skill is the deep
detail for the domain, and the change must leave it true (Step 3).

**Sub-domains have their own skills.** A domain's sub-folder or extracted module that has a skill maps to
`.claude/skills/domain-<domain>-<sub>/SKILL.md`: `ai/{perception,decision,behavior,debug}/` → `domain-ai-<sub>`
(plus `perception/snapshot/` + `agent_snapshot.gd` → `domain-ai-snapshot`, `behavior/combat.gd` → `domain-ai-combat`,
`behavior/search_coverage.gd` → `domain-ai-coverage`), `physics/blood/` → `domain-physics-blood`, `character/body/` →
`domain-character-body`, `ui/{menus,hud,overlays,testing}/` → `domain-ui-<folder>`, and `scenes/main.gd` /
`match_spawner.gd` → `domain-main`. A change to the parent (`goal_controller.gd`, `character.gd`, the set or role of
sub-domains) goes to the parent skill (`domain-ai` overview, `domain-character`, …). Keep both the touched sub-skill and its
parent true. A cross-sub-domain coupling that doesn't flow through the published sub-domain interfaces is an
isolation issue, flagged the same as cross-domain coupling.

## Step 1 — Domain isolation (highest priority)

The whole design rests on domains that can each change on their own. That only holds if the
connections between them are few, deliberate, and named in the `architecture` skill. A change
erodes it when
it quietly adds a new thread between two domains — a call into another domain's internals, a new
`preload` across a boundary, a node reaching in by hard-coded child path, a signal wired straight
to a foreign node. Each new thread is a place a future change in one domain can break another.

For every cross-domain reference the diff introduces or touches, ask **"is this connection
crucial, and is it one of the vital interfaces?"** Route your judgment through these questions:

- **Does it go through a published interface?** If domain A now calls into domain B, that call
  should be one of the interfaces listed in the `architecture` skill (a `class_name` façade like
  `Physics.spawn_debris`, a documented contract method like `get_surface()` / `take_hit()`, a
  named signal). A call into a *private* method, member, or child-node name of another domain is
  the smell. Fix: route it through the existing interface, or — if the connection is genuinely
  needed and new — promote it to a real interface (a small façade / contract method) **and add it
  to the `architecture` skill** (see Step 3).
- **Is it the leanest connection that works?** Reaching in by concrete node name
  (`get_node("GoalController")`) couples to layout; a duck-typed lookup or a one-line seam couples
  to behaviour instead and survives refactors. Prefer the connection that knows the least about
  the other side.
- **Does the dependency direction respect the graph?** The `architecture` skill has a dependency graph with no
  cycles; leaves (Physics, World-Gen) depend on nothing outward. A new edge that points the wrong
  way — a leaf importing a caller, or a cycle — is a defect even if it "works".

Flag each violation with the `file:line`, name which two domains it couples, and give the concrete
reroute. If the change is clean here, say so explicitly — it is the most important section.

## Step 2 — Should a new domain be extracted?

A domain earns its own folder when **its complexity bleeds into several others** — when one
concern forces edits or knowledge into multiple existing domains at once. That is the signal the
concern is really its own thing wearing another domain's clothes. (This is exactly how
`interaction/` and `ai/` came to exist: object-interaction and NPC-decision logic had started to
smear across the character and objects.)

Watch for these in the diff:

- One new feature touches three or more domains, adding coupling to each, rather than living
  behind a single new seam.
- A domain is growing a second, unrelated responsibility (its file header would need "and also …"
  to stay honest).
- The same cross-domain glue is being repeated in several places.

When you see it, recommend the extraction concretely: what the new domain (`scenes/<name>/`) owns,
which logic moves into it, and the one interface the rest of the game would talk to it through —
mirroring how the existing domains are structured. Extraction is a bigger call than a reroute, so
frame it as a recommendation with the reasoning, not a mandate. If nothing warrants it, note that
briefly and move on.

## Step 3 — Keep the architecture skill and the domain skills true

The architecture skills are documentation, so they are held to the same current-state bar as code
comments — and because they are the architecture's source of truth, a change that alters the
architecture but not the skills leaves the next reader with a false map. The responsibility is
split, so update the *right* file (AGENTS.md itself is a stub pointer and rarely needs touching):

**The `architecture` skill (the map)** — update it in the same change when:

- **A domain was added or removed** — update the domain table (including its `domain-<name>`
  skill column) *and* the domain count in the intro ("the N domains"); the prose and the table
  must agree. Adding a domain means adding its `domain-<folder>/SKILL.md` too.
- **A cross-domain interface changed** — a new façade/contract/signal, or a changed signature
  (e.g. an extra parameter, a new return value). The "vital interfaces" list and the dependency
  graph must match what the code now does.
- **A cross-cutting convention changed** — the control/animate/draw layering or the runtime-shape
  rule. Fix the sentence that is now wrong.

**The touched domain's `domain-<folder>/SKILL.md` (the deep detail)** — update it when the
change alters that domain's *internals* as the skill describes them: a pipeline's shape, the
projectile resolution order, the blood-pooling rules, item slots, the input flow, the guard's
choice sets, and so on. A change to a domain's behaviour that leaves its skill describing the old
behaviour is drift, exactly like a stale `architecture` skill. The skill also recaps its own
interface(s), so an interface change updates both the `architecture` list *and* that recap.

Flag any drift you find as a checklist item (`architecture/SKILL.md:line` or
`domain-<name>/SKILL.md:line` →
what to change). Both files' prose must follow the current-state rule in Step 4: state what *is*,
never what changed.

## Step 4 — Comments describe the code as it is now

Comments in this project are a liability when they lie or waffle and an asset when they are short
and true. The bar: **concise, present-tense, current-state only.**

1. **No history, no rationale-for-change.** A comment says what the code *is* and does, never how
   it got there or why it changed. Remove framing like "was X", "renamed from", "moved to/from",
   "now emits", "no longer", "used to", "formerly", "previously", "(was hardcoded …)", and
   speculative "today / tomorrow / later / in future". (Ordinary words that describe current
   behaviour — "old hits", "keep the old collider on failure" — are fine; you are removing
   *history*, not the word "old".)
2. **Concise and to the point.** Trim comments that restate the code or over-explain. One clear
   line beats three hedging ones.
3. **Every method and property has a short description** — a `##` doc comment directly above it,
   or a trailing `## …` on a one-line property/var/signal. Lifecycle overrides (`_ready`,
   `_process`, `_physics_process`, `_draw`, `_init`, `_input`) are exempt from the `##`; if one
   does something non-obvious, a short inline `#` inside the body covers it.
4. **Inline `#` comments only for genuinely interesting or complex business logic** — a real
   gotcha, a non-obvious algorithm step, an ordering dependency, a physics/geometry subtlety. Do
   not narrate code that already reads clearly.
5. **File header:** one `##` block at the top of each script saying what the file is and which
   domain it belongs to.

Run these audits over the **staged** `.gd` files (they are deterministic — prefer them to
eyeballing). Collect the staged set once:

```bash
cd "$(git rev-parse --show-toplevel)"
STAGED_GD=$(git diff --staged --name-only --diff-filter=d -- '*.gd')
```

Undocumented non-lifecycle functions in staged files (should print nothing):

```bash
for f in $STAGED_GD; do
  awk 'prev !~ /^[[:space:]]*##/ && $0 ~ /^[[:space:]]*(static )?func / {
    l=$0; sub(/\(.*/,"",l); gsub(/^[[:space:]]*/,"",l); print FILENAME":"NR": "l } { prev=$0 }' "$f"
done | grep -vE 'func _(ready|process|physics_process|draw|init|input)\b'
```

Member vars / signals without a preceding or trailing `##` (skim — a trailing `## …` counts):

```bash
for f in $STAGED_GD; do
  awk 'prev !~ /^##/ && prev !~ /^@onready/ && ($0 ~ /^@export/ || $0 ~ /^var / || $0 ~ /^signal /) {
    print FILENAME":"NR": "$0 } { prev=$0 }' "$f"
done
```

History / speculation sweep over staged files (each hit should be an ordinary word, not history):

```bash
for f in $STAGED_GD; do
  grep -nHiE '\b(was |were |renamed|moved to|moved from|used to|formerly|previously|today|tomorrow| later\b|in future|hardcoded|the animator)' "$f"
done
```

## Step 5 — It still loads (and, for behaviour, still works)

A change that doesn't parse fails everything above by default. Run the `godot-debug` skill for a
headless load check (run `--import` first if the change added a `class_name` or new file). Report
a clean load, or the exact `SCRIPT ERROR` / `Parse Error` lines.

Then run the GDScript lint, `tools/lint.sh` (Bash sandbox disabled, a few seconds; `tools/run_tests.sh` runs it first
anyway). It lists every warning the editor's Debugger > Errors tab would: unused variable or parameter, integer division,
a name that shadows a member or a built-in, a redundant `await`. Report each as a `file:line` finding. **Never silence a
warning to make it pass: fix the code.** `@warning_ignore`, `@warning_ignore_start`, an underscore prefix that hides a
parameter which should be removed or used, and a lowered warning level in `project.godot` are all last resorts. Accept one
only when no code change can remove the warning, and then only on the one statement, with a comment saying why it cannot
be fixed. Flag every `@warning_ignore*` the staged diff adds (`git diff --staged | grep -n 'warning_ignore'`) and every
`[debug]` / `gdscript/warnings` line it adds to `project.godot` as a finding unless it meets that bar. When renaming to
clear a shadowing warning, grep the function for the old name: a stale reference silently binds to the member it used to
shadow (`name`, `visible`, `material`) and no lint or parse error follows.

Then run the game tests (Bash sandbox disabled; AI changes are covered without a server by the scripted-Von
tests, and `--include-von` adds the live-server ones): `tools/run_tests.sh --changed --summary` runs the touched
domains plus the domains that compose them (and the self-tests for `scenes/testing/` or the Von stub); a change
to worldgen, art, general or `main.gd` makes it run everything, so add `--jobs=auto` there. Report the totals line
and every FAIL / TIMEOUT with its ✗ lines; exit code 1
also covers an engine error/warning logged during a test. A change that adds or alters behaviour should
add or update a test in `tests/<domain>/` (see the `domain-testing` skill) — flag it if none covers it.

If the change alters **behaviour** (movement, combat, items, interactions, world-gen), a clean
load isn't enough — exercise it in the running game. Use the `godot-drive` skill: launch via
`mcp__godot__run_project`, drive the player with the dev command server (`python3 tools/gcmd.py
"<verb>"` — e.g. `tp`, `move`, `fire`, `punch`, `interact`, or raw GDScript through `eval`), and
read the reaction back through `mcp__godot__get_debug_output` (each command echoes as `[cmd] …`).
Report what you drove and what the game did. Two gotchas from that skill: launch Godot from Bash
only with the sandbox disabled, and `mcp__godot__stop_project` orphans the Von server on port 8000.

## Step 6 — Show the finished change in a worktree editor

Once the checks above are green, leave a live copy of the change running for the user. The editor is
named after the worktree (its directory name), so there is no name to pass:

```bash
tools/editor.sh --autorun        # run from the worktree root being verified (Bash sandbox disabled)
```

If an editor is already open on this worktree the script starts nothing and prints `editor already
running` with its pid, port and log; report that and stop (Play is not pressed again). Otherwise it
prints the editor pid, the command-server port and a log path. After ~10 s confirm the log
(`$TMPDIR/editor_<worktree>.log`) shows `[cmd] listening on 127.0.0.1:<port>` and no `SCRIPT ERROR`
(optionally `python3 tools/gcmd.py --port <port> 'scene().name'`). The game opens on the setup menu
with the worktree name at the top. Report the worktree name, port and pid; leave the editor open.

## Output — the checklist

Report findings as a checklist grouped by the sections above, most-important first. Each item is
a `file:line`, the problem in a phrase, and the concrete fix. End with a one-line verdict.

```
## Audit

### Domain isolation
- [ ] `scenes/main.gd:48` — Main couples to the NPC's child node name `"GoalController"`.
      Fix: find the controller by its `control` duck-type instead (as `character._find_controller` does).
- [x] No calls into another domain's private members.

### Domain extraction
- [x] No concern is bleeding across domains; nothing to extract.

### Architecture & domain skills
- [ ] `architecture/SKILL.md:20` — intro says "eight domains" but the table now lists nine (AI added). Fix: "nine".
- [ ] `domain-physics/SKILL.md:41` — blood section describes the 4-arg `spawn_blood`; the code now takes 5. Fix: state the current signature.

### Comments & docs
- [ ] `scenes/physics/physics.gd:33` — comment describes the old signature ("(parent, hit, exclude)"). Fix: state the current 5-arg form.
- [x] Every staged method/property is documented; no history framing.

### Load check & tests
- [x] Headless load clean — no SCRIPT ERROR / Parse Error.
- [ ] `scenes/ai/foo.gd:57` — `@warning_ignore("integer_division")` added to pass the lint. Fix: compute it as `int(a / 2.0)`.
- [x] `tools/lint.sh`: no warnings, and no `@warning_ignore` added.
- [x] `tools/run_tests.sh`: 6 passed, 0 failed, 2 skipped.

### Worktree editor
- [x] `tools/editor.sh --autorun` running for `fix-the-flicker` (pid 4242, port 9345); setup menu shows `fix-the-flicker`.

**Verdict:** 3 issues to address before commit.
```

If everything passes, the verdict is simply that the change is ready to commit — don't invent
issues to look thorough. A clean change is the goal, not a long list.
