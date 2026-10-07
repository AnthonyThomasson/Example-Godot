---
name: domain-ai-debug
description: Deep implementation detail for the AI DEBUG sub-domain (scenes/ai/debug/) — the two draw-only overlays on an NPC. The vision overlay (LoS-masked FOV cone + awareness bubble) and the agent overlay (floating action label + current navigation path). Use when editing scenes/ai/debug/ or working on the NPC vision cone / awareness bubble visualization, the action-status label, or the movement-path overlay. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Debug sub-domain (`scenes/ai/debug/`)

Optional, draw-only overlays that visualize an NPC's brain. Both follow the "draw on their own child
`Node2D`" convention, read only the sibling controller's / nav agent's PUBLIC API, sense nothing and
feed nothing back — so they can never affect behaviour. They are added as children of the NPC in the
preset scene (`character/npc.tscn`).

Files:
- `vision_debug.gd` — the NPC's actual visible area.
- `agent_debug.gd` — the NPC's current decision + path.

## `vision_debug.gd` (toggle `show_vision`)

Draws the portions of the forward FOV cone and the 360° near-awareness bubble that have a clear line
of sight back to the NPC. A ray fan samples the physics space each frame (same `QUERY_MASK = 1` as
the vision sense) and builds visibility polygons, so walls and furniture cast proper shadows — showing
only the area that would actually trigger a detection. It reads the controller's live vision params
(`vision_enabled`, `view_distance`, `fov_degrees`, `awareness_radius`). When vision is disabled
(omniscient), the bubble is drawn as a plain circle and the cone is skipped.

## `agent_debug.gd` (toggles `show_actions`, `show_path`)

Draws, next to the NPC:
- a floating **action label** — the controller's `debug_status()` (intent, act verb + target, combat
  phase, under-fire alert), which the controller forwards from the behaviour sub-domain.
- the NPC's current **movement path** — the `NavigationAgent2D`'s remaining path as a polyline +
  waypoint dots + a target ring.

`label_color` / `path_color` are set per side in the preset scenes to match the body colour.

## Note on the controller's observer getters

Both overlays depend on the controller keeping `debug_status()` and the Vision exports public. The
controller is the single authoring/observer surface: it forwards `debug_status()` (and `current_act()`)
from the behaviour sub-domain and holds the Vision group exports, so these overlays need no reference
into the perception/behaviour internals.
