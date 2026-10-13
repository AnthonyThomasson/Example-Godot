---
name: m-audit-everything
description: Audit the WHOLE codebase for accumulated rot — orphaned mechanisms whose consumer is gone, unreferenced code, duplication, cross-domain coupling that bypasses the published interfaces, domains due for a sub-domain split, and stale skills/comments — as a checklist of file:line findings with concrete fixes. It never deletes anything on its own. Manual only — invoked as `/m-audit-everything`.
disable-model-invocation: true
model: claude-sonnet-5-5
effort: xhigh
---

# Audit everything — whole-codebase health audit

`/m-audit` gates **one branch's change** (its commits since `main`, plus anything staged) before it is pushed. This skill audits the **codebase as
it stands**, looking for what accumulates *between* changes: code nothing calls any more,
mechanisms whose consumer was removed, duplication that crept in, boundaries that eroded, domains
that outgrew one folder, and documentation that quietly stopped being true.

The output is a **checklist of concrete findings**, each tied to a `file:line` with a specific fix.

**Propose, don't delete.** Removal is destructive and some findings will be false positives
(Step 1 explains why). Present the checklist and let the user choose what goes. Only edit after
they say so, and then run Step 6.

## What rot actually looks like here

Run the cheap detectors, but don't mistake them for the audit. This codebase is tight on trivially
dead symbols — a full scan finds a handful of unreferenced functions and **zero** unread
declarations. The rot that genuinely accumulates is the kind a scan can't see:

1. **Orphaned mechanisms** — live, called, well-commented code that still *produces* something
   nothing *consumes*. Every scan calls it reachable; it is pure waste.
2. **Documentation drift** — a skill or comment describing the code of three changes ago.
3. **Eroded boundaries** — a domain quietly relying on another's API that the `architecture` skill
   never published, so a rename in one place changes behaviour in another.

So weight your effort accordingly: the scanner is a five-minute first pass, and Steps 2–5 are where
the real findings are.

## Step 0 — Ground truth

Load the **`architecture`** skill: the domain table, the vital interfaces (the *entire* sanctioned
cross-domain surface), the dependency graph, the cross-cutting conventions. Everything not on that
list is private to its domain, and you are about to audit the whole codebase against it.

Then survey the shape of the thing, so Step 4 has numbers rather than impressions:

```bash
cd "$(git rev-parse --show-toplevel)"
for d in scenes/*/; do
  printf "%-26s %3s files %6s lines\n" "$d" \
    "$(find "$d" -name '*.gd' | wc -l | tr -d ' ')" \
    "$(cat $(find "$d" -name '*.gd') 2>/dev/null | wc -l | tr -d ' ')"
done
find scenes -name '*.gd' -exec wc -l {} + | sort -rn | sed -n 2,16p   # the largest files
```

Read the `domain-<folder>/SKILL.md` for each domain as you reach it — don't load all fourteen up
front. Domains that have been split into sub-domains keep an overview skill plus one `domain-<domain>-<sub>` skill per
sub-domain (`ai/*`, `physics/blood/`, `character/body/`, `ui/*`, `perception/snapshot/`, `behavior/combat.gd`,
`behavior/search_coverage.gd`; the composition root is `domain-main`); treat their boundaries exactly as seriously as
the top-level ones.

`tools/audit_scan.py` holds the mechanical detectors used below (`deps`, `dead`, `signals`,
`facts`, `events`; `all` runs them together). It reads files only — no Godot needed.

## Step 1 — Dead code

Three distinct kinds, in increasing order of how much they actually matter.

### 1a. Unreferenced symbols (cheap, usually near-empty)

```bash
python3 -I tools/audit_scan.py dead
```

Lists functions with no reference anywhere and `const` / `var` / `signal` / `enum` declarations
nothing reads, then the scene symbols only `tests/` or `tools/` reference (a test seam or a leftover) and the
test and tool declarations nothing references. It matches by token, so a same-named member of another class
hides a dead one; grep the qualified name when a hit looks wrong. A reference is any non-comment token in `scenes/ tests/ tools/ addons/` or a `.tscn`,
so a handler connected by bare name (`.connect(_on_x)`) counts as used.

Also worth a look: scripts no scene or `preload` references, and `.gd` files with a missing or
orphaned `.uid`:

```bash
for f in $(find scenes tests tools addons -name '*.gd'); do [ -f "$f.uid" ] || echo "no uid: $f"; done
for u in $(find scenes tests tools addons -name '*.gd.uid'); do [ -f "${u%.uid}" ] || echo "orphan uid: $u"; done
```

**Test coverage:** run `python3 tools/test_coverage.py` for domains with no tests, switches no test uses and
interfaces no test calls; list the gaps worth filling.

**Every hit here is advisory until you confirm it by hand.** This project leans on dynamic
dispatch that no scan can follow, and each of these is a real mechanism in use:

- **Duck-typed controllers** — a controller is "any node with `control(character, delta)`"; the
  match HUD and command server find NPC state by probing for `current_act()` / `debug_status()` /
  `debug_state()`. The *caller* never names the method's file.
- **`Expression` eval** — `general/command_server.gd` evaluates arbitrary GDScript from
  `tools/gcmd.py`, so anything reachable from a `gcmd` verb is live.
- **Scene-wired signals and exported `NodePath`s** — the connection lives in the `.tscn`, not in
  any `.gd`.
- **Contract methods** — `get_surface()`, `take_hit()`, `get_interactions()`, `apply_impulse()`,
  `get_mass()` are called polymorphically across a whole class of objects.

Before proposing a deletion, grep the `.tscn` files and `tools/` for the bare name, and say in the
finding which of these you ruled out. A method that is documented as published API but has no
caller is still a finding: either the doc or the method goes.

### 1b. Orphaned mechanisms (the valuable category)

A producer whose consumer was removed. The code runs, so nothing flags it, and its comments still
confidently explain a purpose the codebase no longer has. Find these by tracing each *mechanism*
end to end: who writes this, and who still reads it?

**The canonical shape, from a real find.** `character/character.gd` declared
`signal item_changed(item)` and emitted it on every slot switch "for the HUD" — but nothing
connected it: the debug HUD reads `current_item()` by polling each frame instead. The emit ran
forever, feeding no one. The `dead` scan calls it reachable (a signal is "used" at its emit site),
so only end-to-end tracing catches it:

```bash
python3 -I tools/audit_scan.py signals   # emit sites vs. listeners for every signal
python3 -I tools/audit_scan.py facts     # decision-snapshot facts no tree node gates on
python3 -I tools/audit_scan.py events    # each EventBus topic's listeners and payload keys with their readers
```

`signals` flags a signal with no listener (`test_context._never` is a deliberate never-emitted
sentinel for `await`). `facts` lists facts `agent_snapshot.gd` writes on every decision that no
decision-tree `requires`, entry rule, test or tool names, marking each as documented (the
`domain-ai-perception` skill and `docs/cover-and-stance.md` present some as vocabulary available to
tree authors) or not. A documented, ungated fact is a judgement call — report it as such rather than
as rot; an undocumented one is an orphan.

That is the shape to hunt for any mechanism: grep the symbols that make it *work* (the keys a
producer writes and a consumer would read, a signal's connections, an obstacle's enable flag) —
**not** the mechanism's own name — and check whether every match sits inside the producing file. If
it does, the consumer is gone. Candidates beyond what the scanner covers: a dict field written on
every option but read nowhere (a past audit found `dist`, `to_target`, `nearby`, `farther` in the
tactics geometry); a leaf/record key the emitter fills that no handler destructures; anything an
export still configures but no code branches on; a cache or log nothing queries. Debug-state dicts
(`behavior.gd` `debug_state()`) are read generically through `gcmd`, so an unread key there is low
value — mention it, don't push it.

### 1c. Vestigial configuration

An `@export` or `const` that nothing branches on, a tuning knob for a behaviour that is gone, or a
`project.godot` setting with no reader. These are worse than dead functions because they look like
working controls — someone will tune them and wonder why nothing happens. Check each config holder
(`BallisticsConfig`, `PhysicsConfig`, `CharacterConfig`, `BloodConfig`, `SoundConfig`, …) and the
controller exports. `dead` already catches an export no code reads; here look for ones that are read
only to be passed along and never branched on.

## Step 2 — Redundancy and duplication

Not "two lines look alike" — duplication that means one fix will have to be made twice.

- **The same logic in two places.** Two files computing the same geometry, two copies of a physics
  query, the same clamp written twice. Say which should own it and which should call across.
  (A past audit of `scenes/ai/perception/` found exactly this: a `QUERY_MASK` constant and a
  `_blocked()` raycast duplicated between the perception face and the vision module. The fix was to
  make the vision module the single owner.)
- **Two paths doing one job.** A fallback and a primary that have converged, or a special case the
  general case now covers.
- **Pass-through indirection.** A wrapper that only forwards, a parameter threaded through several
  layers that each just pass it on. If a module already *owns* a thing, its private helpers
  shouldn't take it as an argument.
- **Dead branches.** A condition that can't be false any more; a null guard on something now
  guaranteed.

## Step 3 — Domain isolation, repo-wide

Step 1 of `/m-audit` asks this of a diff; ask it of every boundary that exists. For each
cross-domain reference, is the connection **crucial**, and is it one of the **vital interfaces** in
the `architecture` skill?

Almost every script here is reached by `class_name`, so a `preload("res://scenes/…")` grep sees
almost nothing. Start from the edge matrix:

```bash
python3 -I tools/audit_scan.py deps
```

It prints every `unit -> unit` edge with the symbols crossing it, counting class names used in code
(comments and string literals are ignored; `scenes/ai/<sub>/` counts as its own unit; `scenes/main.gd`
is the composition root and is *allowed* to know every domain, so it is skipped), then the same matrix for
`preload` / `load` paths and scene `ext_resource` paths, which `class_name` counting cannot see. Then check:

1. **Every edge is published.** Each row must correspond to a vital interface or the dependency graph
   in the `architecture` skill. An edge that isn't is the smell; fix by rerouting through the existing
   interface, or promoting it to a real one (a small façade / contract method) **and adding it to the
   `architecture` skill**.
2. **The direction is right.** The graph has no cycles, and Physics, Navigation, Art, Audio and
   World-Gen are leaves that depend on nothing outward. A new edge pointing the wrong way is a defect
   even if it works.
3. **Duck-typed API is published too.** `class_name` edges miss calls on a node held as plain `Node`
   — the AI and UI call the character and the AI controller that way. List the members actually
   called and compare them with the interface lists:

   ```bash
   grep -rhoE "\b(character|_character|other|body|victim|node)\.(\w+)" scenes/ai --include='*.gd' | sed -E 's/^[^.]+\.//' | sort | uniq -c | sort -rn
   grep -rhoE "\b(_character|_controller|_player|npc)\.(\w+)" scenes/ui scenes/general --include='*.gd' | sed -E 's/^[^.]+\.//' | sort | uniq -c | sort -rn
   ```

   A member called from another domain that no interface lists is a finding (publish it). So is a
   `has_method("x")` probe used as a *type test* ("is this node a character?") — it silently changes
   meaning when `x` is renamed; recommend an explicit marker.
4. **Is it the leanest connection that works?** `get_node("GoalController")` couples to layout; a
   duck-typed probe couples to behaviour and survives refactors.
5. **No reaching into private state.** Another object's `_member`:

   ```bash
   grep -rnE "[a-zA-Z)\]]\._[a-z][a-zA-Z0-9_]*" scenes --include='*.gd' | grep -vE "^\S+:[0-9]+:\s*#|\bself\._"
   ```

   Inside one domain, a draw helper reading its owner's private (`character_visuals` →
   `_character._deformable`) is the control/animate/draw convention, not a violation; across a
   domain it is.

Apply the identical test inside `scenes/ai/` across its four sub-domains: perception, decision,
behaviour and debug talk only through their published interfaces (the `deps` footer reports any
sub-domain→sub-domain `class_name` edge; also read how `behavior.gd` reaches `_perception` and how the
debug overlays reach the controller), and a shortcut between them is an isolation finding exactly
like a cross-domain one.

## Step 4 — Is a domain due to be split?

A concern earns its own module when **its complexity bleeds into several others**, or when one
folder has grown a second, unrelated responsibility. This is how `interaction/` and `ai/` came to
exist, how `ai/` then split internally into four sub-domains around a thin orchestrator, how `objects/` and
`worldgen/` came by their `art/ wall/ floor/` and `categories/` sub-folders, and how `physics/blood/`,
`character/body/`, `ui/{menus,hud,overlays,testing}/` and `ai/perception/snapshot/` were cut out later. Prefer a seam where
the extracted piece owns the state it mutates (a back-reference into the parent's private fields means the seam is wrong);
note that a new script that changes which script loads first can make the headless load check print exit-time
leak errors (see `godot-debug`).

Produce numbers first — the Step 0 table plus, for every domain over ~1,500 lines or ~15 files, the
files grouped by what they are about. Signals to weigh:

- A folder much larger than its siblings, especially one file carrying most of it; any file over
  ~700 lines.
- A file header that would need "and also …" to stay honest.
- Internal clusters that don't talk to each other — a sign of two modules sharing a folder. Test it:
  for a candidate cluster, grep how many files *outside* the cluster mention its symbols. A seam where
  only two or three non-cluster files do is cheap to cut.
- The same cross-domain glue repeated in several places.

Judge by **coupling and responsibility, not line count** — `worldgen/` is large but cohesive, and a
big folder with one job is healthy.

**A split comes with its own skill.** Cut the matching detail out of the parent skill into a new
`domain-<parent>-<sub>` skill (frontmatter `name` = the folder, a trigger-rich `description`), leave the parent an overview and a
one-line pointer per child, and list the child in the `architecture` domain table. A split without its skill leaves the parent
describing two things.

For every split you recommend, be concrete: the proposed sub-folder name(s), which files move, what
the new module owns, and the one interface the rest of the codebase keeps talking to it through
(ideally unchanged, so a move is mechanical: `class_name` references survive a move, only
`preload("res://…")` paths, docs and any scene `ext_resource` need editing — count them). A split is a
bigger call than a reroute, so frame it as a recommendation with its reasoning and rank the candidates
by seam cleanliness. If nothing warrants one, say so in a line and move on. **Do not invent a split to
look thorough.**

## Step 5 — Documentation accuracy

Every doc here is held to the same bar as a code comment: **concise, present-tense, current-state
only.** Audit four layers.

**1. `AGENTS.md`** — a stub pointing at the skills. It should say almost nothing, and that nothing
should be true.

**2. The `architecture` skill (the map)** — the domain table, the vital interfaces list, the
dependency graph, the conventions. Check the **count of domains agrees with reality in every
place it is stated** — the frontmatter `description`, the intro prose, and the table heading all
assert it independently, so they drift apart.

```bash
ls -d scenes/*/ | wc -l    # the real number
grep -rn "domains" AGENTS.md .claude/skills/architecture/SKILL.md | grep -iE "ten|eleven|twelve|nine|thirteen|fourteen|fifteen|[0-9]+ domains"
```

There are **fourteen** domain folders; `AGENTS.md` (×2) and `architecture/SKILL.md` (the
`description`, the intro, the table heading) must all agree. Re-run the grep each audit — the three
assertions in the skill drift independently when a domain is added or removed.

**3. Each `domain-<name>` skill (the deep detail)** — it must describe the domain's internals *as
they are*. Read it against the code and flag every passage that is no longer true. Interface
changes land in two places: the `architecture` list **and** that skill's own recap. Where a
mechanism or method was removed (Step 1a/1b), the skill passages describing it must go too — a
deleted read-only accessor still listed as a sub-domain interface, or a removed signal still in the
Character interface recap, is the usual instance. Also check the files and tests a skill names still
exist (tests live under `tests/<domain>/`, not `scenes/`).

**4. Code comments.** The rules: no history or rationale-for-change ("was X", "renamed from", "now
emits", "no longer", "used to", "formerly", "previously", speculative "later / in future"); concise
over restating the code; a `##` doc comment on every method and property (lifecycle overrides
exempt); inline `#` only for a genuine gotcha, ordering dependency, or geometry subtlety; one `##`
file header naming the file's job and domain.

```bash
# Undocumented non-lifecycle functions.
for f in $(find scenes tools -name '*.gd'); do
  awk 'prev !~ /^[[:space:]]*##/ && prev !~ /^[[:space:]]*@/ && $0 ~ /^[[:space:]]*(static )?func / {
    l=$0; sub(/\(.*/,"",l); gsub(/^[[:space:]]*/,"",l); print FILENAME":"NR": "l } { prev=$0 }' "$f"
done | grep -vE 'func _(ready|process|physics_process|draw|init|input|exit_tree|notification|unhandled_input|enter_tree|integrate_forces)\b'

# Files with no `##` header in their first lines.
for f in $(find scenes -name '*.gd'); do head -3 "$f" | grep -q '^##' || echo "$f"; done

# History / speculation sweep (each hit should be an ordinary word, not history).
grep -rniE '\b(renamed|moved to|moved from|used to|formerly|previously|no longer|in future|for now|todo|fixme|hack|legacy|deprecated)\b' scenes --include='*.gd'
```

The history sweep is noisy by design — "no longer held" appears in plenty of honest sentences. Judge
each hit.

## Step 6 — Nothing broke

An audit that only reads changes nothing, so if you changed nothing, say so and skip this.

If the user accepted edits, the bar is that **behaviour is identical**. Run the `godot-debug`
skill for a headless load check (with `--import` first if a `class_name` moved or a script was added
or moved). Removing something dynamically dispatched won't fail to parse — it fails at runtime — so
run `tools/run_tests.sh --changed`, and if the removal touched anything in the 1a caveat list, drive
it in the game with the `godot-drive` skill and confirm the affected behaviour still happens. Two
gotchas from that skill: launch Godot from Bash only with the sandbox disabled, and a hard kill
orphans the Von decision server on port 8000 (`pkill -f "von serve"`). Re-run
`python3 -I tools/audit_scan.py all` and confirm the findings you fixed are gone and no new edge
appeared in `deps`. Run `tools/lint.sh` too (`run_tests.sh` does first): a removal can leave an unused variable or
parameter behind. Fix such a warning in the code; silencing it (`@warning_ignore`, an underscore prefix on a parameter that
should go, a lowered level in `project.godot`) is a last resort, as in `m-audit`.

## Output — the checklist

Group by the sections above, highest-value first. Each item: a `file:line`, the problem in a phrase,
and the concrete fix. Mark confirmed-clean sections with `[x]` so the reader knows they were
actually checked. Module complexity is a ranked list of recommendations, each with the files that move.

```
## Codebase cleanup

### Dead code
- [ ] `scenes/character/character.gd:56,156` — `signal item_changed` is emitted on every slot
      switch but nothing connects it (the debug HUD polls `current_item()`). Fix: delete the
      signal + emit; remove it from `architecture` and `domain-character` interface recaps.
- [x] No unreferenced functions or unread declarations (scan corrected per 1a; N funcs scanned).

### Redundancy
- [x] No duplicated logic found across domains.

### Domain isolation
- [x] Every cross-domain call goes through a published interface; no cycles.

### Module complexity
- [ ] 1. `physics/` → `physics/blood/` — 12 of 23 files (~1,400 lines) are blood; only 3 other
      files mention it; interface unchanged (`BloodWound`, …). Moves: `blood_*.gd`. Edits: 4 preloads + docs.
- [x] No other domain warrants a split; `ai/` is already sub-divided.

### Documentation
- [ ] `domain-navigation/SKILL.md:NN` — says the furniture-holes overlay is "off by default"; the
      effective default is `main.gd`'s `show_nav_holes` export (on). Fix: state the real default.

**Verdict:** 2 items to clear; isolation and redundancy clean.
```

A clean codebase is the goal, not a long list — **don't manufacture findings to look thorough.** If
a section is genuinely healthy, one `[x]` line is the right answer. Equally, don't soften a real
finding: orphaned code and a stale skill both cost the next reader real time.
