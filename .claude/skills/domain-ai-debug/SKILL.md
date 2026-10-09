---
name: domain-ai-debug
description: Deep implementation detail for the AI DEBUG sub-domain (scenes/ai/debug/) — the three draw-only overlays on an NPC. The vision overlay (LoS-masked FOV cone + awareness bubble), the agent overlay (floating action label + current navigation path), and the tactics overlay (the candidate navigation zones it weighed). Use when editing scenes/ai/debug/ or working on the NPC vision cone / awareness bubble visualization, the action-status label, the movement-path overlay, or the tactical-zone overlay. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Debug sub-domain (`scenes/ai/debug/`)

Optional, draw-only overlays that visualize an NPC's brain. Both follow the "draw on their own child
`Node2D`" convention, read only the sibling controller's / nav agent's PUBLIC API, sense nothing and
feed nothing back — so they can never affect behaviour. They are added as children of the NPC in the
preset scene (`character/npc.tscn`).

Files:
- `vision_debug.gd` — the NPC's actual visible area.
- `agent_debug.gd` — the NPC's current decision + path.
- `tactics_debug.gd` — the candidate navigation point zones it weighed, and the room zones it reasons over.

## `vision_debug.gd` (toggle `show_vision`)

Draws the portions of the forward FOV cone and the 360° near-awareness bubble that have a clear line
of sight back to the NPC. A ray fan samples the physics space each frame (same `QUERY_MASK = 1` as
the vision sense) and builds visibility polygons, so walls and furniture cast proper shadows — showing
only the area that would actually trigger a detection. It reads the controller's live vision params
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

## `tactics_debug.gd` (toggles `show_tactics`, `show_room_zones` — both off by default)

The tactical-geometry overlay, in two independent aspects (both draw on the NPC's own child Node2D,
reading the controller's public API; both default off — they are dense).

**Point zones (`show_tactics`)** — the candidate positions the NPC's perception laid out for its last
decision, from the controller's `debug_zones()`: a flat list of `{ point, category, label, desc }`, one
per option in the last snapshot's option groups that carries a world location (its `point` param, or an
interactable's current position); the spectator inspector reads `label`/`desc` to detail a clicked
point, and the overlay highlights that point with a double ring via `set_focus()` / `clear_focus()`. Each is a translucent disc + outline + a dot at the exact point,
coloured by `category` (`fire` red, `flank` orange, `advance` yellow, `retreat` blue, `lead` purple,
`search` green, `room` teal, `interaction` white, `waypoint` magenta — `ZONE_COLORS`); each category
is labelled once beside its first marker, so the palette reads as an in-world legend. `waypoint` covers
the non-room go-to options the room/search groups carry (the NPC's starting post, the front entrance,
approaching the house) — re-tagged out of `room`/`search` so these, which often sit well outside any
room, don't read as misplaced room zones. Options with no location (a point-blank punch, the hostile
picks) are skipped. These refresh each decision (the decide cadence). The overlay runs
`PROCESS_MODE_ALWAYS` so it still redraws while the tree is paused — the spectator inspector
(`scenes/ui/spectator_inspector.gd`) flips `show_tactics`/`show_room_zones` per NPC when you click one
during a Space-pause, the usual way to study the zones.

**Room zones (`show_room_zones`)** — every room of the house drawn as a rectangle (faint fill + 2px
outline + a `type · status` tag in the corner), from the controller's `debug_room_zones()`: a list of
`{ rect, type, status }`, tinted by how THIS NPC regards the room right now (`ROOM_COLORS`) —
`current` gold (the room it stands in), `searched` green, `unsearched` orange (seen but not searched
recently), `unknown` grey (not yet seen). This is the room reasoning the search / room / flank points
are placed against, and it is per-NPC: a familiar defender knows every room from the start while an
invader's rooms turn from `unknown` to known as it sees them. Drawn behind the point zones.

## Note on the controller's observer getters

All three overlays depend on the controller keeping its observer getters and the Vision exports public.
The controller is the single authoring/observer surface: it forwards `debug_status()` (and
`current_act()`) from the behaviour sub-domain, builds `debug_zones()` from the last perception snapshot
it holds, forwards `debug_room_zones()` from the perception's `room_status()`, and holds the Vision
group exports — so these overlays need no reference into the perception/behaviour internals.
