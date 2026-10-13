---
name: domain-ai-watch
description: Deep implementation detail for the AI WATCH module and stage (scenes/ai/behavior/watch.gd + Behavior._apply_watch) — where an NPC looks and when it takes the shot, whatever primitive it is running: the threat that holds its eyes and gun (visible, else engaged, else seen a moment ago with a clear line), the look down its path while walking, the rotating look at its room's doorways while resting, the stop on arrival, the reload reflex with a threat in view, and no sprinting with a shot to take (except a retreat). Use when editing watch.gd or Behavior._apply_watch / _aim_move / _should_run, or working on the NPC turning its back on a threat, staring at a wall, or seeing an enemy and not shooting; the spec and its tests are docs/gaze-and-fire.md. Complements `domain-ai-behavior`, `domain-ai-combat` and the `architecture` skill.
---

# AI · Watch (`scenes/ai/behavior/watch.gd`, the watch stage in `behavior.gd`)

Spec and tests: `docs/gaze-and-fire.md` (W1 to W6; `tools/run_tests.sh gaze`). The invariant: **an NPC is always either looking at
(and, when it can, shooting) a threat, or watching its doors; never a wall, never with its back to a known threat.**

`Character.aim_point` is the only thing that sets facing (standing = instant snap, crouched 5 rad/s), it is never reset, and it defaults
to the world's origin. The primitives set it only as they steer; the watch stage runs after them and has the last word, and it is the one
place a threat is shot at, whichever primitive or entry phase is running.

## The stage (`Behavior._apply_watch`, run in `apply()` right after the primitive steered)

1. Clears `_threat`; does nothing when the character `is_busy()` (frozen in an interaction) or the primitive is `melee` / `interact` /
   an `engage` that has arrived (those aim at their own target).
2. **Threat** (`Watch.threat(_hostiles, _engage_id)`): the engaged contact if `visible`, else the nearest visible, else the engaged one
   as last seen, else the nearest younger than `lost_gaze`. A contact that is not visible only counts when `has_line_to` its last-seen
   spot is clear (no staring at a wall because someone is behind it).
3. With a threat: `aim_point` = its position **before any gate**, then `Combat.fire_at_will` (loaded gun, in `shoot_range`, clear
   line, facing settled, cooldown) and, unless the entry is crossing (`_entry.committed()`, E4), `Combat.reload_if_dry`.
4. With none and `_resting()` (a `hold`, a `reload`, a `move` that has arrived and is not covering a room): `Watch.idle_gaze`.
   `_gaze` (`threat` / `doors` / `primitive`) and `_threat` are in `debug_state()["gaze"]`.

## Watch (`watch.gd`, a `RefCounted` built in `Behavior.setup`, tunables via `apply_config`)

- `threat(hostiles, engaged_id)` — the pick above. `lost_gaze` (`watch_lost_gaze`, 2 s).
- `travel_point(character)` — where a walker looks: the farthest point, up to `look_ahead` (`watch_look_ahead`, 150 px) down the walk
  the nav agent was just given (`Locomotion.path_ahead()`), sampled every 30 px, that it has a clear line to (`has_line_to`); INF with
  none. `Behavior._aim_move`'s default branch and `Entry._aim_travel` use it and fall back to the steering vector. (The next waypoint
  alone hugs the door jamb, so facing it looks at the jamb.)
- `idle_gaze(character, delta)` — turns among `perception.room_doorways(room)` (outer doors included; each with a clear line and not
  under 60 px), nearest first on entering a room then round the NPC by angle, `door_dwell` (`watch_door_dwell`, 2.5 s) apiece, eased at
  `look_rate` (= `search_look_rate`) from the actual facing. Nothing outdoors or with no door in line; an unset `aim_point` (ZERO) becomes
  "where the body points". `reset()` on every new order.

## Around the stage

- `Behavior._apply_move`: an arrived move zeroes `move_input`, so the NPC stands still while the next decision is in flight.
- `_apply_hold` / `_apply_reload` do not aim; the stage does. `update_known` retargets a fight from a contact it has lost sight of to
  another hostile in view.
- `_should_run`: false while `Combat.can_fire_at(threat)` or `Combat.reload_due()`, unless the leaf has `run_through_fire` (the RETREAT
  node). A running character can neither shoot nor reload.
- `Combat`: `can_fire_at`, `reload_due`, `_faces`; `peek_cover` shoots only once facing, ducks only after a shot or an empty click
  (not after a refused shot); `ambush` waits for the facing.
- `Entry`: `gaze_held` (set from `_threat` each tick) makes `_look_toward` report "settled", so a pie step the gaze cannot settle on
  because of a threat does not hold the entry. `_look_toward` and `SearchCoverage.step` ease from the actual facing, not a private angle,
  so the gaze does not snap back when a threat lets go.

## Exports (`GoalController`, group *Watch*)

`watch_look_ahead`, `watch_door_dwell`, `watch_lost_gaze` → Behavior fields → `apply_config()` → `Watch`.

## Tests

`tests/ai/gaze_hold_watches_doors`, `gaze_fresh_npc_keeps_its_facing`, `gaze_arrival_stops` (Von answers held back by `latency_frames`),
`gaze_walk_looks_ahead`, `gaze_search_turns_to_threat`, `gaze_travel_watches_threat`, `entry_guard_fires_from_outside`,
`fire_dry_gun_on_move_reloads`, `combat_waits_for_facing` (`Combat` driven with fakes), `engaged_retargets_to_visible` (`Behavior` driven
with fakes), `ai_runs_to_destination` (W6), `retreat_keeps_running`; helper `tests/_ai/gaze_probe.gd`. A held NPC needs a look direction
(`aim_point`, e.g. `Flank.npc`'s `look_at`) to see a target at start: an unset one looks where its body points.
