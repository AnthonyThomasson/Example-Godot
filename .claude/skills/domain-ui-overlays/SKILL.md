---
name: domain-ui-overlays
description: Deep implementation detail for the UI overlays sub-domain (scenes/ui/overlays/) — the single table of debug overlays (OverlayRegistry), the in-game overlay toggle bar (OverlayToggles with group buttons and All), the performance overlay (FPS, frame time, draw calls, graph) and the DragHandle helper. Use when editing scenes/ui/overlays/ or adding/renaming a debug overlay flag, the toggle bar or the performance panel. Complements the `domain-ui` overview, `domain-ai-debug` (the overlay draw scripts) and the `architecture` skill.
---

# UI · Overlays sub-domain (`scenes/ui/overlays/`)

The tooling that switches the AI/nav debug overlays on and off and shows engine stats. The overlay draw scripts themselves live in `scenes/ai/debug/` (`domain-ai-debug`); this folder holds the registry row for each flag and the bars that flip it. See `domain-ui` for what all UI scripts share.

- `overlay_registry.gd` — the ONE table of debug overlays (`ENTRIES`: `flag`, `label`, `group`, `default`;
  `defaults()`; `NAV_HOLES` (labelled "Navigation holes": furniture and characters at rest) and `PERF`, the global non-per-NPC flags, listed in `GLOBAL` / `is_global(flag)`).
  `flag` is the overlay node's `show_<x>` property name. The setup window, the toggle bar and Main all read it, so a new overlay is one row here
  plus its draw script (`scenes/ai/debug/`) and a node in `npc.tscn`.

- `overlay_toggles.gd` — the **in-game overlay toggle bar** (`OverlayToggles` CanvasLayer, built by
  `main.gd` after the world spawns, both modes, only when Debug is on). A collapsible top-right panel (1.5× scale: `SCALE` in the script) of toggle buttons grouped
  from the registry (Perception / Combat / Movement / Brain / Entry / Map / Stats). An **All (n/N)** button and each
  group's header button (`Perception (n/N)`) flip a whole set: all on unless already all on, then all off; each
  changed flag emits its own `overlay_toggled`, so Main needs no bulk path. `RESERVED_WIDTH` is the screen width it occupies from the right edge. `setup(flags)` seeds the buttons;
  pressing one emits `overlay_toggled(flag, on)`, which Main applies live (`_on_overlay_toggled`: player
  mode → every NPC's overlay via `_configure_debug`; spectator mode → `SpectatorInspector.set_flag`, so
  the selected NPC follows; `show_nav_holes` → the single NavDebug; `show_perf` → the PerformanceOverlay).
  `PROCESS_MODE_ALWAYS` (works while paused); the panel swallows clicks so pressing a button never selects
  an NPC; buttons take no focus (Space stays pause/interact). The "Overlays" title is a drag handle
  (`DragHandle`) that moves the bar; the `▸/▾` button beside it collapses it.

- `drag_handle.gd` — the **drag-to-move helper** (`DragHandle` Node, added as a child of the handle Control;
  `setup(handle, target)`). Left-drag the handle to move `target` by shifting its offsets (anchors kept, so it
  stays put relative to its screen edge on resize), clamped inside the viewport. Used by the toggle bar
  (title) and the performance overlay (whole panel).

- `performance_overlay.gd` — the **performance overlay** (`PerformanceOverlay` CanvasLayer, layer 9, built by
  `main.gd` next to the toggle bar when Debug is on; `set_shown(on)` from the "Performance" toggle, off
  by default). A compact semi-transparent panel docked left of the toggle bar (`OverlayToggles.RESERVED_WIDTH`)
  at y 76 — below the match HUD's top-centre timer and right of its goal readout, so it overlaps no other
  HUD in either mode. Shows FPS (+ low over the last `SAMPLES` frames), frame / physics ms, draw calls,
  objects, node count, active 2D physics objects, static memory (Godot `Performance` monitors, text refreshed
  every `REFRESH` s) and a per-frame frame-time bar graph with a 16.7 ms reference line. Left-drag the panel to
  move it (it swallows clicks, so it blocks click-to-inspect beneath it). `PROCESS_MODE_ALWAYS` (keeps
  updating while paused); hidden it stops processing.

## Interface recap

- `main.gd` reads `OverlayRegistry` (`defaults()`, `is_global`, `NAV_HOLES`, `PERF`), builds `OverlayToggles` + `PerformanceOverlay` when Debug is on and applies `overlay_toggled(flag, on)`; the Testing runner builds the same widgets for its overlay bar (architecture interface 13).
- Tests: `tests/ui/overlay_toggles_test.gd`.
