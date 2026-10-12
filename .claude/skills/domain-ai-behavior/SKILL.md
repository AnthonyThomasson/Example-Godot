---
name: domain-ai-behavior
description: Deep implementation detail for the AI BEHAVIOUR sub-domain (scenes/ai/behavior/) — running the decision planner's leaf as one primitive (move / engage / melee / interact / hold / reload / entry) and the System-Two state Von lacks: the tactical entry phase machine (entry.gd: stack, slice the pie, cross, corners, clear, rear security, over the team radio), engagement + retargeting, territorial confinement, posture and run policy, commitment (when a running choice re-decides), the full-path debug label, and the locomotion layer (nav pathing, room queries, furniture bulldozing). The fighting itself is `domain-ai-combat` (combat.gd) and room search by sight is `domain-ai-coverage` (search_coverage.gd). Use when editing scenes/ai/behavior/ (behavior.gd, entry.gd, locomotion.gd) or working on how a chosen option becomes movement, holding ground, commitment/dwell timers, or pathing. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Behaviour sub-domain (`scenes/ai/behavior/`)

The ACT half: it runs the LEAF the decision planner chose — one primitive with its params — as
concrete movement + actions, and holds the System-Two state Von (a stateless ranker) lacks. It never
chooses WHAT to do and applies no policy beyond its params. It reads the world only through the
perception sub-domain and drives the character only through its public controller contract
(`move_input`/`aim_point`, `select_slot`, `shoot`, `melee`, `interact_with`, `end_interaction`).

Files:
- `behavior.gd` — the primitive executor (a `Node`); owns engagement + commitment state, posture / run policy and the read-outs.
- `combat.gd` — shots, punches, bursts, back-off, the peek-and-cover cycle (`RefCounted`; `domain-ai-combat`).
- `search_coverage.gd` — covering a room by sight (`RefCounted`; `domain-ai-coverage`).
- `entry.gd` — a tactical entry through a doorway, as a team member or alone (`RefCounted`; see "Tactical entry" below).
- `locomotion.gd` — the pathing layer (a `Node` child of behaviour); owns the NavigationAgent2D and answers `room_key_at(p)` / `inside_house(p)`.

The controller sets the behaviour's config fields from its exports, calls `setup(perception, nav_agent)`
once to build its `Locomotion`, `SearchCoverage` and `Combat` children, then `apply_config()` to push the tunables they hold
in — re-calling `apply_config()` each decision so a runtime retune takes effect. (The behaviour's own
fields are read live, so only those modules need the push.)

## The primitives (a leaf = `{ path, labels, primitive, params }`)

| Primitive | Params | What it does | Done / re-decides |
|---|---|---|---|
| `move` | `point`, `aim` (travel / target / threat / point), `target_id`, `fire_at_will`, `arrive_room`, `look_around` | Path to the point (or until ENTERING `arrive_room`), aiming as asked; with `fire_at_will`, shoots a known hostile on a clear line once facing settles (`Combat.fire_at_will`). Holds on arrival. A `look_around` move (search / explore) walks all the way INTO the room, then **covers it by sight** (`search_coverage.gd`, the `domain-ai-coverage` skill) until it has SEEN the room or its budget runs out. ADVANCE is a `move` with `aim: target` + `fire_at_will`: it closes in, then re-decides how to fight. | On arrival (forces a decision) — a `look_around` move only once the room is covered or its budget runs out (`max_commit_time` still caps the walk INTO the room before coverage starts). |
| `engage` | `point` (anchor), `target_id`, `style` (peek_cover / ambush), `confine_inside` | Path to the anchor firing at will, then fight from it: **peek-and-cover** (peek to the nearest spot with a clear shot, fire on `fire_cooldown`, duck to cover for `cover_time`, positions committed for `reposition_interval`) or **ambush** (hold the covered spot, fire the moment a line opens). ENGAGE and FLANK use this, anchored at the chosen spot or side. | Moving: at `max_commit_time`. In position: every `tactic_interval` (timer starts on arrival) or when `engaged` lapses. |
| `melee` | `target_id`, `confine_inside` | Close to `punch_range` and swing. | `tactic_interval` / `engaged` lapse. |
| `interact` | `object`, `id` | Walk to the object, face it, run the interaction, hold it `interaction_dwell`. | Dwell over (forces a decision), or approach cap. |
| `reload` | — | Equip the gun (`gun_slot()`), stand still watching the nearest hostile and `Character.reload()`; ends when the reload does (or at once if it can't start). | The reload ending (forces a decision), or `max_commit_time`. |
| `entry` | `opening`, `into`, `slot`, `side` (from the ENTER option), `run` | A tactical entry through the doorway (`entry.gd`, below): approach and stack, slice the pie, cross, take a corner, clear the room, maybe hold the door. Shoots on a clear line once crossing. | When the entry is over (room clear, rear watch done, or given up); never on the cadence. |
| `hold` | — | Stand and watch the nearest known hostile. | Decide cadence. |

**Territory** is a param, not a policy: with `confine_inside` (set by the planner for a territorial
NPC's combat leaves) and a contact last seen outside, `Behavior` sets `hold_ground`, which `Combat` honours (see `domain-ai-combat`).

**Running** is a behaviour policy, not a primitive: after the primitive steers, `_should_run()` sets
`character.run_input` only while TRAVELLING (a `move` or `engage` not yet arrived — never a `look_around`
search, ambush/peek, interaction or hold — or a `melee` closing in), when the leaf carries `run: true` or
the NPC is under fire, the destination is farther than `run_min_distance` (straight line), and a run can
start (`run_start_fraction` of the stamina bar, or already running). The Character spends the stamina and
walks once dry. Exports on the controller: `run_enabled`, `run_min_distance`, `run_start_fraction`.
`debug_status()` reads "running" / "running into position" while it sprints; `debug_state()` has `running`.
A running NPC cannot shoot (`Character.shoot()` is ignored while running): `Combat.shoot()` skips a shot
while `is_running()` without spending the fire cooldown, so it fires as soon as the run ends.
Test: `tests/ai/ai_runs_to_destination_test.gd`.

**Posture** is a behaviour policy too (spec: `docs/cover-and-stance.md`, A1 to A3): after the primitive has steered and `run_input` is set,
`_apply_posture` writes the posture `_wanted_posture` asks for through `Character.set_posture` (idempotent, so every tick). Everything outside a
fight and everything travelling to a destination (`move`, an `engage` not yet arrived, `melee`, `interact`) **stands** — only a standing body runs —
and so does an NPC that is running. Fighting in place (`engage` arrived, or `hold` / `reload` with a hostile known or shots landing) it **crouches** (behind cover, in the open or
pinned alike, and when moving about inside the fight). A crouch is held `posture_dwell` (0.7 s) before it is dropped; standing back up is never delayed.
Exports on the controller: `posture_enabled` (the `ai.posture` switch), `posture_dwell`. `debug_status()` appends "crouching";
`debug_state()` has `posture`. Not a decision-tree level: Von is never asked, so it works with the server down. Tests:
`tests/ai/posture_crouches_in_fight_test.gd`, `posture_pinned_crouch_test.gd`, `posture_stands_to_run_test.gd`.

**Combat** — the gunnery, the peek-and-cover cycle, bursts, backing off a blocked barrel, the reload reflex, melee and the
no-per-weapon-code rule — is `combat.gd`: the **`domain-ai-combat`** skill. `Behavior` passes it the engaged contact and `hold_ground`.

## Tactical entry (`entry.gd`)

The spec and the tests are `docs/tactical-entry.md` (E1 to E8) and `tests/ai/entry_*_test.gd`. `Behavior` adopts an
ENTER leaf, starts the entry on the next tick (`begin(character, params)`: it reads the doorway's geometry and the team
off the perception, `entry_geometry` / `entry_team`) and then calls `step()` each tick until it reports done. Phases:
`approach` (to its stack slot: if on the wrong side of the door, out from the wall and across far out first; then to a
point past the slot and along the wall into it, so it never walks the door's axis close in), `stack` (in the slot facing
the door; radios `ready`), `pie` (the point — the lowest slot still waiting — walks the pie arc, at each step turning its
gaze through the door until it settles plus `entry_pie_dwell`, dropping room sample points (`SearchCoverage.sample_room`)
and corners it sees: `seen_fraction`, hidden corners; alone it then crosses in front, far out, and slices the other
side), `cross` (radios `going_in`; walks to its corner without stopping; `in` once past the wall plane and off the axis),
`corner` (holds it `entry_corner_dwell` looking across the room), `clear` (`SearchCoverage.begin/step`; radios `clear`
with `cleared_room` once the rest of the stack is in), `rear` (the last of the team in holds just inside the door facing
out for `rear_security_time`).

- **Barrier and order.** The point crosses when every other claimant has radioed past `claim`, or `entry_ready_timeout`
  after it was ready (restarted when the stack grows). A follower crosses `entry_follow_gap` after the member ahead of
  it radioed `in`. A member still at `claim` once the one behind has waited the timeout is dropped from the order.
- **Corners.** Point: the door-wall corner on its own side (buttonhook); alone, the door-wall corner on the side away
  from where it ended the pie. Second: the hard corner on the other side. Later members: a spot inside off the axis.
- **Commitment.** `committed()` is true while crossing; the controller starts no decision then (a forced one waits),
  so a hit or a hostile seen in the doorway is fought once the NPC is through. Posture stands throughout; it may run
  only on the approach (`travel_target()`).
- **The radio.** Steps are queued (`take_calls()`, via `Behavior.take_entry_calls()`) and the controller posts them;
  the latest is repeated every 2 s so the claim stays live. Choosing anything else `abandon()`s the entry (radios
  `abort`). Each phase change is a `GameLog` line (`--verbose` in tests).
- **Read-outs.** `Behavior.debug_entry()` (opening, into, slot, side, solo, phase, seen_fraction, pie_sides,
  hidden_corners, corner, stack_point, team), also under `entry` in `debug_state()`; the status line says the phase
  ("stacked at the door", "slicing the pie", "going in" ...).

## Public interface (what the orchestrator calls)

- `setup(perception, nav_agent)` (build the Locomotion, coverage and combat modules), `apply_config()` (push their tunables
  in; re-callable each decision); config fields; `rooms` (set each tick; forwarded to Locomotion).
- `set_leaf(leaf)` — adopt: snap the point onto the navmesh, capture the target (a fight whose target
  is no longer known drops to hold and forces a re-decision), commit.
- `update_known(known, delta) -> bool` — adopt the perception's hostiles; retarget a lost engaged
  contact to the nearest other; with none left, a leaf that needs a target ends → true (re-decide).
- `salient_key()`, `service_interaction(character, delta, force)`, `take_resolved()`,
  `wants_decision(character, decide_timer_elapsed)` (the table's last column), `apply(character, delta)`,
  `fallback()` (steady hold when no decision can be had), `committed()` (crossing a doorway: no decision may
  start), `take_entry_calls()` (entry steps for the controller to radio), `debug_entry()`, `path_label()`.
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

All movement flows through `move_to(character, dest)` on a `NavigationAgent2D`. The Navigation
domain bakes furniture in as navmesh holes and rings the house with a walkable outdoor strip.
Steering always aims at `get_next_path_position()` — a navmesh waypoint, so it is wall-safe, and for
an unreachable target it steps toward the closest reachable point. Furniture physically on the route
(a piece shoved off its baked hole) is bulldozed by the character's own push physics; there is no RVO
avoidance and no straight-at-the-destination fallback. `reachable(p)` snaps a point onto the navmesh
(every leaf destination goes through it); `reached(character, point)` reports arrival. Falls back to
straight-line steering with no agent. It also holds the house `rooms` (set by `Behavior`) and answers `room_key_at(p)` /
`inside_house(p)` for the move's `arrive_room` test and the coverage and combat modules.
