---
name: domain-ai-behavior
description: Deep implementation detail for the AI BEHAVIOUR sub-domain (scenes/ai/behavior/) — running the decision planner's leaf as one primitive (move / engage / melee / interact / hold / reload / entry) and the System-Two state Von lacks: the tactical entry phase machine (entry.gd: stack, slice the pie, cross, corners, clear, rear security, over the team radio), engagement + retargeting, territorial confinement, posture and run policy, commitment (when a running choice re-decides), the full-path debug label, and the locomotion layer (nav pathing, room queries, furniture bulldozing). The fighting itself is `domain-ai-combat` (combat.gd), room search by sight is `domain-ai-coverage` (search_coverage.gd) and where it looks and when it takes the shot is `domain-ai-watch` (watch.gd). Use when editing scenes/ai/behavior/ (behavior.gd, entry.gd, locomotion.gd) or working on how a chosen option becomes movement, holding ground, commitment/dwell timers, or pathing. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Behaviour sub-domain (`scenes/ai/behavior/`)

The ACT half: it runs the LEAF the decision planner chose — one primitive with its params — as
concrete movement + actions, and holds the System-Two state Von (a stateless ranker) lacks. It never
chooses WHAT to do and applies no policy beyond its params. It reads the world only through the
perception sub-domain and drives the character only through its public controller contract
(`move_input`/`aim_point`, `select_slot`, `shoot`, `melee`, `interact_with`, `end_interaction`).

Files:
- `behavior.gd` — the primitive executor (a `Node`); owns engagement + commitment state, posture / run policy and the read-outs.
- `combat.gd` — shots, kicks, punches, bursts, back-off, the peek-and-cover cycle (`RefCounted`; `domain-ai-combat`).
- `search_coverage.gd` — covering a room by sight (`RefCounted`; `domain-ai-coverage`).
- `watch.gd` + the watch stage of `behavior.gd` — where it looks and when it takes the shot, in every primitive (`RefCounted`; `domain-ai-watch`, spec `docs/gaze-and-fire.md`).
- `entry.gd` — a tactical entry through a doorway, as a team member or alone (`RefCounted`; see "Tactical entry" below).
- `locomotion.gd` — the pathing layer (a `Node` child of behaviour); owns the NavigationAgent2D and answers `room_key_at(p)` / `inside_house(p)`.

The controller sets the behaviour's config fields from its exports, calls `setup(perception, nav_agent)`
once to build its `Locomotion`, `SearchCoverage`, `Combat`, `Watch` and `Entry` modules, then `apply_config()` to push the tunables they hold
in — re-calling `apply_config()` each decision so a runtime retune takes effect. (The behaviour's own
fields are read live, so only those modules need the push.)

## The primitives (a leaf = `{ path, labels, primitive, params }`)

| Primitive | Params | What it does | Done / re-decides |
|---|---|---|---|
| `move` | `point`, `aim` (travel / target / threat / point), `target_id`, `arrive_room`, `look_around` | Path to the point (or until ENTERING `arrive_room`), aiming as asked (a threat in sight takes the eyes and the gun: the watch stage, below). Stops on arrival (`move_input` is zeroed every tick after it, so the NPC stands still while the next decision is on its way: a real Von answer takes a moment, and from a point near the front door the last heading is out of the house; tests `tests/ai/movement/move_stops_on_arrival_test.gd`, `gaze_arrival_stops`). A `look_around` move (search / explore) walks all the way INTO the room, then **covers it by sight** (`search_coverage.gd`, the `domain-ai-coverage` skill) until it has SEEN the room or its budget runs out. ADVANCE is a `move` with `aim: target`: it closes in, then re-decides how to fight. | On arrival (forces a decision) — a `look_around` move only once the room is covered or its budget runs out (`max_commit_time` still caps the walk INTO the room before coverage starts). |
| `engage` | `point` (anchor), `target_id`, `style` (peek_cover / ambush), `confine_inside` | Path to the anchor firing at will, then fight from it: **peek-and-cover** (peek to the nearest spot with a clear shot, fire on `fire_cooldown`, duck to cover for `cover_time`, positions committed for `reposition_interval`) or **ambush** (hold the covered spot, fire the moment a line opens). ENGAGE and FLANK use this, anchored at the chosen spot or side. | Moving: at `max_commit_time`. In position: every `tactic_interval` (timer starts on arrival) or when `engaged` lapses. |
| `melee` | `target_id`, `confine_inside` | Close to `punch_range` and strike (a kick with a gun in hand, else a punch). | `tactic_interval` / `engaged` lapse. |
| `interact` | `object`, `id` | Walk to the object, face it, run the interaction, hold it `interaction_dwell`. | Dwell over (forces a decision), or approach cap. |
| `reload` | — | Equip the gun (`gun_slot()`), stand still (its eyes where the watch stage puts them) and `Character.reload()`; ends when the reload does (or at once if it can't start). | The reload ending (forces a decision), or `max_commit_time`. |
| `entry` | `opening`, `into`, `slot`, `side` (from the ENTER option) | A tactical entry through the doorway (`entry.gd`, below): approach and stack, slice the pie, cross, take a corner, clear the room, maybe hold the door. Shoots a threat in sight in every phase (the watch stage). | When the entry is over (room clear, rear watch done, or given up); never on the cadence. The entry guard (below) also runs it, as a detour in the middle of another order. |
| `throw` | `point` (the spot), `kind` (`frag` / `stun`), `radius`, `slot`, `target_id` | The GRENADE tactic (`docs/grenades.md` G17; `combat.gd` does the throwing, `domain-ai-combat`): take the grenade in hand, turn to the spot (closing the last px if it drifted out of range since the offer), throw (the line is re-checked until the wind-up begins and the throw dropped if it is blocked; from the wind-up on it is committed), radio `frag_out` / `bang_out` as it leaves the hand (`take_throw_calls`), gun back in hand, then stand out the fuse (the watch stage shoots from there). An evade plan (the thrower in its own burst's zone) replaces the order at the release tick; `poll_throw` runs before it so the call is radioed first. Committed (no re-decision) during the wind-up. | When the grenade has gone off (or the throw could not be made, or the fuse plus a second ran out). |
| `hold` | — | Stand; the watch stage looks at the threat (and shoots it) or turns among the room's doorways. | Decide cadence. |

**Gaze and fire** are a policy too, the **watch stage** (`Behavior._apply_watch`, `watch.gd`; the `domain-ai-watch` skill, spec `docs/gaze-and-fire.md`):
after the primitive steers, a threat in sight (or one seen a moment ago with a clear line) takes the NPC's eyes and gun whatever the primitive
is (a move, a hold, a reload, an engage still walking, a throw once the grenade is away, any entry phase but `bang`; not a melee, an
arrived engage, an interaction, a throw still taking the grenade in hand and throwing it, or an entry's `bang`); no primitive
or entry phase has its own fire call. With no threat a walker looks down its path (`Watch.travel_point`) and a resting NPC (hold / reload /
an arrived move) turns among its room's doorways. An arrived move zeroes `move_input`. Tests: `tests/ai/gaze/`,
`entry_guard_fires_from_outside`, `fire_dry_gun_on_move_reloads`, `engaged_retargets_to_visible`.

**Territory** is a param, not a policy: with `confine_inside` (set by the planner for a territorial
NPC's combat leaves) and a contact last seen outside, `Behavior` sets `hold_ground`, which `Combat` honours (see `domain-ai-combat`).

**Running** is a behaviour policy, not a primitive: after the primitive steers and the watch stage has picked its threat, `_should_run()` sets
`character.run_input` only while TRAVELLING (a `move` or `engage` not yet arrived — never a `look_around`
search, ambush/peek, interaction, hold or tactical entry — or a `melee` closing in), when the leaf carries `run: true` or
the NPC is under fire, the destination is farther than `run_min_distance` (straight line), and a run can
start (`run_start_fraction` of the stamina bar, or already running). The Character spends the stamina and
walks once dry. Exports on the controller: `run_enabled`, `run_min_distance`, `run_start_fraction`.
`debug_status()` reads "running" / "running into position" while it sprints; `debug_state()` has `running`.
A running NPC cannot shoot or reload (`Character.shoot()` is ignored while running), so `_should_run` is false while a shot is available
(`Combat.can_fire_at(threat)`: loaded, in range, clear line) or the reload reflex is due (`Combat.reload_due`): it drops to a walk and
takes the shot instead of sprinting on past its range. A leaf with `run_through_fire` (the RETREAT node) keeps sprinting. `Combat.shoot()`
still skips a shot while `is_running()` without spending the fire cooldown.
Tests: `tests/ai/movement/ai_runs_to_destination_test.gd`, `retreat_keeps_running_test.gd`.

**Posture** is a behaviour policy too (spec: `docs/cover-and-stance.md`, A1 to A3): after the primitive has steered and `run_input` is set,
`_apply_posture` writes the posture `_wanted_posture` asks for through `Character.set_posture` (idempotent, so every tick). Everything outside a
fight and everything travelling to a destination (`move`, an `engage` not yet arrived, `melee`, `interact`) **stands** — only a standing body runs —
and so does an NPC that is running. Fighting in place (`engage` arrived, or `hold` / `reload` with a hostile known or shots landing) it **crouches** (behind cover, in the open or
pinned alike, and when moving about inside the fight). A crouch is held `posture_dwell` (0.7 s) before it is dropped; standing back up is never delayed.
Exports on the controller: `posture_enabled` (the `ai.posture` switch), `posture_dwell`. `debug_status()` appends "crouching";
`debug_state()` has `posture`. Not a decision-tree level: Von is never asked, so it works with the server down. Tests:
`tests/ai/posture/posture_crouches_in_fight_test.gd`, `posture_pinned_crouch_test.gd`, `posture_stands_to_run_test.gd`.

**Combat** — the gunnery, the peek-and-cover cycle, bursts, backing off a blocked barrel, the reload reflex, melee and the
no-per-weapon-code rule — is `combat.gd`: the **`domain-ai-combat`** skill. `Behavior` passes it the engaged contact and `hold_ground`.

## The evade reflex (G16) and the blind NPC (G15)

**Evade (`Behavior.set_evade(plan)`, called every tick by the orchestrator with the perception's `evade_plan`; `docs/grenades.md` G16).** Outside Von and over every primitive, like the
auto-reload: while a live grenade threatens the NPC it is carried out instead of the running order, an entry (committed or not) and an interaction included. The first
tick of a plan drops the detour, abandons the entry (the stack is told), and replaces the order with `evade` (path `["evade"]`, labels `EVADE - a live frag grenade`);
no decision is started or adopted while it runs (the controller's `_should_decide` / `_on_decided`, `set_leaf`). `_apply_evade` runs to `plan.spot` (`Locomotion.move_to`, looking where it
goes, running when `run_enabled` and stamina allow), then holds it facing away from the grenade, **crouched when the spot is cover** (`plan.crouch`); the watch stage does not run (no
turning to a threat, no shot). With no spot in time it stays, facing away (a stun then blinds it for the back-turned share only), crouched for a frag. When the plan ends (the burst) `_resolved` forces
a new decision. Read-outs: `evading()`, `evade_spot()` (the controller's `debug_grenades().escape`), `debug_state()["evade"]`. Tests: `tests/ai/grenade/evade_*`.

**A blinded NPC** (`Character.is_blind()`): the orchestrator starts no new decision (`_should_decide`) and re-decides the tick its sight returns; the order it was carrying out goes on
(it stumbles: the character is slowed and drifts); the perception keeps its contacts (so the watch stage's engaged-contact pick, or the arrived peek-and-cover, fires at the hostile's last-known
spot with the character's aim sway, G13) and sees no new one. A deafened NPC hears no gunfire, no hit elsewhere and no callout (the orchestrator drops them).

## Tactical entry (`entry.gd`)

The spec and the tests are `docs/tactical-entry.md` (E1 to E15) and `tests/ai/entry/`. `Behavior` adopts an
ENTER leaf, starts the entry on the next tick (`begin(character, params)`: it reads the doorway's geometry and the team
off the perception, `entry_geometry` / `entry_team`) and then calls `step()` each tick until it reports done. Phases:
`approach` (to its stack slot: if on the wrong side of the door, out from the wall and across far out first; then to a
point past the slot and along the wall into it, so it never walks the door's axis close in), `stack` (in the slot facing
the door; radios `ready`), `pie` (the point — the lowest slot still waiting — walks the pie arc, at each step turning its
gaze through the door until it settles plus `entry_pie_dwell`, dropping room sample points (`SearchCoverage.sample_room`)
and corners it sees: `seen_fraction`, hidden corners; alone it then crosses in front, far out, and slices the other
side), `cross` (radios `going_in`; walks to its corner without stopping; `in` once past the wall plane and off the axis),
`corner` (holds it `entry_corner_dwell` looking across the room), `clear` (`SearchCoverage.begin/step`; radios `clear`
with `cleared_room` once the rest of the stack is in), `cover` (the room is held, guns on the doorways on, below), `rear`
(a member left over holds just inside the door it came by, facing out).

- **Holding the cleared room (E8).** `_finish` marks the room cleared, then reads the doorways on out of it into rooms not
  cleared (`entry_watch_doors(into, opening)`, outside doors and the door it came by left out) with a cover spot each:
  `COVER_DEPTH` back inside the cleared room, off the doorway's axis on the NPC's side, the gun aimed through it. With a
  team, each member claims the nearest doorway no teammate's `cover` call names (kept once its own; a tie goes to the lower
  instance id) and radios `cover` with `covering`; one left over (or, with no doorway on, the last one in) goes to `rear`,
  anyone else is done. Each member on the rear has a spot of its own (`_hold_rear_or_done`: by slot, the members take turns either
  side of the doorway just inside it, each pair `SPOT_SPACING` (44 px) further along the wall), so two never share one. The hold ends when a teammate seen holding (`cover` / `rear`) is no longer (it radioed `done`,
  `abort`, or claims another doorway), or after `entry_cover_time` (cover) / `rear_security_time` (rear); a member that
  held radios `done`. Alone, it turns its gaze through each doorway on in turn, `entry_watch_dwell` once settled, then is
  done. The heartbeat repeats the latest call whole, so `covering` and `cleared_room` stay on the radio.

- **The bang (E17, `docs/grenades.md` G18).** An ENTER or STUN ENTRY leaf with `bang: true` (and a stack that follows the first claimer's mode: every claim carries `bang` and the `stuns` the member carries; one
  `bang: false` makes the whole stack quiet) adds the `bang` phase between `stack` and `cross`. `_thrower(team)` picks the second of the stack if it carries a stun, else the lowest slot that does, from the claims, the same on every member;
  `_bang_due` (in `stack`, or in `approach` once the rest are ready) has the thrower plan the throw (`_plan_bang`: a target `BANG_DEPTHS` of the way into the room, on the doorway's axis first, and a spot, its own slot or
  `BANG_STEP_ALONG` in front of the door, `BANG_STEP_OUT` out from the wall, from which the lob is clear of the jamb with its hand `BANG_HAND_REACH` to its right and `BANG_EDGE_MARGIN` to spare: none = the bang is given up and the stack
  goes in quietly), radio `bang`, and every member that sees the call enters `bang`. In `bang`, the thrower walks out from its slot (clear of the member ahead of it) to the spot, throws through `Combat.begin_throw` / `throw_step` /
  `throw_released`, and walks back; everyone holds its slot turned away from the door (`_look_toward` away along the door's normal; the watch stage does not turn it to a threat in `bang`). On the stun's burst in the room (`AgentPerception.last_burst`)
  the stack is over the bang (`_bang_over`): the point crosses at once, no pie, and E14's hold on a hostile in view does not apply for `BANG_WINDOW` s; no top-off is waited for. A call not answered by a burst within `BANG_BURST_CAP`
  or never made within `BANG_CALL_CAP` gives the bang up, and so does a teammate's claim that says quiet (`bang` false: its thrower had no lob or lost its stun): a member in `stack` or in `bang`
  follows it at once, its own claims saying quiet too. Tests: `tests/ai/grenade/bang_fallback_*`. `Entry.expects_burst(kind)` makes `Behavior.set_evade` leave the stack to this hold while a stun is in the air; `committed()` is also true during the thrower's wind-up.
- **Top off at the stack (E11).** A member short of a full magazine with a spare swaps it in while `stack`ed, the one lull:
  `_topping_off` (entry.gd) calls `Combat.top_off` (a tactical reload: `select_slot(gun_slot())`, `reload()`) from `_tick_stack`
  before the point starts the pie or a follower crosses, and from `_tick_pie` before the point crosses (a pie that fired),
  standing still and waiting for the reload to end. Skipped while a hostile holds the entrant's eyes (`gaze_held`: it fires) and
  past `TOP_OFF_CAP` (8 s) per entry; never in `cross` (the watch stage's empty-gun reflex is off while committed too).
- **The last man faces back (E12).** In `stack` a member that is the last slot of a stack of three or more (`_covers_rear`:
  two or more others on the radio, every one with a lower slot) looks along the wall away from the door (`spot + along * side * 300`,
  at 3x `look_rate`) instead of at it, until the member ahead of it is through (`_turn_at`); then it looks at the door as every
  follower does. A threat in sight takes the eyes first (the watch stage).
- **A short room takes two (E13).** The doorway geometry's `capacity` (perception, below) is 2 for a room with a side under
  `entry_short_room` (150 px). A member with that many claiming lower slots ahead of it (`_holds_outside`) stays in `stack` running `_tick_security`: still,
  facing back (E12), until the room is called clear by the team and a teammate that held it moves on (`_team_moved`) or
  `rear_time` has run out since, then radios `done`. It never crosses. Not held back once nobody ahead of it is on the radio and
  the room is not called clear (it takes the lead); gives up (`abort`) after `SECURITY_CAP` (30 s) with no clear call.
- **No crossing on a hostile in view (E14).** `Behavior._apply_entry` hands the entry `hostile_in_view` (`_hostile_in_view`: the watch
  stage's threat is seen now, or was within `watch_lost_gaze`, and `Combat.has_line_of_fire` holds: in range on a clear line, so it
  can be engaged from outside; a hostile seen over low cover with no line of fire holds nothing). While it is set the pie holds where it stands
  (no next step, no crossing; the watch stage fires), a follower does not cross after the member ahead, and nothing else changes: it
  crosses once the hostile is out of view. Whatever order brought the NPC to the doorway (ENTER, or a COMBAT advance / engage the
  entry guard sent through an entry) meets the same rule, because it is the entry's, not the order's. An NPC under fire still drops
  a detour and walks in (the guard's exemption).
- **Barrier and order.** The point crosses when every other claimant has radioed past `claim`, or `entry_ready_timeout`
  after it was ready (restarted when the stack grows). A follower crosses `entry_follow_gap` after the member ahead of
  it radioed `in`. A member still at `claim` once the one behind has waited the timeout is dropped from the order.
- **Corners.** Point: the door-wall corner on its own side (buttonhook); alone, the door-wall corner on the side away
  from where it ended the pie. Second: the hard corner on the other side. Later members: a spot inside off the axis, `SPOT_SPACING`
  apart.
- **Bodies on the way.** Every phase walks through `Locomotion.move_to`, so a member goes round a teammate at rest, stops short of
  one on its slot or spot and takes a free spot beside it (an approach waypoint counts as reached there too, `_loco.reached`), and gives
  way to a walking one. The crossing never stands in the funnel except while `Locomotion.holding()` (a body in its way). A walk a body
  seals and stays in re-plans (`Entry.way_blocked`, called by `Behavior._way_blocked` on `Locomotion.take_blocked`): the approach goes
  on to its next waypoint; with none left a member the stack keeps from its slot takes the back of the stack (`_to_back`: the slot
  behind the last claimed, radioed as a new claim; E2 goes by arrival), and with no slot to take gives the claim up (`abort`; `Behavior`
  re-decides with `resolve_reason()` "way blocked", or a detour hands the walk back to its order); a pie step is skipped; the thrower
  gives the bang up; a crossing waits out the first signal (the one ahead moves on into the room), then gives the entry up if still
  outside the wall plane, or takes its corner where it stands once through; a corner, cover or rear spot is held where it stands and
  the room is covered from there. An entrant walks all the way into its corner (`CORNER_REACH` 6 px): in a small room a corner
  a stride short sits in the doorway of the one crossing behind it. E13's capacity counts a member's place in the stack (how many
  claim a lower slot), not its slot's number, since a member that took the back leaves its old slot empty. A member back in `stack` stands where it was held (its place). Tests: `entry_held_walk_replans`,
  `stack_ai_goes_round_player_in_slot`.
- **Commitment.** `committed()` is true while crossing; the controller starts no decision then (a forced one waits),
  so a hit or a hostile seen in the doorway is fought once the NPC is through. Posture stands throughout, and it never
  runs, not even under fire: a running character cannot shoot, so a sprint to the stack or through the doorway would
  be a lowered gun at the worst moment (test `entry_never_runs`).
- **The radio.** Steps are queued (`take_calls()`, via `Behavior.take_entry_calls()`, which adds `opening`, `into`, `slot` and `side`) and the controller posts them;
  a human invader's `PlayerStack` (`ai/team/`, `domain-ai`) posts the same steps for the human, so the team counts it like an ally;
  the latest is repeated every 2 s so the claim stays live. Choosing anything else `abandon()`s the entry (radios
  `abort`). Each phase change is a `GameLog` line (`--verbose` in tests).
- **The entry guard (E9).** Entry is not only for an ENTER order: `Behavior._entry_guard()` runs every tick after the
  running primitive steered (a `move` not yet arrived, an `engage` and its repositions, an `interact` walk) and reads the walk the
  nav agent was just given (`Locomotion.path_ahead()`), not the order's destination. When the perception's `threshold_ahead()`
  finds a doorway on that walk into a room that is not cleared, within `entry_guard_range` (300 px of walking), it starts a
  **detour**: the order is stashed whole in `_resume`, `_primitive` becomes `entry` for that doorway (`_params` = opening +
  room; slot and side come from the radio as usual), and when the entry ends `_finish_entry()` puts the order back and refills
  its commit timer; the walk carries on from where the entry left the NPC, and meets the next uncleared doorway the same way.
  The labels and path of the order stay, so the status line still says what the NPC is after, with the entry's phase as progress.
  Exempt: `entry_guard` off, no `entry_enabled`, an NPC under fire, a leaf whose params say `entry_guard: false` (RETREAT), a
  `move` that has arrived, and a doorway whose entry was given up less than `entry_guard_rearm` s ago (`_guard_off`, on the
  guard's own clock). A new decision while a detour runs (`set_leaf`) replaces the paused order and leaves the entry
  running, unless it is one the guard does not apply to (`_guards(leaf)`: not a walk, a retreat, or under fire): then the
  detour is dropped and the entry abandoned (`abort` on the radio). Coming under fire before the crossing cancels the detour
  the same way (`_cancel_detour`); a crossing already under way is finished. A decision that was in flight when the NPC became
  committed to its own ENTER crossing is ignored (`set_leaf` returns) and the entry's end re-decides. `fallback()` (no decision to
  be had) abandons any entry. Tests: `tests/ai/entry/entry_guard_*_test.gd`, `entry_fallback_aborts`,
  `entry_decision_in_flight_during_cross`.
- **Doorways passed in a corridor (E15).** The same guard also looks for a doorway the walk goes **past** (`Perception.passing_ahead`:
  between two rooms of the house, into a room not cleared, the walk crosses its axis within 150 px of the wall and never enters it)
  nearer than any doorway it crosses, via `_passing_gate`, skipping one a teammate is working or that was just secured or given up.
  The detour is an `entry` with `secure: true`: `entry.gd` takes no team and radios nothing, stacks beside the jamb, slices one side of
  the pie (the watch stage fires at what it sees, E14 holds it on a hostile in view) and ends `secured` without crossing; `_finish_entry`
  then leaves the doorway alone for `entry_secure_time` (30 s, controller export). An ENTER order's own approach walk is guarded the same way
  (`_guard_approach`: the entry is abandoned, the doorway secured, the order restarts from `approach`), but not for a member heading for a
  stack others have claimed (`entry_team(opening)` is not empty): the team goes to its door as one. `_stash_order` keeps `entry_pending`
  so a paused ENTER starts afresh. Tests: `entry_guard_secures_passed_doorway` (scripted), `entry_corridor_doors_not_passed` (real Von).
- **Read-outs.** `Behavior.debug_entry()` (opening, into, slot, side, solo, secure, phase, seen_fraction, pie_sides, covering, watch_doors,
  hidden_corners, corner, stack_point, team), also under `entry` in `debug_state()`;
  `Behavior.debug_entry_view(character)` (world-space: entry.gd `debug_view` — doorway frame, slots, pie arc and queue,
  corners with what the pie saw, role, waypoints, gaze, timers, the team off the radio, the doorways covered — plus the
  entry guard's detour, rearm list, look-ahead and the cleared rooms) for the entry debug overlays; the status line says the phase
  ("stacked at the door", "slicing the pie", "going in" ...).

## Public interface (what the orchestrator calls)

- `setup(perception, nav_agent)` (build the Locomotion, coverage, combat, watch and entry modules), `apply_config()` (push their tunables
  in; re-callable each decision); config fields; `rooms` (set each tick; forwarded to Locomotion).
- `set_leaf(leaf)` — adopt: snap the point onto the navmesh, capture the target (a fight whose target
  is no longer known drops to hold and forces a re-decision), commit.
- `update_known(known, delta) -> bool` — adopt the perception's hostiles; retarget a lost engaged
  contact to the nearest other; with none left, a leaf that needs a target ends → true (re-decide).
- `salient_key()`, `service_interaction(character, delta, force)`, `take_resolved()` (with `resolve_reason()`, read just before it:
  "way blocked" when a body seals the only way of the walk and stays, "" for a finished task; the controller forces its decision with it),
  `wants_decision(decide_timer_elapsed)` (the table's last column), `apply(character, delta)`,
  `fallback()` (steady hold when no decision can be had), `committed()` (crossing a doorway: no decision may
  start), `take_entry_calls()` (entry steps for the controller to radio), `debug_entry()`, `debug_entry_view(character)`,
  `debug_combat(character)`, `debug_coverage()`, `debug_progress()`, `intent()`, `path_label()`.
- `reached_lead()` — the investigation lead (`params.lead`) the running move has reached, which the
  controller hands to perception's `check_lead()` so it isn't offered again.
- `ongoing()` — the running choice is still in progress (en route, fighting, using an object): only
  then does the planner mark the option continuing it "(your current plan)" — a finished move must
  not be re-picked just because it was the last plan.
- Read-only: `current_act()` (path ids), `in_combat()`, `debug_status()`
  — **the full decision path, every level, joined with " - "** (`COMBAT - Intruder - FLANK - their
  left side (kitchen)  · in position, looking for a shot  ⚠ under fire`), `activity_text()` (the same
  path + progress + how long, for Von's "current activity" line), `debug_state()` (JSON-safe).

## Locomotion (`locomotion.gd`)

All movement flows through `move_to(character, dest, within := 0)` on a `NavigationAgent2D` (`within`: arrive closer than the agent's
own 16 px; the entry's stack slots use `SLOT_REACH` 6 px, since a member a stride short of its slot stands on the next one). `path_ahead()` returns the walk it was just given
(`{ path, index }`, or {}), which the behaviour's entry guard reads. The Navigation
domain bakes furniture in as navmesh holes and rings the house with a walkable outdoor strip.
Steering always aims at `get_next_path_position()` — a navmesh waypoint, so it is wall-safe, and for
an unreachable target it steps toward the closest reachable point. Furniture physically on the route
(a piece shoved off its baked hole) is bulldozed by the character's own push physics; there is no RVO
avoidance and no straight-at-the-destination fallback. `reachable(p)` snaps a point onto the navmesh
(every leaf destination goes through it); `reached(character, point, within := 0)` reports arrival (at the free spot it took, below; never while held).
Falls back to straight-line steering with no agent. It also holds the house `rooms` (set by `Behavior`) and answers `room_key_at(p)` /
`inside_house(p)` for the move's `arrive_room` test and the coverage and combat modules. `reachable` / `on_navmesh` always use the plain map.

**Characters (issue #53).** A walk accounts for the characters the NPC KNOWS of and never walks into one: `Behavior` hands it
the perception's contacts every tick (`bodies`, set in `Behavior.apply`: what it sees, or saw within `contact_memory_ttl`, with `pos`, `vel`, `facing`, `visible`);
a body it has not seen does not exist for the walk, and one out of sight whose last spot (within `WALK_BODY_RANGE`, 450 px) it can see
now with nobody on it has moved on (`Behavior._walk_bodies`, via `AgentPerception.visible_points`). `ignore_id` leaves out the one a
`melee` closes on. A body whose track is slower than
`REST_SPEED` (40 px/s) is at rest, any faster one a walker. Each walk (a new one when the destination moves more than `NEW_WALK` px) is in
one of three ways, checked once a physics frame (`_check`):
- **plain**: the world's own map (furniture only). The first known body at rest the path passes closer than `PASS_CLEARANCE` (32 px, and
  closer than the NPC stands to it now) within `LOOKAHEAD` (400 px), or one standing on the goal, ends it:
- **round**: the Navigation domain's steering map, with every character at rest carved out, when its route reaches the goal and passes
  no known body at rest (`_goes_round`), whatever the detour (out of the room and in by another door included);
- **held**: no way round (the body seals the only way, or has just stopped and the map, re-baked every 0.75 s, has not carved it yet),
  or the body stands on the goal: the NPC walks on until `STOP_GAP` (56 px) from the body and stands. It looks for a way round every
  `RECHECK` s and walks on the moment nothing known is in the way. After `WAIT` (0.75 s), and every `REPLAN_EVERY` (4 s) after, it
  re-plans: a body on the goal sends it to the nearest free spot near the destination (`_free_spot`: rings from 44 px, open floor, 40 px
  clear of every body at rest, same side of the walls); any other hold raises `take_blocked()`, on which `Behavior._way_blocked`
  re-plans whatever walks: a `move` / `engage` / `melee` / `interact` (and a `throw` still closing on its spot) ends with `resolve_reason()`
  "way blocked" and the controller re-decides; an `entry` re-plans its own walk (`Entry.way_blocked`, "Tactical entry" above). The walk
  stays held meanwhile; an evade holds the best spot it has until the burst. So no walk is held more than `WAIT` + `REPLAN_EVERY` s.
  The steering map is the one `NavBuilder.steering_map` names when `setup` runs (Main drops the NPCs in the frame the navmesh is
  built); `_goes_round` waits for `NavBuilder.ready` on both maps.
**Giving way (`_give_way`)**: of two walkers in view whose
courses come within `GIVE_CLEARANCE` (36 px) in the next `GIVE_HORIZON` (1.2 s), the one with the right of way walks on (`_has_way`: the
other sees it, by distance or its facing, and its instance id is the lower; one that cannot see it cannot give way, so the other does); the
other steps aside off the walker's line when it stands on it (open floor, clear of other bodies, never toward the walker), else waits, until
the walker has gone by (at most `GIVE_MAX` 3 s). Even with the right of way it stops for a walker on course closer than `GIVE_IMMINENT`
(50 px), whose track may not show it setting off yet. Last of all, whatever the walk (and the combat back-off), `keep_off` drops the part of a step that heads
into a known body closer than `KEEP_OFF` (36 px) so the NPC slides past it (the agent cuts a path's corners by up to its 16 px
`path_desired_distance`); with nothing left of the step it stands. `holding()` is true whenever the walk stands or steps aside for a body (held, giving way, kept off, or at the free spot beside a taken destination): the entry's crossing then does not push on straight. `debug_state()["loco"]` adds `way`, `held_for`, `giving_way`. Cost: per walker per
frame, the agent's path against the few known bodies near it; a steering route only on a change of way or every `RECHECK` while held; the
free-spot search only on a re-plan. Tests: `tests/ai/movement/npc_detours_round_body_at_rest`, `npc_waits_at_doorway_held_by_teammate`,
`npc_dest_taken_stops_nearby`, `npc_routes_only_round_bodies_it_sees`, `npc_walkers_give_way`, `npc_routes_around_character`,
`npc_own_hole_does_not_slow_it`, and the scenario `tests/ai/entry/entry_team_no_bumping` (real Von; `tests/_ai/bump_probe.gd` measures
"walks into").
