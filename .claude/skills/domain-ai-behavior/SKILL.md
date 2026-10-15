---
name: domain-ai-behavior
description: Deep implementation detail for the AI BEHAVIOUR sub-domain (scenes/ai/behavior/) — running the decision planner's leaf as one primitive (move / engage / melee / interact / hold / reload / entry / throw) and the System-Two state Von lacks: engagement + retargeting, territorial confinement, posture and run policy, commitment (when a running choice re-decides), the full-path debug label, and the locomotion layer (nav pathing, room queries, furniture bulldozing). The fighting itself is `domain-ai-combat` (combat.gd), room search by sight is `domain-ai-coverage` (search_coverage.gd), where it looks and when it takes the shot is `domain-ai-watch` (watch.gd) and the tactical entry through a doorway (entry.gd: stack, slice the pie, cross, corners, clear, rear security, over the team radio, and the entry guard) is `domain-ai-entry`. Use when editing scenes/ai/behavior/ (behavior.gd, locomotion.gd) or working on how a chosen option becomes movement, holding ground, commitment/dwell timers, or pathing. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
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
- `entry.gd` — a tactical entry through a doorway, as a team member or alone (`RefCounted`; `domain-ai-entry`, spec `docs/tactical-entry.md`).
- `locomotion.gd` — the pathing layer (a `Node` child of behaviour); owns the NavigationAgent2D and answers `room_key_at(p)` / `inside_house(p)`.

The controller sets the behaviour's config fields from its exports, calls `setup(perception, nav_agent)`
once to build its `Locomotion`, `SearchCoverage`, `Combat`, `Watch` and `Entry` modules, then `apply_config()` to push the tunables they hold
in — re-calling `apply_config()` each decision so a runtime retune takes effect. (The behaviour's own
fields are read live, so only those modules need the push.) On its first `control()` the controller calls `bind(character)`: the
behaviour keeps the NPC's body and hands it to each module's own `bind`, so none of their functions takes the character.

## The primitives (a leaf = `{ path, labels, primitive, params }`)

| Primitive | Params | What it does | Done / re-decides |
|---|---|---|---|
| `move` | `point`, `aim` (travel / target / threat / point), `target_id`, `arrive_room`, `look_around` | Path to the point (or until ENTERING `arrive_room`), aiming as asked (a threat in sight takes the eyes and the gun: the watch stage, below). Stops on arrival (`move_input` is zeroed every tick after it, so the NPC stands still while the next decision is on its way: a real Von answer takes a moment, and from a point near the front door the last heading is out of the house; tests `tests/ai/movement/move_stops_on_arrival_test.gd`, `gaze_arrival_stops`). A `look_around` move (search / explore) walks all the way INTO the room, then **covers it by sight** (`search_coverage.gd`, the `domain-ai-coverage` skill) until it has SEEN the room or its budget runs out. ADVANCE is a `move` with `aim: target`: it closes in, then re-decides how to fight. | On arrival (forces a decision) — a `look_around` move only once the room is covered or its budget runs out (`max_commit_time` still caps the walk INTO the room before coverage starts). |
| `engage` | `point` (anchor), `target_id`, `style` (peek_cover / ambush), `confine_inside` | Path to the anchor firing at will, then fight from it: **peek-and-cover** (peek to the nearest spot with a clear shot, fire on `fire_cooldown`, duck to cover for `cover_time`, positions committed for `reposition_interval`) or **ambush** (hold the covered spot, fire the moment a line opens). ENGAGE and FLANK use this, anchored at the chosen spot or side. | Moving: at `max_commit_time`. In position: every `tactic_interval` (timer starts on arrival) or when `engaged` lapses. |
| `melee` | `target_id`, `confine_inside` | Close to `punch_range` and strike (a kick with a gun in hand, else a punch). | `tactic_interval` / `engaged` lapse. |
| `interact` | `object`, `id` | Walk to the object, face it, run the interaction, hold it `interaction_dwell`. | Dwell over (forces a decision), or approach cap. |
| `reload` | — | Equip the gun (`gun_slot()`), stand still (its eyes where the watch stage puts them) and `Character.reload()`; ends when the reload does (or at once if it can't start). | The reload ending (forces a decision), or `max_commit_time`. |
| `entry` | `opening`, `into`, `slot`, `side` (from the ENTER option) | A tactical entry through the doorway (`entry.gd`, `domain-ai-entry`): approach and stack, slice the pie, cross, take a corner, clear the room, maybe hold the door. Shoots a threat in sight in every phase (the watch stage). | When the entry is over (room clear, rear watch done, or given up); never on the cadence. The entry guard (below) also runs it, as a detour in the middle of another order. |
| `throw` | `point` (the spot), `kind` (`frag` / `stun`), `radius`, `slot`, `target_id`, `from` (where it throws from), `walk` (`from` is a throw spot) | The GRENADE tactic (`docs/grenades.md` G17; `combat.gd` does the throwing, `domain-ai-combat`): with a throw spot (issue #51 R13) walk all the way to it first (gun in hand, the watch stage on any threat; status "walking to the throw spot"; a held walk re-decides like a move; the walk is guarded like an engage's: `_entry_guard`, `_guards` and `_keeps_out_of_views` take the throw's `walk` stage, and `_resume_order` re-begins the throw (`_begin_throw_order`) when a detour's entry hands it back), then take the grenade in hand, turn to the spot (closing the last px if it drifted out of range since the offer), throw (the line is re-checked until the wind-up begins and the throw dropped if it is blocked; from the wind-up on it is committed), radio `frag_out` / `bang_out` as it leaves the hand (`take_throw_calls`), gun back in hand, then stand out the fuse (the watch stage shoots from there). An evade plan (the thrower in its own burst's zone) replaces the order at the release tick; `poll_throw` runs before it so the call is radioed first. Committed (no re-decision) during the wind-up. | When the grenade has gone off (or the throw could not be made, or the fuse plus a second ran out). |
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
auto-reload, but for the NPC's own throw in its wind-up (`throw_stage` `windup`: the grenade leaves the hand within 0.3 s toward its spot; the evade starts the tick it has, `poll_throw` running first; test `ai/grenade/evade_waits_for_own_windup`): while a live grenade threatens the NPC it is carried out instead of the running order, an entry (committed or not) and an interaction included. The first
tick of a plan drops the detour, abandons the entry (the stack is told), and replaces the order with `evade` (path `["evade"]`, labels `EVADE - a live frag grenade`);
no decision is started or adopted while it runs (the controller's `_should_decide` / `_on_decided`, `set_leaf`). `_apply_evade` runs all the way into `plan.spot` (`Locomotion.move_to`
within `EVADE_REACH` 6 px: a spot is out of the burst's line with little room to spare, so a stride short of it can be in the line; looking where it
goes, running when `run_enabled` and stamina allow), then holds it facing away from the grenade, **crouched when the spot is cover** (`plan.crouch`); the watch stage does not run (no
turning to a threat, no shot). With no spot in time it stays, facing away (a stun then blinds it for the back-turned share only), crouched for a frag. When the plan ends (the burst) `_resolved` forces
a new decision. Read-outs: `evading()`, `evade_spot()` (the controller's `debug_grenades().escape`), `debug_state()["evade"]`. Tests: `tests/ai/grenade/evade_*`.

**A blinded NPC** (`Character.is_blind()`): the orchestrator starts no new decision (`_should_decide`) and re-decides the tick its sight returns; the order it was carrying out goes on
(it stumbles: the character is slowed and drifts); the perception keeps its contacts (so the watch stage's engaged-contact pick, or the arrived peek-and-cover, fires at the hostile's last-known
spot with the character's aim sway, G13) and sees no new one. A deafened NPC hears no gunfire, no hit elsewhere and no callout (the orchestrator drops them).

## Tactical entry (`entry.gd`) — `domain-ai-entry`

The entry phase machine, its team radio, the entry guard's detours and the entry read-outs are the **`domain-ai-entry`** skill.

## Public interface (what the orchestrator calls)

- `setup(perception, nav_agent)` (build the Locomotion, coverage, combat, watch and entry modules), `apply_config()` (push their tunables
  in; re-callable each decision), `bind(character)` (the body, once); config fields; `rooms` (set each tick; forwarded to Locomotion).
- `set_leaf(leaf)` — adopt: snap the point onto the navmesh, capture the target (a fight whose target
  is no longer known drops to hold and forces a re-decision), commit.
- `update_known(known, delta) -> bool` — adopt the perception's hostiles; retarget a lost engaged
  contact to the nearest other; with none left, a leaf that needs a target ends → true (re-decide).
- `salient_key()`, `service_interaction(delta, force)`, `take_resolved()` (with `resolve_reason()`, read just before it:
  "way blocked" when a body seals the only way of the walk and stays, "" for a finished task; the controller forces its decision with it),
  `wants_decision(decide_timer_elapsed)` (the table's last column), `apply(delta)`,
  `fallback()` (steady hold when no decision can be had), `committed()` (crossing a doorway, throwing the bang, a throw's wind-up: no decision may
  start), `take_entry_calls()` (entry steps for the controller to radio), `debug_entry()`, `debug_entry_view()`,
  `debug_combat()`, `debug_coverage()`, `debug_progress()`, `path_label()`, `throw_plan()` (the throw about to be made,
  `{ from, to, kind, radius }`, `{}` once the grenade is away: the grenades overlay's `throw`), `order()` (the running order's `{ path, labels }`),
  `take_entry_turned()` and `adopt_bang(path, labels)` (an ENTER that turned into a bang one is re-adopted as STUN ENTRY, E17: `domain-ai-entry`).
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

All movement flows through `move_to(dest, within := 0)` on a `NavigationAgent2D` (`within`: arrive closer than the agent's
own 16 px; the entry's stack slots use `SLOT_REACH` 6 px, since a member a stride short of its slot stands on the next one). `path_ahead()` returns the walk it was just given
(`{ path, index }`, or {}), which the behaviour's entry guard reads. The Navigation
domain bakes furniture in as navmesh holes and rings the house with a walkable outdoor strip.
Steering always aims at `get_next_path_position()` — a navmesh waypoint, so it is wall-safe, and for
an unreachable target it steps toward the closest reachable point. Furniture physically on the route
(a piece shoved off its baked hole) is bulldozed by the character's own push physics; there is no RVO
avoidance and no straight-at-the-destination fallback. `reachable(p)` snaps a point onto the navmesh
(every leaf destination goes through it); `reached(point, within := 0)` reports arrival (at the free spot it took, below; never while held).
Falls back to straight-line steering with no agent. It also holds the house `rooms` (set by `Behavior`) and answers `room_key_at(p)` /
`inside_house(p)` for the move's `arrive_room` test and the coverage and combat modules. `reachable` / `on_navmesh` always use the plain map.

**Characters (issue #53).** A walk accounts for the characters the NPC KNOWS of and never walks into one: `Behavior` hands it
the perception's contacts every tick (`bodies`, set in `Behavior.apply`: what it sees, or saw within `contact_memory_ttl`, with `pos`, `vel`, `facing`, `visible`);
a body it has not seen does not exist for the walk, and one out of sight whose last spot (within `WALK_BODY_RANGE`, 450 px) it can see
now with nobody on it has moved on (`Behavior._walk_bodies`, via `AgentPerception.visible_points`). `ignore_id` leaves out the one a
`melee` closes on. A body whose track is slower than
`REST_SPEED` (40 px/s) is at rest, any faster one a walker. Each walk (a new one when the destination moves more than `NEW_WALK` px) is in
one of four ways, checked once a physics frame (`_check`):
- **plain**: the world's own map (furniture only). The first known body at rest the path passes closer than `PASS_CLEARANCE` (32 px, and
  closer than the NPC stands to it now) within `LOOKAHEAD` (400 px), or one standing on the goal, ends it:
- **doors**: the Navigation domain's avoid map (`NavBuilder.avoid_map`: the planning bake with the doorway views carved out, E18), for a walk
  `Behavior` marks `avoid_doors` (above). `_update_doors` asks the perception for the route (`walk_route(goal, avoid_exempt)`) each frame until
  it is decided (plain while the avoid map bakes: `pending`), then every `DOORS_RECHECK` (2 s) while round the views (which keeps the map alive and follows
  the rooms as their clear lapses): the avoid map when the plain route comes into a view and the route round them is within `door_avoid_ratio` x plain +
  `door_avoid_slack`, else plain (and `passing_ahead` secures what it crosses). A walk that is not guarded (`avoid_doors` false) drops it. A body at rest on
  a doors walk's path takes it to the steering map (round) or holds it as on a plain one: the steering map has no views carved, so E15 secures what that
  crosses; once the way is free it goes back to the avoid map: a held walk at once (`_free_way`), a walk gone round once the avoid map's route to the goal passes
  no known body at rest all the way, not only the first `LOOKAHEAD` (`_clear_on`, looked at every `RECHECK` s; a body just past the look-ahead would send it
  round again a few strides on). Tests: `tests/ai/movement/npc_doors_walk_round_body`, `npc_doors_walk_body_on_goal` (scripted).
- **round**: the Navigation domain's steering map, with every character at rest carved out, when its route reaches the goal and passes
  no known body at rest (`_goes_round`), whatever the detour (out of the room and in by another door included);
- **held**: no way round (the body seals the only way, or has just stopped and the map, re-baked every 0.75 s, has not carved it yet),
  or the body stands on the goal: the NPC walks on until `STOP_GAP` (56 px) from the body and stands. It looks for a way round every
  `RECHECK` s and walks on the moment nothing known is in the way. After `WAIT` (0.75 s), and every `REPLAN_EVERY` (4 s) after, it
  re-plans: a body on the goal sends it to the nearest free spot near the destination (`_free_spot`: rings from 44 px, open floor, 40 px
  clear of every body at rest, same side of the walls); any other hold raises `take_blocked()`, on which `Behavior._way_blocked`
  re-plans whatever walks: a `move` / `engage` / `melee` / `interact` (and a `throw` still closing on its spot) ends with `resolve_reason()`
  "way blocked" and the controller re-decides; an `entry` re-plans its own walk (`Entry.way_blocked`, `domain-ai-entry`). The walk
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
frame, the agent's path against the few known bodies near it; a steering route only on a change of way or every `RECHECK` while held; an
avoid-map route every `RECHECK` while a walk that keeps out of the doorway views is round a body, and `walk_route` every `DOORS_RECHECK`
while it is round the views; the free-spot search only on a re-plan. Tests: `tests/ai/movement/npc_detours_round_body_at_rest`, `npc_waits_at_doorway_held_by_teammate`,
`npc_dest_taken_stops_nearby`, `npc_routes_only_round_bodies_it_sees`, `npc_walkers_give_way`, `npc_routes_around_character`,
`npc_own_hole_does_not_slow_it`, `npc_doors_walk_round_body`, `npc_doors_walk_body_on_goal`, and the scenario `tests/ai/entry/entry_team_no_bumping`
(real Von; `tests/_ai/bump_probe.gd` measures "walks into", and standing pressed against a body, which `keep_off` alone stops short of a bump).
