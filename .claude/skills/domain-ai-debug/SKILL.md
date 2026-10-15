---
name: domain-ai-debug
description: Deep implementation detail for the AI DEBUG sub-domain (scenes/ai/debug/) — the draw-only overlays on an NPC: the four core ones plus eleven behaviour overlays (contacts, hearing, combat, territory, targets, brain, routes, stuck, grenades, and the two tactical-entry ones: entry plan, entry team & guard). The vision overlay (LoS-masked FOV cone + awareness bubble), the agent overlay (floating action label + current navigation path), the tactics overlay (the candidate navigation zones it weighed), and the search overlay (room-coverage points a searcher is seeing / still to see). Use when editing scenes/ai/debug/ or working on the NPC vision cone / awareness bubble visualization, the action-status label, the movement-path overlay, the tactical-zone overlay, or the search-coverage overlay. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Debug sub-domain (`scenes/ai/debug/`)

Optional, draw-only overlays that visualize an NPC's brain. They follow the "draw on their own child
`Node2D`" convention, read only the sibling controller's / nav agent's PUBLIC API, sense nothing and
feed nothing back — so they can never affect behaviour. They are added as children of the NPC in the
preset scene (`ai/npc.tscn`).

Files:
- `vision_debug.gd` — the NPC's actual visible area.
- `agent_debug.gd` — the NPC's current decision + path.
- `tactics_debug.gd` — the candidate navigation point zones it weighed, and the room zones it reasons over.
- `zone_list.gd` — a static transform (`ZoneList.from_options`) that flattens a snapshot's option groups into the point zones the tactics overlay draws; the orchestrator's `debug_zones()` calls it (the only file here the orchestrator preloads).
- `search_debug.gd` — how a searcher is covering the room it is in (which points it has seen vs. not).
- `debug_text.gd` — the shared text helper (a label with a shadow) the overlays draw their words with.
- Eleven further overlays, all subclasses of `debug_overlay.gd` (a shared base: finds the controller and
  character, runs `PROCESS_MODE_ALWAYS`, redraws only while its `show_<x>` is on, plus ring/arrow/line/
  timer-arc helpers): `contacts_debug.gd`, `hearing_debug.gd`, `combat_debug.gd`, `territory_debug.gd`,
  `targets_debug.gd`, `brain_debug.gd`, `routes_debug.gd`, `stuck_debug.gd`, `grenade_overlay.gd`, `entry_debug.gd`, `entry_team_debug.gd`
  (see the section below).

## `vision_debug.gd` (toggle `show_vision`)

Draws the portions of the forward FOV cone and the 360° near-awareness bubble that have a clear line
of sight back to the NPC. A ray fan asks the controller each frame where the NPC's sight ends
(`debug_sight_end(to)`, the perception's `sight_end` → `AgentVision.sight_hit`: walls and TALL furniture block,
furniture at or below `see_over_coverage` is seen over) and builds visibility polygons from the answers, so the
shadows are exactly the sense's — only the area that would actually trigger a detection. The overlay casts no
ray of its own. It reads the controller's live vision params
(`vision_enabled`, `view_distance`, `fov_degrees`, `awareness_radius`). When vision is disabled
(omniscient), the bubble is drawn as a plain circle and the cone is skipped.

## `agent_debug.gd` (toggles `show_actions`, `show_path`)

Draws, next to the NPC:
- a floating **action label** — the controller's `debug_status()`: the full decision path, every
  level from the broad mode to the concrete option joined with " - " (`COMBAT - Intruder - FLANK -
  their left side (kitchen)`), then the running primitive's progress and an under-fire alert. The
  controller forwards it from the behaviour sub-domain.
- the NPC's current **movement path** — the `NavigationAgent2D`'s remaining path as a polyline +
  waypoint dots + a target ring.

`label_color` / `path_color` are set per side in the preset scenes to match the body colour.

## `tactics_debug.gd` (toggles `show_tactics`, `show_room_zones` — `main.gd` drives both, off by default)

The tactical-geometry overlay, in two independent aspects (both draw on the NPC's own child Node2D,
reading the controller's public API; both default off — they are dense).

**Point zones (`show_tactics`)** — the candidate positions the NPC's perception laid out for its last
decision, from the controller's `debug_zones()`: a flat list of `{ point, category, label, desc, tags }`, one
per option in the last snapshot's option groups that carries a world location (its `point` param, or an
interactable's current position); the spectator inspector reads `label`/`desc` to detail a clicked
point, and the overlay highlights that point with a double ring via `set_focus()` / `clear_focus()`. Each is a translucent disc + outline + a dot at the exact point,
coloured by `category` (`fire` red, `flank` orange, `advance` yellow, `retreat` blue, `lead` purple,
`search` green, `entry` cyan (the stack slot beside a doorway ENTER offers), `room` teal, `interaction` white,
`waypoint` magenta — `ZONE_COLORS`); each category
is labelled once beside its first marker, so the palette reads as an in-world legend. `waypoint` covers
the non-room go-to options the room/search groups carry (the NPC's starting post, the front entrance,
approaching the house) — re-tagged out of `room`/`search` so these, which often sit well outside any
room, don't read as misplaced room zones. Options with no location (a point-blank punch, the hostile
picks) are skipped. These refresh each decision (the decide cadence). The overlay runs
`PROCESS_MODE_ALWAYS` so it still redraws while the tree is paused — the spectator inspector
(`scenes/ui/hud/spectator_inspector.gd`) flips `show_tactics`/`show_room_zones` per NPC when you click one
during a Space-pause, the usual way to study the zones.

**Room zones (`show_room_zones`)** — every room of the house drawn as a rectangle (faint fill + 2px
outline + a `type · status` tag in the corner), from the controller's `debug_room_zones()`: a list of
`{ rect, type, status }`, tinted by how THIS NPC regards the room right now (`ROOM_COLORS`) —
`current` gold (the room it stands in), `searched` green, `unsearched` orange (seen but not searched
recently), `unknown` grey (not yet seen). This is the room reasoning the search / room / flank points
are placed against, and it is per-NPC: a familiar defender knows every room from the start while an
invader's rooms turn from `unknown` to known as it sees them. Drawn behind the point zones.

## `search_debug.gd` (toggle `show_search` — off by default; shown for the SELECTED NPC)

Visualizes how a `look_around` search move is covering the room by sight (see `domain-ai-coverage`).
Defaults off like the tactics overlay: in spectator mode the inspector turns it on only for the
clicked NPC (it is one of the `_flags`), and in player mode `main.gd`'s `show_search` drives it.
From the controller's `debug_search_coverage()` (`{ active, points, unseen, target, budget }`) it
draws, **only while the NPC is actively covering a room** (`active`): every room sample point dim,
the still-UNSEEN ones bright gold on top (so coverage visibly fills in as they wink out), a red line +
ring to the point the NPC is looking at / walking to right now (`target`), and a `searched N/total  Ss left`
readout beside the NPC (`budget`: the seconds before the search gives up on the room). Nothing is drawn once the room is covered (the move resolves) or when the NPC
isn't searching. Like the others it draws on its own child Node2D, reads only the controller's public
API, and runs `PROCESS_MODE_ALWAYS`.

## Note on the controller's observer getters

All the overlays depend on the controller keeping its observer getters and the Vision exports public.
The controller is the single authoring/observer surface: it forwards `debug_status()` (and
`current_act()`) from the behaviour sub-domain, builds `debug_zones()` from the last perception snapshot
it holds (the flattening is `zone_list.gd` in this folder: a static `ZoneList.from_options(options)`, which also owns the `waypoint` tagging), forwards `debug_room_zones()` from the perception's `room_status()` and
`debug_search_coverage()` from the behaviour's `debug_coverage()`, and holds the Vision group exports —
so these overlays need no reference into the perception/behaviour internals.

## The behaviour overlays (all default off; toggled from the UI toggle bar)

Each is a child of the NPC in `ai/npc.tscn`, found by its `show_<x>` property (registry in
`scenes/ui/overlays/overlay_registry.gd`), and reads only the controller's public `debug_*` getters:

| Overlay (flag) | Draws | Controller getter(s) |
|---|---|---|
| `contacts_debug` (`show_contacts`) | ghost at each contact's last-KNOWN position, fading with age; red/green by hostility + the reason; facing/velocity arrows; wound pip; sight line when visible; lost hostiles' extrapolated heading | `known_contacts_for_display()`, `debug_memory()`, `debug_state()` |
| `hearing_debug` (`show_hearing`) | hearing / hit-awareness / callout-range rings; gunfire heard (fading); incoming-fire arrow; ally callouts heard (speaker→point); the last callout this NPC radioed | `debug_memory()`, `debug_sent_callout()` |
| `combat_debug` (`show_combat`) | engaged target crosshair, fire line (clear green / blocked red / out of range), shoot + punch rings, aim arrow, committed fire/cover spot, peek/cover phase + duck countdown, fire-cooldown arc, ambush badge, RELOADING badge | `debug_combat()` |
| `territory_debug` (`show_territory`) | house outline, "inside/outside · HOLDING GROUND", engaged target inside/outside, zones outside the house a territorial NPC drops | `debug_combat()`, `debug_room_zones()`, `debug_zones()` |
| `targets_debug` (`show_targets`) | requested vs navmesh-snapped destination (red = unreachable), room-entry target, interact object + dwell arc, hold watch line, checked-lead count | `debug_combat()`, `debug_memory()` |
| `brain_debug` (`show_brain`) | THINKING badge while Von is asked, FALLBACK badge when the last walk failed, next-decision / tactic / commit timers, force reason, true facts, per-level probability bars | `debug_brain()` |
| `routes_debug` (`show_routes`) | navigated route to each fire/flank/advance/retreat point (green hidden / red exposed), clear-shot + cover notes, flank `held by` / `route passes` / ally lane, hostile `watch_arc` wedges | `debug_zones()` (entries carry `tags`), `known_contacts_for_display()`; route from the nav map, cached 0.5 s |
| `stuck_debug` (`show_stuck`) | recent-position trail + a ring that reddens while the NPC is trying to move without progressing | `debug_progress()` |
| `grenade_overlay` (`show_grenades`) | (docs/grenades.md G19) every live grenade the NPC knows of: a dot with its danger radius ringed round it, `kind fuse_left (source)` and a countdown arc (against the grenade's whole `fuse`, which `debug_grenades()` reports); the safe spot it is running to (green ring, line from the NPC); a planned throw (`throw` set: an arc from the hand to the landing spot, the grenade's danger radius round it) | `debug_grenades()` |
| `entry_debug` (`show_entry`) | this NPC's tactical entry: the doorway, its out-normal and the fatal funnel; stack slots in use (numbered, its own ringed; a lone entrant's far side faint); approach waypoints; the pie arc (steps done dim / to go bright, the current one ringed), the line through the doorway and the room points still unseen; corners red hard / green soft, filled once its pie saw them, its target corner ringed; its gaze; after the clear the doorways on (line + wedge, the one it covers bright, a solo sweep numbered) or the rear it holds; cleared rooms outlined; a badge (slot, role, phase, pie progress, seen %) with timer arcs for the ready wait, follow gap and hold | `debug_entry_view()` |
| `entry_team_debug` (`show_entry_team`) | the team off the radio: each ally's claim (from where it radioed to its slot, `slot N · step`, an arrow to the doorway on it covers) and who the point is waiting for; the entry guard: the next doorway into an uncleared room on the walk and how far (cyan within `entry_guard_range`, grey beyond), a running detour (GUARD badge, dashed line to the paused order), doorways it is leaving alone | `debug_entry_view()` |

The getters are read-only and added to the controller: `debug_memory()` (perception memory: gunfire,
under-fire, callouts, checked leads, lost hostiles, radii), `debug_combat()` (behaviour
state as world-space data), `debug_brain()` (planner pending / last-failed / levels, decide + force timers
and the last force reason, facts), `debug_progress()` (locomotion `sample()` — observation only, nothing
reacts to a stall), `debug_sent_callout()`, `debug_grenades()` (perception's known grenades, the behaviour's evade spot and, from the throw primitive, the throw planned until the grenade leaves the hand (`Behavior.throw_plan`): `{ known: [{ point, kind, fuse_left, fuse, radius, source }], escape: Vector2 (INF: not running to one), throw: {} }`) and `debug_entry_view()` (behaviour `debug_entry_view`: the running entry as
world-space data from entry.gd `debug_view` under `entry`, and the entry guard's picture under `guard`; the guard's
look-ahead along the walk is computed only when asked). `debug_zones()` entries also carry the option's `tags`
(`inside`, `held`, `crosses`/`crosses_name`, `no_shot`, `heading`, `lane`, `hidden`, plus `clear_shot`,
`route_exposed`, `cover`, `ally_lane`, `held_by` added by the snapshot's
`_geo_tags()`; the planner reads only `inside` and the booleans a node's `drop_tags` names, and `hidden` only orders the
retreat summary, so the extras don't affect decisions).
