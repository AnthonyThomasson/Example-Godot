---
name: analysis-cleanup
description: Audit the WHOLE codebase for accumulated rot, rather than verifying one change. Use when the user asks to clean up / tidy / audit / review the codebase, to find dead, unused or redundant code, to check the domains are still isolated, to check whether a domain has grown complex enough to split into modules, or to check the documentation still matches the code — and as a periodic health check between features. Finds unreferenced code, orphaned mechanisms whose consumer is gone, duplication, cross-domain coupling that bypasses the published interfaces, domains due for a sub-domain split, and stale skills/comments. Produces a checklist of findings, each with a file:line and a concrete fix; it never deletes anything on its own.
---

# Cleanup — whole-codebase health audit

`analysis-change-verification` gates **one diff** before it is committed. This skill audits the **codebase as
it stands**, looking for what accumulates *between* changes: code nothing calls any more,
mechanisms whose consumer was removed, duplication that crept in, boundaries that eroded, domains
that outgrew one folder, and documentation that quietly stopped being true.

The output is a **checklist of concrete findings**, each tied to a `file:line` with a specific fix.

**Propose, don't delete.** Removal is destructive and some findings will be false positives
(Step 1 explains why). Present the checklist and let the user choose what goes. Only delete after
they say so, and then re-run Step 6.

## What rot actually looks like here

Run the cheap detectors, but don't mistake them for the audit. This codebase is tight on trivially
dead symbols — a full scan finds **zero** unreferenced functions and **zero** unread declarations.
The rot that genuinely accumulates is the kind grep can't see:

1. **Orphaned mechanisms** — live, called, well-commented code that still *produces* something
   nothing *consumes*. Every scan calls it reachable; it is pure waste.
2. **Documentation drift** — a skill or comment describing the code of three changes ago.

So weight your effort accordingly: the greps are a five-minute first pass, and Steps 2–5 are where
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
find scenes -name '*.gd' | wc -l
```

Read the `domain-<folder>/SKILL.md` for each domain as you reach it — don't load all eleven up
front. The AI domain is split into sub-domains, each with its own `domain-ai-<sub>` skill plus the
`domain-ai` overview; treat its sub-domain boundaries exactly as seriously as the top-level ones.

## Step 1 — Dead code

Three distinct kinds, in increasing order of how much they actually matter.

### 1a. Unreferenced symbols (cheap, usually empty)

Functions nothing calls:

```bash
cd "$(git rev-parse --show-toplevel)"
for f in $(find scenes tools -name '*.gd'); do
  grep -oE '^[[:space:]]*(static )?func [a-z_][a-zA-Z0-9_]*' "$f" | sed -E 's/.*func //' | while read -r fn; do
    case "$fn" in _ready|_process|_physics_process|_draw|_init|_input|_exit_tree|_unhandled_input|_notification|_integrate_forces) continue;; esac
    # `calls` also matches the `func NAME(` declaration itself, so compare against the declaration
    # count — not 0 — or every function looks called and the scan never reports a thing.
    calls=$(grep -rhoE "[^a-zA-Z0-9_]$fn\(" scenes tools --include='*.gd' | wc -l | tr -d ' ')
    decls=$(grep -rhoE "^[[:space:]]*(static )?func $fn\(" scenes tools --include='*.gd' | wc -l | tr -d ' ')
    refs=$(grep -rhoE "\"$fn\"|&\"$fn\"|'$fn'" scenes tools --include='*.gd' --include='*.tscn' | wc -l | tr -d ' ')
    [ "$calls" -le "$decls" ] && [ "$refs" -eq 0 ] && echo "UNCALLED $f: $fn"
  done
done
```

Declarations nothing reads (a superset — it includes locals; `-F`/`-w` keep it robust against
GDScript's `%`-format strings, which break naive regex extraction):

```bash
for f in $(find scenes tools -name '*.gd'); do
  awk -v F="$f" '/^[[:space:]]*(@export[^ ]*[[:space:]]+)?(const|var|signal)[[:space:]]+[a-zA-Z_]/ {
    l=$0; sub(/^[[:space:]]*/,"",l); sub(/^@export[^ ]*[[:space:]]+/,"",l)
    sub(/^(const|var|signal)[[:space:]]+/,"",l)
    if (match(l,/^[a-zA-Z_][a-zA-Z0-9_]*/)) print F":"NR":"substr(l,1,RLENGTH)
  }' "$f"
done | while IFS=: read -r f ln sym; do
  uses=$(grep -rnwF -- "$sym" scenes tools --include='*.gd' 2>/dev/null | grep -cv "^$f:$ln:")
  # A copy of the SAME declaration in another file (e.g. a const duplicated in two scene scripts) is
  # not a use — subtract other-file declaration lines, or a file-local symbol looks read via its twin.
  dups=$(grep -rnE "^[[:space:]]*(@export[^ ]*[[:space:]]+)?(const|var|signal)[[:space:]]+$sym\b" scenes tools --include='*.gd' 2>/dev/null | grep -cv "^$f:$ln:")
  tscn=$(grep -rlwF -- "$sym" scenes --include='*.tscn' 2>/dev/null | wc -l | tr -d ' ')
  [ "$((uses - dups))" -le 0 ] && [ "$tscn" -eq 0 ] && echo "UNUSED $f:$ln  $sym"
done
```

Also worth a look: scripts no scene or `preload` references, and `.gd` files with an orphaned
`.uid` (or the reverse).

**Every hit here is advisory until you confirm it by hand.** This project leans on dynamic
dispatch that no grep can follow, and each of these is a real mechanism in use:

- **Duck-typed controllers** — a controller is "any node with `control(character, delta)`"; the
  match HUD and command server find NPC state by probing for `current_act()` / `debug_status()` /
  `debug_state()`. The *caller* never names the method's file.
- **`Expression` eval** — `general/command_server.gd` evaluates arbitrary GDScript from
  `tools/gcmd.py`, so anything reachable from a `gcmd` verb is live. Check
  `.claude/commands/test-ai-behavior.md` too: it passes `--defender`/`--invader` export overrides
  as raw GDScript.
- **Scene-wired signals and exported `NodePath`s** — the connection lives in the `.tscn`, not in
  any `.gd`.
- **Contract methods** — `get_surface()`, `take_hit()`, `get_interactions()`, `apply_impulse()`,
  `get_mass()` are called polymorphically across a whole class of objects.

Before proposing a deletion, grep the `.tscn` files and `tools/` for the bare name, and say in the
finding which of these you ruled out.

### 1b. Orphaned mechanisms (the valuable category)

A producer whose consumer was removed. The code runs, so nothing flags it, and its comments still
confidently explain a purpose the codebase no longer has. Find these by tracing each *mechanism*
end to end: who writes this, and who still reads it?

**The canonical shape, from a real find.** `character/character.gd` declared
`signal item_changed(item)` and emitted it on every slot switch "for the HUD" — but nothing
connected it: the debug HUD reads `current_item()` by polling each frame instead. The emit ran
forever, feeding no one. The 1a scans all call it reachable (a signal is "used" at its emit site),
so only end-to-end tracing catches it: for a signal, grep its `connect` / `await` separately from
its `emit`.

```bash
# A signal whose only matches are its declaration + `.emit` — no `.connect`, no `await` — has no listener.
grep -rn "item_changed" scenes --include='*.gd' --include='*.tscn'
```

That is the shape to hunt for any mechanism: grep the symbols that make it *work* (the keys a
producer writes and a consumer would read, a signal's connections, an obstacle's enable flag) —
**not** the mechanism's own name — and check whether every match sits inside the producing file. If
it does, the consumer is gone. Candidates: a dict field written on every option but read nowhere
(this audit found several — `dist`, `to_target`, `nearby`, `farther` in the tactics geometry); a
leaf/record key the emitter fills that no handler destructures; anything an export still configures
but no code branches on; signals emitted but connected nowhere; a cache or log nothing queries.

### 1c. Vestigial configuration

An `@export` or `const` that nothing branches on, a tuning knob for a behaviour that is gone, or a
`project.godot` setting with no reader. These are worse than dead functions because they look like
working controls — someone will tune them and wonder why nothing happens. Check each config holder
(`BallisticsConfig`, `PhysicsConfig`, `CharacterConfig`, `BloodConfig`) and the controller exports.

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

Step 1 of `analysis-change-verification` asks this of a diff; ask it of every boundary that exists. For each
cross-domain reference, is the connection **crucial**, and is it one of the **vital interfaces** in
the `architecture` skill?

- **Does it go through a published interface?** A call into another domain's private method,
  member, or child-node name is the smell. Fix: reroute through the existing interface, or promote
  it to a real one (a small façade / contract method) **and add it to the `architecture` skill**.
- **Is it the leanest connection that works?** `get_node("GoalController")` couples to layout; a
  duck-typed probe couples to behaviour and survives refactors.
- **Does it respect the dependency direction?** The graph has no cycles, and Physics, Navigation
  and World-Gen are leaves that depend on nothing outward. A new edge pointing the wrong way is a
  defect even if it works.

Useful sweep — a domain folder naming another domain's internals:

```bash
grep -rn "get_node(\"\|get_node('\|\$[A-Z]" scenes --include='*.gd' | grep -v "^scenes/main.gd"
grep -rn "preload(\"res://scenes/" scenes --include='*.gd'
```

`scenes/main.gd` is the composition root and is *allowed* to know every domain — exclude it, and
don't report it as a violation.

Apply the identical test inside `scenes/ai/` across its four sub-domains: perception, decision,
behaviour and debug talk only through their published interfaces, and a shortcut between them is an
isolation finding exactly like a cross-domain one.

## Step 4 — Is a domain due to be split?

A concern earns its own module when **its complexity bleeds into several others**, or when one
folder has grown a second, unrelated responsibility. This is how `interaction/` and `ai/` came to
exist, and how `ai/` then split internally into four sub-domains around a thin orchestrator.

Signals to weigh (with the Step 0 numbers in hand):

- A folder much larger than its siblings, especially one file carrying most of it.
- A file header that would need "and also …" to stay honest.
- Internal clusters that don't talk to each other — a sign of two modules sharing a folder.
- The same cross-domain glue repeated in several places.

For reference, `ai/` crossed this line at ~11 files and split; most domains sit well under that.
Judge by **coupling and responsibility, not line count** — `worldgen/` is large but cohesive, and a
big folder with one job is healthy.

When you do see it, make the recommendation concrete: what the new module owns, which code moves,
and the one interface the rest would talk to it through. A split is a bigger call than a reroute, so
frame it with its reasoning as a recommendation — and if nothing warrants one, say so in a line and
move on. **Do not invent a split to look thorough.**

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
grep -rn "domains" AGENTS.md .claude/skills/architecture/SKILL.md | grep -iE "ten|eleven|twelve|nine|[0-9]+ domains"
```

There are **eleven** domain folders; `AGENTS.md` (×2) and `architecture/SKILL.md` (the
`description`, the intro, the table heading) must all agree. Re-run the grep each audit — the three
assertions in the skill drift independently when a domain is added or removed.

**3. Each `domain-<name>` skill (the deep detail)** — it must describe the domain's internals *as
they are*. Read it against the code and flag every passage that is no longer true. Interface
changes land in two places: the `architecture` list **and** that skill's own recap. Where a
mechanism or method was removed (Step 1a/1b), the skill passages describing it must go too — a
deleted read-only accessor still listed as a sub-domain interface, or a removed signal still in the
Character interface recap, is the usual instance.

**4. `.claude/commands/test-ai-behavior.md`** — it passes real GDScript into the game, so stale
content actively breaks. A removed or renamed export leaves dead `--defender`/`--invader` override
lines; a changed decision rule leaves a wrong "Expected:" note.

**5. Code comments.** The rules: no history or rationale-for-change ("was X", "renamed from", "now
emits", "no longer", "used to", "formerly", "previously", speculative "later / in future"); concise
over restating the code; a `##` doc comment on every method and property (lifecycle overrides
exempt); inline `#` only for a genuine gotcha, ordering dependency, or geometry subtlety; one `##`
file header naming the file's job and domain.

```bash
# Undocumented non-lifecycle functions.
for f in $(find scenes tools -name '*.gd'); do
  awk 'prev !~ /^[[:space:]]*##/ && $0 ~ /^[[:space:]]*(static )?func / {
    l=$0; sub(/\(.*/,"",l); gsub(/^[[:space:]]*/,"",l); print FILENAME":"NR": "l } { prev=$0 }' "$f"
done | grep -vE 'func _(ready|process|physics_process|draw|init|input|exit_tree|notification)\b'

# History / speculation sweep (each hit should be an ordinary word, not history).
grep -rniE '\b(was |were |renamed|moved to|moved from|used to|formerly|previously|today|tomorrow| later\b|in future|hardcoded)' scenes --include='*.gd'
```

The history sweep is noisy by design — "was" appears in plenty of honest sentences. Judge each hit.

## Step 6 — Nothing broke

An audit that only reads changes nothing, so if you changed nothing, say so and skip this.

If the user accepted deletions, the bar is that **behaviour is identical**. Run the `godot-debug`
skill for a headless load check (with `--import` first if a `class_name` moved). Removing something
dynamically dispatched won't fail to parse — it fails at runtime — so if the removal touched
anything in the 1a caveat list, drive it in the game with the `godot-drive` skill and confirm the
affected behaviour still happens. Two gotchas from that skill: launch Godot from Bash only with the
sandbox disabled, and a hard kill orphans the Von decision server on port 8000 (`pkill -f "von
serve"`).

## Output — the checklist

Group by the sections above, highest-value first. Each item: a `file:line`, the problem in a phrase,
and the concrete fix. Mark confirmed-clean sections with `[x]` so the reader knows they were
actually checked.

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
- [x] No domain warrants a split; `ai/` is already sub-divided.

### Documentation
- [ ] `domain-navigation/SKILL.md:NN` — says the furniture-holes overlay is "off by default"; the
      effective default is `main.gd`'s `show_nav_holes` export (on). Fix: state the real default.

**Verdict:** 2 items to clear; isolation and redundancy clean.
```

A clean codebase is the goal, not a long list — **don't manufacture findings to look thorough.** If
a section is genuinely healthy, one `[x]` line is the right answer. Equally, don't soften a real
finding: orphaned code and a stale skill both cost the next reader real time.
