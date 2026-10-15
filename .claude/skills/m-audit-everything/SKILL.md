---
name: m-audit-everything
description: Audit the WHOLE codebase for rot (orphaned mechanisms, dead code, duplication, unpublished coupling, domains due a split, stale docs) as a file:line checklist, via a phased Orca orchestration. Manual only (`/m-audit-everything`).
disable-model-invocation: true
model: claude-sonnet-5-5
effort: xhigh
---

# Audit everything

Audits the codebase as it stands (`audit` covers one branch). Output: a checklist, each item a `file:line` with a fix.
**Propose, don't delete:** edit only items the user accepts (Phase 4), then Step 6. The scans find little; spend the
effort on Briefs 1b–5: **orphaned mechanisms** (live code feeding nothing), **doc drift**, **eroded boundaries**.

## Phases

Load `orchestration` (`orca skills get orchestration`; on macOS the executable is `orca`) and follow its coordinator
loop. You are the coordinator; never substitute a non-Orca subagent.

| Phase | Owner | Work | Gate |
| --- | --- | --- | --- |
| 0 — Scan | you | Step 0 survey, `audit_scan.py all`, uid check, `test_coverage.py`, saved under `$AUDIT_DIR` | outputs exist |
| 1 — Code wave | 5 workers, parallel, read-only | **1a** unreferenced symbols · **1b** orphaned mechanisms + vestigial config · **2** redundancy · **3** isolation · **4** splits | every Dispatch settled |
| 2 — Docs wave | up to 4 workers, parallel, read-only | **5a** `AGENTS.md` + `architecture` · **5b–5c** domain skills, sharded · **5d** code comments | every Dispatch settled |
| 3 — Merge | you | merge reports into the Output checklist, then ask which items to apply | the user answers |
| 4 — Fix + verify | one worker per disjoint file set, then one verifier | apply accepted items; Step 6 | verifier green |

Docs after code: Brief 5 drops the skill passages for what Phase 1 finds dead and describes its splits, so every
Phase 2 worker gets the Phase 1 report paths. Nothing is edited before Phase 4.

**Phase 0** (workers share this worktree):

```bash
AUDIT_DIR="${TMPDIR:-/tmp}/m-audit-everything-$(basename "$PWD")"; mkdir -p "$AUDIT_DIR"
python3 -I tools/audit_scan.py all > "$AUDIT_DIR/scan.txt"
python3 tools/test_coverage.py      > "$AUDIT_DIR/test_coverage.txt"
for f in $(find scenes tests tools addons -name '*.gd'); do [ -f "$f.uid" ] || echo "no uid: $f"; done  > "$AUDIT_DIR/uids.txt"
for u in $(find scenes tests tools addons -name '*.gd.uid'); do [ -f "${u%.uid}" ] || echo "orphan uid: $u"; done >> "$AUDIT_DIR/uids.txt"
# plus the Step 0 size table, saved as $AUDIT_DIR/survey.txt
```

**A wave.** Create the Run once (`orca orchestration run-create --objective "m-audit-everything of <branch>" --json`),
start every worker of the wave, then wait:

```bash
orca orchestration worker-start --task-title "<name>" --spec "<spec>" --worktree current --agent claude --json   # one per worker
orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json
```

Spec template (literal paths; a worker has no `$AUDIT_DIR`):

> **Target:** the whole codebase as it stands in `<worktree path>`; scan outputs in `<AUDIT_DIR>` (`scan.txt`,
> `test_coverage.txt`, `uids.txt`, `survey.txt`) [; Phase 1 reports `<AUDIT_DIR>/report-*.md` for a docs worker].
> **Change:** produce the findings of `[Brief N — name, part ‹x›]` in `.claude/skills/m-audit-everything/SKILL.md`; read
> that brief, the `architecture` skill first, then `[the domain-*/ skills for the domain(s) it covers]`.
> **Constraints:** read-only — edit, stage, commit, stash and ticket nothing; propose, never delete; confirm every scan hit
> by hand and name which dynamic-dispatch mechanism you ruled out; do not pad a clean section. **Ownership:** you own
> exactly one file, `<AUDIT_DIR>/report-[id].md`. **Observable acceptance:** that file holds the brief's checklist — one
> `- [ ] file:line — problem. Fix: …` per issue, `- [x] …` per confirmed-clean item, ending in a one-line verdict; your
> `worker_done` summary gives the issue count and passes the file as `--report-path`.

Worker ids: `1a 1b 2 3 4 5a 5b 5c 5d`. 5b–5c split the domain skills into two halves of similar line count (`domain-ai*`
first; `domain-ui*`, `general`, `main`, `testing` in the second); each reads only its shard. 5d may split by `scenes/`
subtree if large.

A `failed` outcome, missing report or uncovered shard is a finding ("brief N did not complete: …"). After each wave
release settled workers; start no phase while `worker-list --run <run_id> --terminal-state reclaimable` returns any.

**Phase 3.** Merge every `report-*.md` into the Output checklist, keeping each `file:line` and fix verbatim; the same
line from two workers is one item. Rank split candidates by seam cleanliness. Ask which items to apply.

**Phase 4.** Accepted items only, grouped by file: one worker per **disjoint** file set, each spec naming its items and
files, acceptance "the item is gone and behaviour is identical". Then one verifier worker for Step 6, alone (it launches
Godot and Von). A failing item is reported, not silently retried.

## Step 0 — Ground truth (Phase 0)

Load `architecture`. Survey sizes for Brief 4:

```bash
cd "$(git rev-parse --show-toplevel)"
for d in scenes/*/; do
  printf "%-26s %3s files %6s lines\n" "$d" \
    "$(find "$d" -name '*.gd' | wc -l | tr -d ' ')" \
    "$(cat $(find "$d" -name '*.gd') 2>/dev/null | wc -l | tr -d ' ')"
done
find scenes -name '*.gd' -exec wc -l {} + | sort -rn | sed -n 2,16p   # the largest files
```

Read each `domain-<folder>` skill as you reach it; sub-domain boundaries (map in `audit`, step 0) count like domain
ones. `tools/audit_scan.py` (`deps`, `dead`, `signals`, `facts`, `events`, `all`) reads files only.

## Brief 1 — Dead code (workers 1a, 1b)

### 1a. Unreferenced symbols

```bash
python3 -I tools/audit_scan.py dead
```

Matches by token (a same-named member elsewhere hides a dead one: grep the qualified name); any non-comment token in
`scenes/ tests/ tools/ addons/` or a `.tscn` counts. Also check scripts nothing references, `uids.txt`, and the gaps in
`test_coverage.txt` worth filling.

**Every hit is advisory until confirmed by hand.** Dynamic dispatch no scan follows:

- **Duck-typed controllers:** any node with `control(character, delta)`; the match HUD and command server probe
  `current_act()` / `debug_status()` / `debug_state()`.
- **`Expression` eval:** `general/command_server.gd` evaluates GDScript from `tools/gcmd.py`; anything reachable from a
  verb is live.
- **Scene-wired signals and exported `NodePath`s** live in the `.tscn`.
- **Contract methods:** `get_surface()`, `take_hit()`, `get_interactions()`, `apply_impulse()`, `get_mass()`.

Grep the `.tscn` files and `tools/` for the bare name before proposing a deletion, and name which mechanism you ruled
out. A documented published method with no caller is still a finding: the doc or the method goes.

### 1b. Orphaned mechanisms (the valuable category)

A producer whose consumer is gone: trace who writes it and who still reads it. (`dead` counts an emitted signal as
used, so a signal nobody connects only shows here.)

```bash
python3 -I tools/audit_scan.py signals   # emit sites vs listeners per signal
python3 -I tools/audit_scan.py facts     # snapshot facts no tree node gates on
python3 -I tools/audit_scan.py events    # each EventBus topic's listeners, payload keys and their readers
```

- `signals`: a signal with no listener (`test_context._never` is a deliberate `await` sentinel).
- `facts`: facts `agent_snapshot.gd` writes that no tree `requires`, entry rule, test or tool names, marked documented
  (vocabulary in `domain-ai-perception` / `docs/cover-and-stance.md`: a judgement call, report as such) or not (an orphan).
- By hand: grep the symbols that make it *work* (keys a consumer reads, connections, an enable flag), not its name; all
  matches in the producing file = orphan. Candidates: a dict field written but never read, a record key no handler
  reads, a cache or log nothing queries. Unread `behavior.gd` `debug_state()` keys are read via `gcmd`: mention only.

### 1c. Vestigial configuration (worker 1b)

An `@export`, `const` or `project.godot` setting nothing branches on (it looks like a working control). Check the
config holders (`BallisticsConfig`, `PhysicsConfig`, `CharacterConfig`, `BloodConfig`, `SoundConfig`, …) and controller
exports for values only passed along; `dead` already catches unread ones.

## Brief 2 — Redundancy (worker 2)

Duplication that means one fix must be made twice:

- **Same logic twice** (geometry, a physics query, a clamp): say which owns it and which calls across.
- **Two paths, one job:** a fallback converged with its primary; a special case the general case covers.
- **Pass-through indirection:** a forwarding wrapper, a parameter threaded through layers; a module's private helpers
  shouldn't take what the module owns as an argument.
- **Dead branches:** a condition that can't be false, a null guard on something guaranteed.

## Brief 3 — Domain isolation, repo-wide (worker 3)

`audit` step 1, for every boundary. Start from the edge matrix:

```bash
python3 -I tools/audit_scan.py deps
```

It prints every `unit -> unit` edge with the crossing symbols (class names in code; comments and strings ignored;
`scenes/ai/<sub>/` is its own unit; `scenes/main.gd` is skipped as the composition root), then the `preload` / `load` and
scene `ext_resource` matrices. Check:

1. **Every edge is published** in `architecture`'s interfaces or graph. If not: reroute, or promote to a small façade /
   contract method **and add it to `architecture`**.
2. **Direction:** no cycles; Physics, Navigation, Art, Audio and World-Gen are leaves.
3. **Duck-typed calls** (AI and UI call the character and controller as plain `Node`) are published too:

   ```bash
   grep -rhoE "\b(character|_character|other|body|victim|node)\.(\w+)" scenes/ai --include='*.gd' | sed -E 's/^[^.]+\.//' | sort | uniq -c | sort -rn
   grep -rhoE "\b(_character|_controller|_player|npc)\.(\w+)" scenes/ui scenes/general --include='*.gd' | sed -E 's/^[^.]+\.//' | sort | uniq -c | sort -rn
   ```

   An unlisted member called across domains: publish it. A `has_method("x")` used as a type test changes meaning on a
   rename: recommend an explicit marker.
4. **Leanest connection:** `get_node("GoalController")` couples to layout; a duck-typed probe to behaviour.
5. **No private reach-in:**

   ```bash
   grep -rnE "[a-zA-Z)\]]\._[a-z][a-zA-Z0-9_]*" scenes --include='*.gd' | grep -vE "^\S+:[0-9]+:\s*#|\bself\._"
   ```

   Within a domain, a draw helper reading its owner's private (`character_visuals` → `_character._deformable`) is the
   control/animate/draw convention; across domains it is a violation.

The same test applies between the AI sub-domains (perception, decision, behaviour, debug): the `deps` footer reports
sub-domain `class_name` edges; also read how `behavior.gd` reaches `_perception` and how the debug overlays reach the
controller.

## Brief 4 — Is a domain due a split? (worker 4)

Numbers first: the Step 0 table, plus each domain over ~1,500 lines or ~15 files grouped by topic. Signals: a folder
far larger than its siblings or one file carrying most of it; a file over ~700 lines; a header needing "and also …";
clusters that don't talk to each other (two or three outside files mentioning a cluster = a cheap cut); repeated
cross-domain glue. Judge coupling and responsibility, not size (`worldgen/` is large but cohesive). A good seam owns
the state it mutates (a back-reference into the parent's privates is the wrong seam). A new script changing load order
can add exit-time leak lines to the load check (`godot-run`, `--strict-exit`).

**A split comes with its skill:** move the detail into a new `domain-<parent>-<sub>` (`name` = folder, a trigger-rich
`description`), leave the parent an overview plus a one-line pointer per child, add the child to `architecture`'s table.

Per recommendation: sub-folder name(s), files that move, what it owns, the one interface the rest keeps (`class_name`
survives a move; count the `preload("res://…")` paths, docs and `ext_resource`s to edit). Rank by seam cleanliness.
**Never invent a split.**

## Brief 5 — Documentation (workers 5a–5d)

Same bar as comments: concise, present-tense, current state. Read the Phase 1 reports first.

1. **`AGENTS.md`** (5a): a stub pointing at the skills; it says little, all true.
2. **`architecture`** (5a): domain table, vital interfaces, dependency graph, conventions. The domain count must agree
   everywhere it is stated (`AGENTS.md` ×2; the skill's `description`, intro, table heading):

   ```bash
   ls -d scenes/*/ | wc -l    # the real number (sixteen)
   grep -rn "domains" AGENTS.md .claude/skills/architecture/SKILL.md | grep -iE "ten|eleven|twelve|nine|thirteen|fourteen|fifteen|[0-9]+ domains"
   ```

3. **Each `domain-<name>` skill** (5b–5c): read against the code; flag every untrue passage. Its interface pointer names
   the right `architecture` interfaces. A mechanism or method removed in Brief 1a/1b goes from the skills too (a deleted
   accessor still listed as a sub-domain interface is the usual case). Files and tests named still exist (tests live
   under `tests/<domain>/`).
4. **Code comments** (5d): the comment rules are `audit`, step 4. Whole-codebase scripts:

   ```bash
   # Undocumented non-lifecycle functions.
   for f in $(find scenes tools -name '*.gd'); do
     awk 'prev !~ /^[[:space:]]*##/ && prev !~ /^[[:space:]]*@/ && $0 ~ /^[[:space:]]*(static )?func / {
       l=$0; sub(/\(.*/,"",l); gsub(/^[[:space:]]*/,"",l); print FILENAME":"NR": "l } { prev=$0 }' "$f"
   done | grep -vE 'func _(ready|process|physics_process|draw|init|input|exit_tree|notification|unhandled_input|enter_tree|integrate_forces)\b'

   # Files with no `##` header in their first lines.
   for f in $(find scenes -name '*.gd'); do head -3 "$f" | grep -q '^##' || echo "$f"; done

   # History / speculation sweep (noisy by design: judge each hit).
   grep -rniE '\b(renamed|moved to|moved from|used to|formerly|previously|no longer|in future|for now|todo|fixme|hack|legacy|deprecated)\b' scenes --include='*.gd'
   ```

## Step 6 — Nothing broke (Phase 4)

Nothing changed: say so and skip. Otherwise behaviour must be identical:

- `godot-run` load check (`--import` first if a `class_name` or script moved or was added) and `tools/lint.sh` (a
  removal can leave an unused variable: fix the code; silencing is a last resort, as in `audit`).
- `tools/run_tests.sh --changed`: a removed dynamically dispatched member fails at runtime, not at parse.
- Touched anything in the 1a dynamic-dispatch list: drive it live (`godot-run`) and confirm it still happens. After a
  hard kill, `pkill -f "von serve"`.
- Rerun `python3 -I tools/audit_scan.py all`: fixed findings gone, no new `deps` edge.

## Output

By section, highest value first; each item `file:line` — problem — fix; `[x]` on sections confirmed clean; splits ranked
with the files that move. Don't manufacture findings or soften real ones.

```
## Codebase cleanup

### Dead code
- [ ] `scenes/character/character.gd:56,156` — `signal item_changed` emitted on every slot switch, nothing connects
      it (the HUD polls `current_item()`). Fix: delete signal + emit; remove it from `architecture`.
- [x] No unreferenced functions or unread declarations (scan corrected per 1a; N funcs scanned).

### Module complexity
- [ ] 1. `physics/` → `physics/blood/` — 12 of 23 files (~1,400 lines) are blood; 3 other files mention it;
      interface unchanged. Moves: `blood_*.gd`. Edits: 4 preloads + docs.

### Documentation
- [ ] `domain-navigation/SKILL.md:NN` — says the furniture-holes overlay is "off by default"; `main.gd`'s
      `show_nav_holes` export is on. Fix: state the real default.

**Verdict:** 2 items to clear; isolation and redundancy clean.
```
