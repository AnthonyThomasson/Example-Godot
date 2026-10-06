---
name: domain-ai
description: Deep implementation detail for the AI domain (scenes/ai/) — non-player brains: the one generic goal-driven controller that drives every NPC (house defender and invader alike), its perception helper (contacts), its hostility rules, its tunable vision/sight sense, its event-memory helper, and the dev-only Von decision-server launcher. Use when editing scenes/ai/ or working on NPC goals/behaviour, the behaviour primitives (hostility, pursuit, territory), how NPCs find and categorize hostile characters, vision (field of view/range/line-of-sight) and what an NPC knows vs. remembers, per-NPC house familiarity, the act-centric decision menu, derived movement, commitment/engagement memory, the Von choice requests, or the decision server. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# AI domain

Non-player brains. **One** generic controller (`ai/goal_controller.gd`) drives every NPC, with
helpers for perception (`agent_perception.gd` — contacts + decision state), sight
(`agent_vision.gd`), hostility (`agent_hostility.gd`) and memory (`agent_memory.gd`), plus the
dev-only decision-server launcher. A controller writes the character's intent and calls its public
action API — it never reaches into character internals.

**There is no per-NPC-type or per-goal code.** An NPC's behaviour is data authored on its scene: a
plain-language `goal` string plus a few generic **primitives** (exports on the `GoalController`):

| Primitive | Exports | What it does |
|---|---|---|
| Hostility | `hostile_on_sight`, `hostile_on_trespass`, `hostile_on_attack`, `hostility_ttl`, `allied_factions` | Which perceived characters count as hostile (see below). |
| Pursuit | `pursue_hostiles` | Actively hunt: patrol when no hostile is known, engage when one is. |
| Territory | `defend_territory` | Fight a contact outside the house from inside rather than chase it. |
| Knowledge | `familiar_with_house` + the Vision group | What the NPC starts knowing and how it sees. |

The two presets:
- **Defender** — `character/npc.tscn` (faction `household`): `hostile_on_trespass` +
  `hostile_on_attack`, `defend_territory`, familiar with the house. Main drops it into a random room.
- **Invader** — `character/npc_invader.tscn`, an inherited scene that overrides only data (faction
  `invader`): `hostile_on_sight`, not territorial, unfamiliar with the house, a red body. Main drops
  it just outside the house (`spawn_invader`, `invader_margin`).

## Contacts and hostility

**The NPC perceives characters, not "the player".** Each tick the perception's SEE pass
(`observe()`) runs every other character (found from `world_root()`; the player is just another
character) through the vision sense, and records each visible one as `&"saw_character"`
`{ id, node, name, faction, pos, inside, room, item }` (ttl `contact_memory_ttl`). Each sighting is
then handed to the **hostility rules** (`agent_hostility.gd`, owned by the controller, configured
from the Hostility exports):

- **Allies are never hostile**: same faction as the NPC's character (`Character.faction`), or listed
  in `allied_factions`.
- `on_sight` — any other character seen is hostile (`reason "seen"`).
- `trespass` — any other character seen *inside the house* is hostile (`"trespassing"`).
- `retaliate` — a character that attacks the NPC is hostile (`"attacked you"`). The controller feeds
  this from `&"hit"` events (interface 10): a hit on the NPC, or within `hit_awareness_radius` of it,
  whose `attacker` isn't the NPC itself. Projectiles carry the shooter; the Character posts punches.

A verdict is remembered as `&"hostile"` `{ id, reason }` with ttl `hostility_ttl` (≤ 0 = permanent
grudge), so it persists after the trigger ends (a defender keeps treating an intruder who steps
back outside as hostile; `defend_territory` stops it from chasing).

`perception.contacts(self_pos, memory, hostility)` is the one merged view: the freshest sighting
per character + `hostile` / `reason` + `visible` (seen this tick), hostiles first then nearest.
Dead/freed characters drop out.

## The act-centric decision

Von ranks distinct, verb-like options sharply but ranks many near-identical spatial points almost at
random, so the NPC asks it **WHAT TO DO** and derives the movement itself. Each decision `sense()`
builds a compact text state **from what the NPC sees and remembers**: the goal verbatim; where the
NPC is, what it holds, whether it is mid-interaction; one line per known contact (up to
`max_contacts_in_state`: seen live or "last saw … Ns ago", HOSTILE (reason) or not hostile,
inside/outside + room, bearing, held item); then the combat-awareness lines (under fire from a
direction, any remembered event with a `note`, its own injury level). It POSTs **two `choice`
questions in one request** to a local Jev-style `/v1/systemone` server (Von):

- `act` — the act primitives: `hold`; per **known hostile** contact `shoot_<id>` (if carrying the
  pistol) and `punch_<id>`; `search` (patrol for hostiles) when none is known; plus one
  **interact** option per *distinct* action offered by a **known** object (deduped by label, each
  pointing at the nearest known object offering it; item-gated). A familiar NPC knows the whole
  house from the start; an unfamiliar one only gains objects as it sees them.
- `move` — named destinations only (each known room, `last_seen_<id>` for each known hostile, the
  starting position), consulted **only** when the act is `hold`.

It adopts Von's TOP pick (argmax `choice`) for each; logs `<NPC name> (Von) act=… move=… intent=…`
and holds a steady stance when the server is down.

**Movement and aim are derived from the chosen act** (no aim question):
- `interact` → walk to that object, face it, and run the interaction once in reach.
- `shoot_<id>` → engage that contact with **peek-and-cover** (`_apply_peek_cover`): aim at its
  **last-known** position and fire when `has_line_to(known_pos)` confirms a clear line (never
  through walls), paced by `fire_cooldown`. Vision gates whether it KNOWS a contact; a clear line
  gates whether it can HIT it — so it fires at where it knows they are, independent of its cone.
  PEEK: move to the nearest **fire spot** and shoot, then drop to COVER and duck to the nearest
  **cover spot** for `cover_time`. Positions are committed for `reposition_interval`.
- `punch_<id>` → close to `punch_range` of the last-known position and swing on the cooldown.
- `search` / pursuing with no hostile known → **house patrol** (below).
- `hold` → watch the nearest known hostile, and reposition to the `move` destination if chosen.

The engaged contact is tracked by id (`_engage_id`) and re-resolved from memory each tick
(`_update_known`). If its sighting decays mid-fight the controller retargets the nearest other
known hostile, else drops combat and re-decides.

**Pursuit (`pursue_hostiles`).** The view cone follows the NPC's facing and an interaction freezes
facing, so a hunting NPC must not settle into chores. When on, `_set_act` overrides Von's pick:
- no hostile known → an `interact` pick becomes `search`; holding also patrols. **Patrol**
  (`_patrol`) walks room to room facing its direction of travel so the cone sweeps naturally —
  first to the last-known hostile position right after losing sight (`_investigate_last_seen`),
  then a round-robin room tour (`_next_patrol_point`). It doesn't re-ask Von while patrolling;
  spotting a hostile fires a salient event.
- a hostile known → an `interact` / `hold` / `search` pick becomes engaging the nearest hostile
  (the ~20-option interaction menu otherwise dilutes Von's ranking).

Turn it off for an NPC whose goal is unrelated to fighting (e.g. "watch tv"); a backstop still keeps
a *non-pursuing* NPC dragged into a fight (`&"engaged"` fresh) from peeling off to an interaction.

**Territory (`defend_territory`).** While engaging a contact last seen *outside* the house
(`_hold_ground`), the peek-and-cover fire/cover spots are restricted to inside the house and the
peek fallback stops advancing; melee won't chase out. So a defender returns fire through a
doorway/window instead of leaving the house. When the contact steps inside, normal engagement
resumes.

**Pathing avoids furniture, shoving through only as a last resort.** All derived movement flows
through `_path_move` on a `NavigationAgent2D`. The Navigation domain bakes furniture in as navmesh
holes and surrounds the house with a walkable outdoor ring (so an NPC starting outside can path
to a door). The controller enables RVO **avoidance**: each frame `_path_move` feeds
`_agent.velocity` the desired direction and applies the previous frame's safe velocity
(`_safe_velocity`, from `velocity_computed`). When no route exists (`is_target_reachable()` false)
or the NPC stays wedged (advancing less than `stuck_speed`) for `push_through_delay`, it enters
`_push_through` and drives straight at the blocker so the character's push physics shove it.

**Commitment memory (the System-Two layer Von lacks).** Von is stateless, so the controller holds
the thread: it commits to reaching a chosen object (`max_commit_time` cap), stays in an
interaction for `interaction_dwell`, and **commits to combat** while `&"engaged"` is fresh
(`engage_dwell`, refreshed by each shot fired or taken). It re-decides when the task resolves, the
dwell/cap elapses, or a **salient event** fires (`_check_salient`): the set of known hostiles
changes (one spotted, lost, or newly categorized hostile), the engaged contact crosses the house
boundary, or a hit lands while not already in combat.

**Agent memory (`ai/agent_memory.gd`).** A generic, behaviour-agnostic event log:
`remember(topic, data, ttl)`; `is_fresh`/`recall`/`recall_all`/`age`/`fresh` read back. Not capped
per topic. Cleanup runs on every write: age-expired events (per-entry `ttl`, or
`memory_default_ttl`) first, then, while over `memory_capacity`, the oldest **expirable** events.
**Permanent events (ttl ≤ 0) never age out and are never volume-evicted** (learned house
knowledge, permanent hostility verdicts). Topics in use: `saw_character`, `saw_room`,
`saw_object`, `hostile`, `under_fire`, `engaged`. A remembered event whose `data` has a `note`
string is surfaced to Von automatically.

## Vision & knowledge

`ai/agent_vision.gd` is the **sight sense** — pure, stateless geometry. `can_see(from, facing,
point, space, exclude)` is true when `point` is within `view_distance`, AND either within a 360°
`awareness_radius` bubble or inside the forward cone of half-angle `fov_degrees/2` around the NPC's
facing, AND reachable by a clear line on the physics query layer. `enabled = false` = omniscient.

**Per-NPC knowledge** is a memory seed: `familiar_with_house` (on) seeds every room and object as
permanent on the first observe (`_seed_house`); (off) the NPC must *see* each room/object
(`saw_room` / `saw_object`) before it can navigate to or use it. People are never pre-known — a
character is known only once seen, and forgotten after `contact_memory_ttl` out of sight.

`ai/vision_debug.gd` on the NPC's `VisionDebug` child is an optional draw-only overlay (toggle
`show_vision`) that renders the cone, far arc and awareness bubble from the controller's live
vision params. It senses nothing and feeds nothing back.

Tuning exports on the controller: `goal`, `pursue_hostiles`, `defend_territory`,
`hit_awareness_radius`, `under_fire_time`, `engage_dwell`, `memory_capacity`,
`memory_default_ttl`, `push_through_delay`, `stuck_speed`, combat (`shoot_range`, `punch_range`,
`combat_ring_*`, `cover_time`, `fire_cooldown`, `reposition_interval`), the **Vision** group
(`vision_enabled`, `view_distance`, `fov_degrees`, `awareness_radius`, `familiar_with_house`,
`contact_memory_ttl`) and the **Hostility** group. On the perception: `cover_min`,
`hurt_threshold`, `critical_threshold`, `max_contacts_in_state`.

## Decision server launcher

`ai/decision_server_launcher.gd` (a node in `main.tscn`) starts `von serve` when run from the
editor — using its `von_path`, which defaults to the `application/von/server_path` project setting
(blank = don't auto-start) — logs to `user://von_server.log` + `[von]` Output lines, and kills it
on exit. Every NPC shares the one server.

Note: `mcp__godot__stop_project` hard-kills Godot, so the launcher's `_exit_tree` doesn't run and
the Von server it spawned is orphaned on port 8000 — `pkill -f "von serve"` clears it.

## Interface recap (authoritative in the `architecture` skill)

- **Character ↔ Controller** (interface 7): the controller is any node with `control(character,
  delta)`; it writes `move_input` / `aim_point` and calls `melee()`, `shoot()`, `select_slot(id)`,
  `interact_with(object, id)` / `end_interaction()`; reads `damage_taken()`, `faction`,
  `current_item()`, `has_item()`. Main injects only `rooms`.
- **AI → Navigation** (interface 9): the controller sets a `NavigationAgent2D`'s `target_position`
  and reads `get_next_path_position()`.
- **EventBus** (interface 10): consumes `&"hit"` (`victim`, `position`, `direction`, `attacker`).
