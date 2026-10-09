---
name: domain-ai-decision
description: Deep implementation detail for the AI DECISION sub-domain (scenes/ai/decision/) — the decision tree (broad mode → tactic → option → primitive) as GDScript data, the planner that walks it with Von one `choice` request per level (entry rules, gating, territorial filter, auto-picked single options, continuity cue, per-level state), the single-question Von transport with argmax/top-pick, and the dev-only server launcher. Use when editing scenes/ai/decision/ or working on the decision tree, adding a mode/tactic, entry rules (under fire → combat), what Von is asked at each level, how a pick is chosen, the server-down fallback, or auto-starting/reusing the Von server. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Decision sub-domain (`scenes/ai/decision/`)

The THINK half: the decision POLICY as data, and the only place the AI talks to the outside model. Von
is a stateless single-shot ranker that scores every question independently (one encoder pass each, no
conditioning between questions in a request), so a drill-down is **sequential requests, one per
level**, each conditioned on the path chosen so far. The knowledge a walk decides over is BUILT by the
perception sub-domain (the snapshot); the chosen leaf is RUN by the behaviour sub-domain.

Files:
- `decision_tree.gd` — the tree, `const NODES` (data only).
- `decision_planner.gd` — the walk (a `Node`): gating, entry rules, per-level state, Von calls.
- `decision_client.gd` — the Von HTTP transport (a `Node` owning its `HTTPRequest`).
- `decision_server_launcher.gd` — dev-only `von serve` launcher (a node in `main.tscn`).

## `decision_tree.gd` — the tree as data

```
root ─┬─ combat (bind target over `hostiles`) ─┬─ engage  [fire_positions]            → engage
      │                                         ├─ flank   [flank_sides, drop `held`, `crosses`] → engage (anchored at the side)
      │                                         ├─ advance [advance_positions]         → move{aim target, fire_at_will}
      │                                         ├─ melee   [melee: point-blank only]   → melee
      │                                         ├─ retreat [retreat_positions]         → move{aim threat, fire_at_will}
      │                                         └─ locate  [shooter]                   → move{aim point, fire_at_will}
      ├─ investigate [leads]               → move{aim travel, fire_at_will}
      ├─ search [search_rooms, explore]    → move{aim travel, fire_at_will}
      └─ idle ─┬─ use [interactions] → interact · go [rooms] → move · wait → hold
```

Node fields: `label` (path tag), `desc`, `question` (what Von answers when choosing AMONG its
children/options — it names the trade-off), `context` (which perception sections Von sees at that
level; the goal is always shown), `children` (static node ids), `options` (perception option-group
names → leaves; looked up under the bound target first, then globally), `summary` (group whose
summary fills `{summary}`; `summary_inside` within a confined subtree), `bind` + `bind_options` +
`bind_question` + `bind_context` (pick and bind one option first, e.g. which hostile — with a leaner
state, since the options carry each candidate's details), `requires` (fact names, `!` negates; a bound
name counts as true), `confine` (combat subtree: a territorial NPC drops options outside the house),
`drop_tags` (options carrying these tags are never offered — a flank side an ally holds, or one whose
route passes a known hostile), `primitive`, `params` (defaults merged under each option's own params).
A node may mix `children` and `options`. A node whose option groups end up empty (every flank side
dropped; MELEE while the target isn't point-blank) has no leaf, so it isn't offered at all. Adding a
mode or tactic = adding a node (+ a perception option group if it needs new places).

**How a `desc` must read.** Von is a CLASSIFIER — it picks the option whose text best matches the
state (`criteria` in its API are classification criteria). A branch's desc therefore states the
SITUATION in which it is right, in the phrases perception writes into the state, plus specifics in
parentheses: ENGAGE "You have a clear shot at {target}, and you are not badly wounded ({summary})",
RETREAT "You are badly wounded and being hit ({summary})", ADVANCE "{target} looks badly wounded, is
unarmed, or is moving away from you ({summary})". No action labels (they pull toward the goal's
verbs), no negated attributes, no option repeating a dominated choice (drop it instead). These
phrasings were chosen by measurement with `tools/von_probe.py` — re-run it after rewording.

## `decision_planner.gd` — the walk

Config (pushed in from the controller): `disabled_nodes`, `node_overrides` (per-node field merge),
`entry_rules` (ordered fact → start node), `skip_single_option`, `inside_only` (territory). The
controller maps `pursue_hostiles` → `idle` disabled + `hostile_known → combat`; `defend_territory` →
`inside_only`. All but `node_overrides` are re-pushed each decision, so retuning them at runtime takes
effect; `node_overrides` is baked into the tree at `setup()` and is construction-time only.

- `begin(snapshot, continuing)` — starts a walk (abandoning any in flight) at the first entry rule
  whose fact holds and whose node has a leaf, else `root`. Per level: list what's on offer (bind
  options, or gated children whose subtree still holds a leaf, plus the node's option groups through
  the territorial + `drop_tags` filters); when `continuing` (the behaviour's last choice is still in
  progress) mark the option continuing it "(your current plan)" — never a finished one, or Von
  re-picks a completed tactic (a flank it already reached); take a lone option without asking; else
  `client.ask(state, question, criteria)` where state = the goal + the node's `context` sections (the
  bound target's own version first) + "Decided so far: COMBAT → Intruder → FLANK.". A bind level with
  nothing to bind (under fire, shooter unseen) falls through to the node's unbound children (RETREAT
  / LOCATE). An empty entry node falls back to `root`; an empty root fails.
- `signal decided(leaf)` — `{ path (ids), labels, primitive, params (node params ⊕ option params +
  target_id + confine_inside), desc, entry }`. `signal failed()` — transport failure or nothing to
  choose; the controller wires it to the behaviour's `fallback()`.
- `entry_for(facts)` / `current_entry()` — the cheap check the controller uses to interrupt a walk
  in flight when the situation now calls for a different start (e.g. came under fire mid-search).
- `cancel()`, `is_pending()`, `debug_state()` (per level: node, question, state, offered, Von's
  probabilities and pick, `auto`, `ms` — enough to replay offline), `walk_digest()` for the log line.

## `decision_client.gd` — the transport

`configure(url, model, timeout)`; `ask(state_text, instructions, options) -> bool` POSTs ONE `choice`
question (`pick`) to `/v1/systemone`; `cancel()`; `is_pending()`.
- `signal answered(pick, probabilities)` — Von's top pick: the argmax `choice` when it is one of the
  offered ids, else the highest-probability offered id (a stale/foreign id can never be chosen). Von's
  distributions are flat, so taking the top pick — not sampling — keeps the NPC decisive.
- `signal failed()` — request couldn't start, transport failure, non-200, malformed or no offered id.
  **A transport failure and an HTTP error answer are reported as different faults**: a 4xx/5xx prints
  the server's own `{"detail": …}`, never "unreachable". An identical failure is logged only ONCE per
  client; a success clears that. The adopted decision log line (`<NPC> (Von) COMBAT - Intruder -
  FLANK - their left side (kitchen)  [combat auto, combat 112ms, flank 96ms]`) is the controller's.

## `decision_server_launcher.gd`

Development convenience: starts a local `von serve` when the game runs **from the editor** (never in
exported builds) and stops it on exit. Uses `von_path` (defaults to the `application/von/server_path`
project setting; blank = don't auto-start). A server that can still **decide** on `port` is **reused**
and left running, decided by probing `port` up to `probe_attempts` times.

**It is a root node of `main.tscn`, so all of this runs at SCENE LOAD** — while the pre-game setup
window is still open, giving the server its whole boot time before the match builds any NPC. Two
things keep that head start honest:
- A probe that is **refused** (nothing bound) short-circuits the retry budget and launches at once;
  the retries only pay off for a probe that **times out** (a slow server worth reusing). Otherwise a
  cold start wasted `probe_attempts × probe_interval` before even launching.
- The probe **POSTs a real decision** to `health_path` (`/v1/systemone`) rather than checking
  `GET /`, because an **orphaned server is worse than an absent one**. A `von serve` left by a
  hard-killed run (no `_exit_tree`) has a dead stdout pipe, so its weight fetch dies on `EPIPE`
  — permanently — while it keeps serving HTTP. A liveness check reuses it forever and every decision
  comes back `422`; asking it to decide catches it and resolves `false` with the server's own
  `detail`. Clear one by hand with `pkill -f "von serve"`. The probe doubles as a **warm-up**, so the
  first in-match decision isn't the one paying for model load.
- After launching, it keeps polling its own server until the first answer, then prints
  `[von] Decision server live on port N, Xs after scene load` — so readiness means a LIVE brain, not
  merely a spawned process.

**`resolved(live)` + `is_resolved()`** is the gate contract (the live/not-live answer rides the
`resolved` signal). It fires EXACTLY once when
the question settles, and every terminal path reaches `_resolve()` — server answered (`true`), or
none is coming (`false`: exported build, blank `von_path`, failed spawn, `ready_timeout` elapsed).
`main.gd` awaits it before `_spawn_world()` so no NPC ever makes its first decision against a cold
server; a run with no server still starts (with a warning), just with NPCs that hold steady. Main
checks `is_resolved()` *before* awaiting, because the exported-build path resolves synchronously in
`_ready()` — children are readied before their parent, so the signal would otherwise be missed. Any
new terminal path here MUST resolve, or the setup window hangs forever. Output is appended to `user://von_server.log` and echoed as `[von] …` lines.
Every NPC shares the one server (its port must match the clients' `server_url`).

Note: `mcp__godot__stop_project` hard-kills Godot, so `_exit_tree` doesn't run and the Von server it
spawned is orphaned on port 8000 — `pkill -f "von serve"` clears it, and you should always do so. An
orphaned server's stdout pipe is dead, so it can never load weights again (`EPIPE` kills the fetch)
while still answering HTTP; the readiness probe above is what stops it being mistaken for a live one.

## Checking Von's decisions offline

`tools/von_probe.py` replays scenario levels (`tools/von_scenarios/*.json`: state, question, options,
expected pick) against the running server and, with `--ablate`, drops one fact at a time to show
which facts actually move the pick. `--capture <gcmd ai dump>` turns live levels into scenario stubs.
