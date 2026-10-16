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
- `decision_stub.gd` (`class_name DecisionStub`) — test seam: scripted picks that stand in for the server.
- `decision_budget.gd` (`class_name DecisionBudget`) — how many decision snapshots may start in one frame, shared by every NPC (below).
- `decision_server_launcher.gd` — dev-only `von serve` launcher (a node in `main.tscn`).

## `decision_tree.gd` — the tree as data

```
root ─┬─ order [order; requires ordered]      → the option's own primitive (defend / entry), auto-picked
      ├─ combat (bind target over `hostiles`) ─┬─ engage  [fire_positions]            → engage
      │                                         ├─ flank   [flank_sides, drop `held`, `crosses`, `no_shot`, `heading`, `lane`] → engage (anchored at the side)
      │                                         ├─ grenade [grenade_throws, drop `ally_in_blast`, `no_safe_spot`] → throw
      │                                         ├─ advance [advance_positions]         → move{aim target}
      │                                         ├─ melee   [melee: point-blank only]   → melee
      │                                         ├─ reload  [reload: gun low + spare] → reload
      │                                         ├─ retreat [retreat_positions]         → move{aim threat, run_through_fire}
      │                                         └─ locate  [shooter]                   → move{aim point}
      ├─ reload_quiet [reload; no threat known, gun low + spare] → reload
      ├─ investigate [leads] (ask)         → move{aim travel}
      │    └─ stay [lead_outside]          → hold          (decline a lead outside the house)
      ├─ search [search_rooms, explore]    → move{aim travel}
      │    ├─ enter [entries]              → entry         (a doorway into a room left to search)
      │    └─ stun_entry [entries; requires stack_has_stun] → entry{bang}  (a doorway into a room where a hostile may be waiting)
      └─ idle ─┬─ use [interactions] → interact · go [rooms] → move · wait → hold
```

Node fields: `label` (path tag), `desc`, `question` (what Von answers when choosing AMONG its
children/options — it names the trade-off), `context` (which perception sections Von sees at that
level; the goal is always shown), `children` (static node ids), `options` (perception option-group
names → leaves; looked up under the bound target first, then globally), `summary` (group whose
summary fills `{summary}`; `summary_inside` within a confined subtree; `{gun}` in a template is what the NPC calls its gun, from the
snapshot's `gun`: "pistol", "assault rifle"; `{blinded}` the bound hostile's "X is blinded by a flash and cannot see you, or " clause, empty unless it is, from the `blinded` key of its `hostiles` bind), `bind` + `bind_options` +
`bind_question` + `bind_context` (pick and bind one option first, e.g. which hostile — with a leaner
state, since the options carry each candidate's details), `requires` (fact names, `!` negates; a bound
name counts as true), `confine` (combat subtree: a territorial NPC drops options outside the house),
`drop_tags` (options carrying these tags are never offered — a flank side an ally holds, one whose
route passes a known hostile, one with no shot at the target, one the target is walking toward, or one
whose point or route lies in an ally's line of fire), `primitive` (move / engage / melee / interact / hold / reload / entry / throw / defend), `params` (defaults merged under each option's own params; `run: true` on flank, advance, retreat and investigate lets the behaviour sprint to the destination — Von never sees it; `run_through_fire: true` on retreat lets it keep sprinting with a shot available (every other walk drops to a walk to take it, `docs/gaze-and-fire.md` W6); `entry_guard: false` on retreat exempts the walk from the behaviour's entry guard, which sends every other walk into an uncleared room through a tactical entry first).
`ask` (INVESTIGATE: the planner never takes the node, or the level that offers it as its lone option, without asking Von — whether a
lead is worth going to is Von's call). **Staying in the house is Von's call too, guided by the prompt, not a rule:** a territorial
goal ("hold your ground inside the house; do not chase anyone outside") is in every state, the state and the leads say where the gunfire
or hostile is ("outside the house"), and the `stay` child of INVESTIGATE (offered while a lead lies outside the house and the NPC is inside:
fact `lead_outside`) is Von's way to decline. Its desc states the situation in the state's own words and echoes the goal's sentence ("You are inside the house and the gunfire is
outside the house: hold your ground, do not chase anyone outside"). Measured with `tools/von_probe.py` (`investigate_outside_lead*`,
`investigate_outside_leads_*`): it wins for a goal that says it, also when shots are landing near the NPC (0.54) and with three leads on offer
(0.44, the leads split the rest), and loses to the lead for an invader's goal (0.57 to 0.69 for the lead; thin, so re-run the invader probe
after any rewording). A wording that does not name the situation ("Hold your ground inside the house; do not chase anyone outside")
loses to the lead under fire (0.35) and makes invaders hold too, and without a decline option Von takes the outside lead (0.66) whatever the state says. Nothing in the tree or the code knows who the NPC is; reword the desc and re-run
the probe and the Von tests (`defender_stays_in_house_von`, `defender_investigates_gunfire_inside_von`,
`invader_investigates_gunfire_outside_von`) together. `defend_territory` still confines COMBAT only.
A node may mix `children` and `options`. `engage` and `flank` require `gun_loaded` (an empty gun is never offered "a clear shot"); `advance`, `melee` and
`retreat` stay available so an empty NPC can still close in, punch or fall back. The `reload` nodes require `weapon_low` +
`can_reload` (the quiet one also `!threat_known`) and have a lone option, so the planner takes them without a Von request when
nothing else is on offer. A node whose option groups end up empty (every flank side
dropped; MELEE while the target isn't point-blank) has no leaf, so it isn't offered at all. Adding a
mode or tactic = adding a node (+ a perception option group if it needs new places).

**ENTER** (`enter`, a child of `search`): the doorways into rooms the NPC has not seen or not searched lately
(`entries`, an invader's only, `entry_enabled`); the desc names the nearest ("A doorway leads into a room left to
search (the doorway to the west — unexplored — short route)") and the question asks for "the shortest route"
(measured: "the nearest one into an unsearched or unexplored room" lets "unexplored" outweigh a short route). Von chooses only whether and which doorway; the stack, pie, crossing and corners are the
behaviour's `entry` primitive (`domain-ai-entry`), which asks Von nothing on the cadence until the entry is over
(a forced decision — a hit, a hostile belief change — still starts, and replaces the entry or, with Von down, aborts it).

**GRENADE** (`grenade`, a COMBAT child; `docs/grenades.md` G17): offered while the group `grenade_throws` has an option (requires `grenade_ready` only, so the unbound level
offers it too: under the bound hostile, the NPC carries a grenade and the hostile's last-known spot is hidden from its line of fire or in a room the NPC is outside of, in throw
range with a clear lob; unbound, with no hostile known, the global group throws where the shots came from, beside RETREAT, LOCATE not being offered toward that room) that is not tagged `ally_in_blast` or `no_safe_spot`; its
desc is "{situation} and you can throw a grenade onto their spot ({summary})", `{situation}` being the group's case ("Your line to X is blocked" / "X holds a room you are outside of" /
"The shots came from a room you are outside of"; the planner's `_fill` takes it from the summary group's `situation`). Measured (`tools/von_scenarios/grenade_*.json`): the doorway
holder GRENADE 0.49 to 0.51 against ENGAGE 0.32 to 0.40 (a desc keeping "Your line ... is blocked" for it: 0.14 against 0.61); the shots' origin GRENADE 0.77 against RETREAT
0.23 (issue #51 R10). Through a throw spot (R13 / R15, the summary "within throwing range from a spot nearby", `grenade_throw_spot_*.json`) the same ranks hold (0.44 / 0.49 / 0.78;
dropping the walk's words moves GRENADE by 0.02 at most), and over 40 levels captured in real matches out of range GRENADE ranks first in 18 against 17 worded in place. Runs the `throw`
primitive (`domain-ai-combat`). Its options are `frag` and `stun` (asked of Von only when it carries both). Measured on the three real-Von scenarios
(`combat_frag_hidden_hostile`, `combat_frag_take_cover`, `combat_stun_then_advance`) with `tools/von_probe.py`: the desc "Your line to {target} is blocked and you can throw a
grenade onto their spot ({summary})" together with the sentence the exposure section gains ("You can throw a frag grenade onto their spot.") gives GRENADE
0.46 to 0.52 against ENGAGE 0.23 to 0.26 (the old plan cue on ENGAGE changes nothing); either half alone leaves ENGAGE ahead (0.35 to 0.43 against GRENADE 0.22 to 0.36: ENGAGE's "clear shot"
wording wins on the loaded-gun facts), and a desc that opens with "{target} is hidden behind cover where a bullet cannot reach" loses. After a stun the state says the hostile is
"blinded by a flash and cannot see you" (the sentence in the exposure section, the `{blinded}` clause in ADVANCE's desc: "{target} is blinded by a flash and cannot see you, or
{target} looks badly wounded, ..."; the planner fills `{blinded}` from the bound hostile's option, empty otherwise, so every other desc is unchanged): ADVANCE 0.71 against ENGAGE 0.18 (0.26
against 0.48 with the state's contact line alone). **STUN ENTRY** (`stun_entry`, a SEARCH child, requires `stack_has_stun`, G18): the same `entries` group and `entry` primitive as
ENTER with `params { bang: true }`; desc "A doorway leads into a room where a hostile was heard, seen, radioed or shooting from ({summary})", the summary being the nearest doorway's (a doorway into a
suspect room is listed first and says why instead of "unexplored"/"unsearched": "gunfire heard there", "footsteps heard there", "shots at you came from there", "an ally radioed a fight there",
"a hostile seen going in", "a hostile lost by its doorway", "a hostile seen heading in"). Measured with `tools/von_probe.py` on `tools/von_scenarios/stun_entry_*.json` (the SEARCH level of an
invader outside): STUN ENTRY first with each reason (0.39 to 0.46 against ENTER 0.33 to 0.37; ablating the phrase hands each back to ENTER, but gunfire heard, which the state's awareness line names too), the quiet ENTER with none (unexplored 0.46 against 0.29,
unsearched 0.45 against 0.25). A desc naming two reasons, "where gunfire was heard or a hostile was seen going in", ties ENTER on an unrelated phrase (0.39 each); one listing every reason by name gives a plain
unsearched room the bang (0.41 against 0.36); "a hostile may be waiting" bangs everything. At the doorway level the unexplored/unsearched word costs the suspect doorway (0.48 against 0.52),
"gunfire heard there" in its place gives 0.61 and "into the room where gunfire was heard" 0.66. Re-run the probes after any rewording of either.

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
`entry_rules` (ordered fact → start node), `skip_single_option`, `inside_only` (territory), `confine_room` (the room a member ordered to
defend it keeps to, `docs/leadership.md` LD8: inside a `confine` subtree an option whose `tags.room` is another room or outside is dropped,
as `inside_only` drops one outside the house; an option naming no place stays; the leaf's params then carry `confine_room`).
**ORDER** (`order`, a root child, `requires: ordered`, LD6): its one option is the snapshot's `order` group, so it is taken without asking Von;
the option names its own `primitive` (`_finish` takes an option's `primitive` over the node's). The controller's entry rules put
`ordered → order` after `under_fire` / `engaged` and before `hostile_known`. A member's live order is shown at every level after the goal
(the `order` section, "" without one). The
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
  target_id + confine_inside) }`. `signal failed()` — transport failure or nothing to
  choose; the controller wires it to the behaviour's `fallback()`.
- `entry_for(facts)` / `current_entry()` — the cheap check the controller uses to interrupt a walk
  in flight when the situation now calls for a different start (e.g. came under fire mid-search).
- `cancel()`, `is_pending()`, `debug_state()` (per level: node, question, state, offered, Von's
  probabilities and pick, `auto`, `ms` — enough to replay offline), `walk_digest()` for the log line.

## `decision_budget.gd` — snapshots spread over frames

Building a snapshot (the perception's `sense()`) is the costliest thing an NPC does in a frame (2-3 ms, up to 8), and NPCs
that spawned or came under fire together want to decide on the same frame. The controller asks `DecisionBudget.claim()`
before `_start_decision` (in `_should_decide`, and before restarting a walk in `_maybe_interrupt`): `per_frame` (1)
snapshots may start in one physics frame. A refused NPC keeps its wish (`_force`, its elapsed timer) and asks again next
frame, so no NPC waits more than a frame per NPC ahead of it. The limit is a count, not a time, so when an NPC decides never
depends on the machine's speed, and two NPCs that would claim the same flank side on one frame decide on different frames,
each hearing the other's radio first. A test raises `per_frame` with `set_static` to see every NPC decide at once
(`tests/ai/decision/decisions_spread_over_frames_test.gd`).

## `decision_client.gd` — the transport

`configure(url, model, timeout)`; `ask(state_text, instructions, options) -> bool` POSTs ONE `choice`
question (`pick`) to `/v1/systemone`; `cancel()`.
- `signal answered(pick, probabilities)` — Von's top pick: the argmax `choice` when it is one of the
  offered ids, else the highest-probability offered id (a stale/foreign id can never be chosen). Von's
  distributions are flat, so taking the top pick — not sampling — keeps the NPC decisive.
- **Test seam:** while `DecisionStub.active`, `ask()` answers from `decision_stub.gd` a frame later, with no
  HTTP request. `DecisionStub.rules` is an ordered `[{ pick, question? }]` (first rule whose id is offered,
  and whose `question` text occurs in the level's question, wins; else the first offered id), `fail` makes
  every ask fail (server down), `latency_frames` (physics frames an answer is held back, like a slow server; the NPC carries on with
  its old order meanwhile; `TestSetup.von_script`'s second argument) and `requests` logs `{ state, question, options, pick }` per ask. Only the
  Testing domain sets these (`TestSetup.von_script` / `von_down`; statics restored after each test).
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
none is coming (`false`: exported build, blank `von_path`, failed spawn, `ready_timeout` elapsed, or a server up that cannot decide).
`main.gd` awaits it before `_spawn_world()` so no NPC ever makes its first decision against a cold
server; a run with no server still starts (with a warning), just with NPCs that hold steady. Main
checks `is_resolved()` *before* awaiting, because the exported-build path resolves synchronously in
`_ready()` — children are readied before their parent, so the signal would otherwise be missed. Any
new terminal path here MUST resolve, or the setup window hangs forever. Output is appended to `user://von_server.log` and echoed as `[von] …` lines.
Every NPC shares the one server (its port must match the clients' `server_url`).

Note: killing a Bash-launched Godot (`godot-run`, step 5) is a hard kill, so `_exit_tree` doesn't run and the Von server it
spawned is orphaned on port 8000 — `pkill -f "von serve"` clears it, and you should always run it after one. An
orphaned server's stdout pipe is dead, so it can never load weights again (`EPIPE` kills the fetch)
while still answering HTTP; the readiness probe above is what stops it being mistaken for a live one.

## Checking Von's decisions offline

`tools/von_probe.py` replays scenario levels (`tools/von_scenarios/*.json`: state, question, options,
expected pick) against the running server and, with `--ablate`, drops one fact at a time to show
which facts actually move the pick. `--capture <gcmd ai dump>` turns live levels into scenario stubs.
