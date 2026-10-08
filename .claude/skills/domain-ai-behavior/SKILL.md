---
name: domain-ai-behavior
description: Deep implementation detail for the AI BEHAVIOUR sub-domain (scenes/ai/behavior/) — running the decision planner's leaf as one primitive (move / engage / melee / interact / hold) and the System-Two state Von lacks: engagement + retargeting, peek-and-cover and ambush, fire-at-will on the move, territorial confinement, commitment (when a running choice re-decides), the full-path debug label, and the locomotion layer (nav pathing, furniture bulldozing, stuck detection, door-opening). Use when editing scenes/ai/behavior/ or working on how a chosen option becomes movement and shooting, combat maneuvering, holding ground, commitment/dwell timers, or pathing/stuck recovery. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Behaviour sub-domain (`scenes/ai/behavior/`)

The ACT half: it runs the LEAF the decision planner chose — one primitive with its params — as
concrete movement + actions, and holds the System-Two state Von (a stateless ranker) lacks. It never
chooses WHAT to do and applies no policy beyond its params. It reads the world only through the
perception sub-domain and drives the character only through its public controller contract
(`move_input`/`aim_point`, `select_slot`, `shoot`, `melee`, `interact_with`, `end_interaction`).

Files:
- `behavior.gd` — the primitive executor (a `Node`); owns engagement + commitment state.
- `locomotion.gd` — the pathing layer (a `Node` child of behaviour); owns the NavigationAgent2D.

The controller sets the behaviour's config fields from its exports, calls `setup(perception, nav_agent)`
once to build its `Locomotion` child, then `apply_config()` to push the forwarded locomotion tunables
in — re-calling `apply_config()` each decision so a runtime retune takes effect. (The behaviour's own
fields are read live, so only locomotion needs the push.)

## The primitives (a leaf = `{ path, labels, primitive, params }`)

| Primitive | Params | What it does | Done / re-decides |
|---|---|---|---|
| `move` | `point`, `aim` (travel / target / threat / point), `target_id`, `fire_at_will`, `arrive_room` | Path to the point (or until ENTERING `arrive_room`), aiming as asked; with `fire_at_will`, shoots a known hostile on a clear line once facing settles (`AIM_TOLERANCE`). Holds on arrival. | On arrival (forces a decision), or at `max_commit_time`. |
| `engage` | `point` (anchor), `target_id`, `style` (peek_cover / ambush), `confine_inside` | Path to the anchor firing at will, then fight from it: **peek-and-cover** (peek to the nearest spot with a clear shot, fire on `fire_cooldown`, duck to cover for `cover_time`, positions committed for `reposition_interval`) or **ambush** (hold the covered spot, fire the moment a line opens). FLANK and PUSH use this anchored at the chosen spot. | Moving: at `max_commit_time`. In position: every `tactic_interval` (timer starts on arrival) or when `engaged` lapses. |
| `melee` | `target_id`, `confine_inside` | Close to `punch_range` and swing. | `tactic_interval` / `engaged` lapse. |
| `interact` | `object`, `id` | Walk to the object, face it, run the interaction, hold it `interaction_dwell`. | Dwell over (forces a decision), or approach cap. |
| `hold` | — | Stand and watch the nearest known hostile. | Decide cadence. |

**Territory** is a param, not a policy: with `confine_inside` (set by the planner for a territorial
NPC's combat leaves) and a contact last seen outside, fire/cover spots are restricted to inside the
house, the peek fallback holds instead of advancing, and melee won't chase out.

## Public interface (what the orchestrator calls)

- `setup(perception, nav_agent)` (build the Locomotion child), `apply_config()` (push the forwarded
  locomotion tunables in; re-callable each decision); config fields; `rooms` (set each tick).
- `set_leaf(leaf)` — adopt: snap the point onto the navmesh, capture the target (a fight whose target
  is no longer known drops to hold and forces a re-decision), commit.
- `update_known(known, delta) -> bool` — adopt the perception's hostiles; retarget a lost engaged
  contact to the nearest other; with none left, a leaf that needs a target ends → true (re-decide).
- `salient_key()`, `service_interaction(character, delta, force)`, `take_resolved()`,
  `wants_decision(character, cadence_elapsed)` (the table's last column), `apply(character, delta)`,
  `fallback()` (steady hold when no decision can be had).
- `reached_lead()` — the investigation lead (`params.lead`) the running move has reached, which the
  controller hands to perception's `check_lead()` so it isn't offered again.
- `ongoing()` — the running choice is still in progress (en route, fighting, using an object): only
  then does the planner mark the option continuing it "(your current plan)" — a finished move must
  not be re-picked just because it was the last plan.
- Read-only: `current_act()` (path ids), `intent()` (the broad mode), `in_combat()`, `debug_status()`
  — **the full decision path, every level, joined with " - "** (`COMBAT - Intruder - FLANK - their
  left side (kitchen)  · in position, looking for a shot  ⚠ under fire`), `activity_text()` (the same
  path + progress + how long, for Von's "current activity" line), `debug_state()` (JSON-safe).

## Locomotion (`locomotion.gd`)

All movement flows through `move_to(character, dest)` on a `NavigationAgent2D`. The Navigation
domain bakes furniture in as navmesh holes and rings the house with a walkable outdoor strip.
Steering always aims at `get_next_path_position()` — a navmesh waypoint, so it is wall-safe, and for
an unreachable target it steps toward the closest reachable point. Furniture physically on the route
(a piece shoved off its baked hole) is bulldozed by the character's own push physics; there is no RVO
avoidance and no straight-at-the-destination fallback. A shut door within `door_open_reach` that the
NPC is wedged against (advancing < `stuck_speed`) is OPENED instead. `reachable(p)` snaps a point onto
the navmesh (every leaf destination goes through it); `reached(character, point)` reports arrival.
Falls back to straight-line steering with no agent.
