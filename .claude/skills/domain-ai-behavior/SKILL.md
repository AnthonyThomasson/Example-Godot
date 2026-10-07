---
name: domain-ai-behavior
description: Deep implementation detail for the AI BEHAVIOUR sub-domain (scenes/ai/behavior/) — turning the chosen act into movement + actions, and the System-Two state Von lacks. The generic primitives (pursuit, territory, flanking), act interpretation, peek-and-cover shooting, melee, house patrol/search, object interaction, commitment memory, and the locomotion layer (nav pathing, furniture bulldozing, stuck detection, door-opening). Use when editing scenes/ai/behavior/ or working on NPC combat maneuvering, flanking, holding ground, patrol/search, how an act becomes movement, engagement retargeting, commitment/dwell timers, or pathing/stuck recovery. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Behaviour sub-domain (`scenes/ai/behavior/`)

The ACT half: it turns the act Von chose into concrete movement + actions on the character, and holds
the System-Two state Von (a stateless ranker) lacks — the engaged contact, the peek-and-cover cycle,
the patrol tour, the interaction in progress, and the COMMITMENT timers that let multi-step goals
advance instead of oscillating. It reads the world only through the perception sub-domain and drives
the character only through its public controller contract (`move_input`/`aim_point`, `select_slot`,
`shoot`, `melee`, `interact_with`, `end_interaction`).

Files:
- `behavior.gd` — the act machine (a `Node`); owns all act-execution + commitment state.
- `locomotion.gd` — the pathing layer (a `Node` child of behaviour); owns the NavigationAgent2D.

The controller copies its exports onto the behaviour's config fields and calls
`setup(perception, nav_agent)` once; the behaviour builds and configures its `Locomotion` child.

## The generic primitives (no per-NPC-type or per-goal code)

| Primitive | Exports (on the controller) | What it does |
|---|---|---|
| Pursuit | `pursue_hostiles` | Actively hunt: patrol when no hostile is known, engage when one is. |
| Territory | `defend_territory` | Fight a contact outside the house from inside rather than chase it. |
| Flanking | `flank`, `flank_weight`, `flank_ally_radius` | Re-rank fire spots to attack from the target's side/rear and spread allied attackers around it. |

## Public interface (what the orchestrator calls)

- `setup(perception, nav_agent)`; config fields; `rooms` (set each tick) + `entry_point` (handed once).
- `update_known(known, delta) -> bool` — adopt the perception's contacts (hostiles/allies,
  retarget the engaged contact, investigate-last-seen on loss), advance the commit timer; returns true
  when it dropped a fight whose target decayed (→ controller forces a re-decision).
- `salient_key() -> String` — the known-hostile set + engaged inside/outside, for the controller's
  edge-detection (spotting/losing/recategorizing a hostile, or the target crossing the boundary).
- `service_interaction(character, delta, force) -> bool` — hold/advance/end an active interaction;
  true while still interacting (the tick returns). `take_resolved() -> bool` — a task just finished
  (interaction ended / hold destination reached) → the controller forces a re-decision.
- `wants_decision(character, decide_timer_elapsed) -> bool` — whether the current commitment still
  holds (fight while `engaged` fresh, approach until its cap, pursuing-search never on cadence, hold
  move until arrival) or it's time to re-ask.
- `set_act(act_id, acts)` / `set_move(move_id, moves)` — adopt Von's pick (incl. the pursuit/engaged
  policy overrides); `apply(character, delta)` — carry out the current act; `fallback()` — steady
  stance when Von is unreachable; `current_act()` / `intent()` / `in_combat()` / `debug_status()`.

## The act-centric derivation

Movement and aim are DERIVED from the chosen act (no aim question):
- `interact` → walk to the object, face it, run the interaction once in reach; hold it for
  `interaction_dwell`.
- `shoot_<id>` → **peek-and-cover** (`_apply_peek_cover`): aim at the contact's **last-known** position
  and fire when `has_line_to` confirms a clear line, paced by `fire_cooldown`; PEEK to a **fire spot**
  and shoot, then drop to COVER for `cover_time`. Positions committed for `reposition_interval`.
- `punch_<id>` → close to `punch_range` of the last-known position and swing on the cooldown.
- `search` / pursuing with no hostile known → **house patrol** (below).
- `hold` → watch the nearest known hostile, reposition to the `move` destination if chosen.

**Act overrides (`set_act`).** The pursuit primitive and an engaged backstop rewrite Von's pick first:
pursuing with a known hostile turns an `interact`/`hold`/`search` pick into engaging the nearest
(the ~20-option interaction menu otherwise dilutes Von's ranking); pursuing with none known turns an
`interact` pick into `search`; and a non-pursuing NPC dragged into a fight (`engaged` fresh) won't be
peeled off to a chore mid-combat.

**Territory (`defend_territory`).** While engaging a contact last seen *outside* the house, fire/cover
spots are restricted to inside and the peek fallback stops advancing; melee won't chase out — so a
defender returns fire through a doorway/window instead of leaving. Normal engagement resumes once the
contact steps inside.

**Flanking (`flank`).** The peek fire spot is re-ranked by *angular openness* — how far each spot's
bearing from the target is from the bearings to avoid (where a **visible** target is facing, and where
each known ally within `flank_ally_radius` stands) — traded against travel distance (`flank_weight`).
So a lone NPC works to the side/rear and several attackers spread around the target (stigmergic, each
just avoiding where it *sees* friends). Composes with territory (inside filter first, then re-rank);
collapses to nearest-spot when off or with no bearings to avoid.

**Patrol (`_patrol`).** Walks room to room facing its direction of travel so the cone sweeps —
first to the last-known hostile spot right after losing sight, then a round-robin room tour; an
unfamiliar NPC outside heads to the injected `entry_point` (the front door) or the house centroid.

## Commitment memory (the System-Two layer Von lacks)

The behaviour holds the thread Von can't: commits to reaching a chosen object (`max_commit_time`
cap), stays in an interaction for `interaction_dwell`, and **commits to combat** while the perception's
`engaged` memory is fresh (`engage_dwell`, refreshed by each shot via `note_engaged()`). A fight
retargets to the nearest other known hostile if its sighting decays mid-fight, else drops combat.

## Locomotion (`locomotion.gd`)

All derived movement flows through `move_to(character, dest)` on a `NavigationAgent2D`. The Navigation
domain bakes furniture in as navmesh holes and rings the house with a walkable outdoor strip.
Steering always aims at `get_next_path_position()` — a navmesh waypoint, so it is wall-safe, and for
an unreachable target it steps toward the closest reachable point. Furniture physically on the route
(a piece shoved off its baked hole) is bulldozed by the character's own push physics as it walks into
it; there is no RVO avoidance and no straight-at-the-destination fallback, which is what used to let
an unreachable `dest` tunnel a wall. A shut door within `door_open_reach` that the NPC is wedged
against (advancing < `stuck_speed`) is OPENED instead, since doorways stay walkable in the navmesh
and a door is static so the push physics can't move it. `reachable(p)` snaps a point onto the navmesh
(a room centre is often inside furniture, and an off-navmesh target would otherwise be unreachable) —
both the patrol legs and the chosen hold destination are snapped through it;
`reached(character, point)` reports arrival. Falls back to straight-line steering with no agent.
