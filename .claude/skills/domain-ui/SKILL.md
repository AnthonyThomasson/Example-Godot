---
name: domain-ui
description: Deep implementation detail for the UI domain (scenes/ui/) — debug player panel, spectator match HUD, pre-game setup window, seed readout, overlay toggles, and the test browser window + test result banner. Use when editing scenes/ui/ or working on any in-game overlay, the setup menu, the seed label, or the test browser UI. All are decoupled observers: they read only the Character public API/signals, the AI controller's current_act()/goal, and the EventBus — never domain internals. Complements the `architecture` skill.
---

# UI domain (`scenes/ui/`)

Four `CanvasLayer` nodes, all built entirely in code (no scene-side layout), all decoupled observers
that read only published contracts — Character public API/signals, the AI controller's
`debug_status()` / `current_act()` and `goal`, and the EventBus `&"hit"` topic. They know nothing of
the domains.

## Files

- `debug_ui.gd` — the **player debug panel** (`DebugUI` node). Bottom-right stats block: current
  item slot, punch active flag, active interaction, reach. Top-left hit banner: last body hit, method
  (punch left/right or gunshot), damage, and elapsed time. Listens to `hit_landed` on the character;
  freed in spectator mode. Font sizes: stats 34pt, hit banner 32pt.

- `match_hud.gd` — the **spectator match HUD** (`MatchHUD` node). `begin(combatants)` wires it to
  any number of NPCs; each combatant gets a compact floating panel (300×145 px, 28pt font) — name,
  faction, health bar, current act (the controller's `debug_status()` — the full decision path,
  word-wrapped) — whose bottom-centre is placed 24 px above the NPC's on-screen origin each
  frame via `get_global_transform_with_canvas()` (clamped inside the viewport). Also: a top-centre
  running timer (34pt), a top-left goal readout listing every NPC's name and goal (28pt, spans the left half of the screen and word-wraps), a centre
  winner banner (62pt gold), and a bottom-left combat feed (28pt orange, last 6 hits from EventBus
  `&"hit"`). Declares the winner once an entire faction is eliminated.

- `setup_menu.gd` — the **pre-game setup window** (`SetupMenu` node). `open(defaults)` shows a
  full-screen modal (40 px margins, VBox separation 20) with: "Human player" checkbox,
  "Seed" text field (blank = random), Defenders/Invaders spinboxes, a single "Debug" checkbox (the master
  switch for the AI overlays: off = every overlay hidden and no toggle bar; on = the toggle bar, every overlay starting off, plus
  the bar), and a Start button. Pressing Start emits `start_requested({ has_player, seed, defenders,
  invaders, debug })`. Main opens it on a fresh launch on a fresh launch; a scripted `restart` sets the
  Engine `skip_setup` meta so the harness bypasses it. Title 64pt; controls 30pt; separator 28pt;
  Start button 32pt. A **Tests** button (28pt) below Start emits `tests_requested`; Main changes scene to
the test browser. Pressing Start also **disables the button**, because Main may hold the start
  open for a moment (it waits for the Von decision server) and a second press would build the world
  twice. `set_status(text)` writes a 24pt line above the Start button (hidden when blank) — Main
  shows "Waiting for the decision server…" there so that pause is never silent.

- `test_browser_window.gd` — the **test browser window** (`TestBrowserWindow` CanvasLayer, hosted by the
  Testing domain's `test_browser.tscn`). `open(tests, results, matcher, filter, selected)` builds a
  full-screen window: a search box (filtered by the host's `matcher(test, text)`), a `Tree` of tests grouped
  by domain (marked ✓/✗/⏱/– by last result, `[manual]` / `[Von]` tags), a details pane (description, world,
  tags, switches with off in red, Von need) and Back / Play. Play, double-click or Enter emit
  `play_requested(path)`; Back emits `back_requested`; typing emits `filter_changed(text)`. Takes plain test
  descriptor dicts — knows nothing of the Testing classes.

- `test_result_hud.gd` — the **test result banner** (`TestResultHUD` CanvasLayer, layer 10, top-left, built by
  the test runner in interactive mode). `show_running(entry)` names the test, `show_status(text)` shows a wait
  line, `show_result(result)` shows the verdict (PASS / FAIL / TIMEOUT / SKIPPED, or MANUAL for a passing
  sandbox) with each check ✓/✗, the sim time and, for a failure, each actor's final state (`result.snapshot`). Rerun / Back buttons emit `rerun_requested` /
  `back_requested`; they take no focus so keys stay with the game underneath.

- `overlay_registry.gd` — the ONE table of debug overlays (`ENTRIES`: `flag`, `label`, `group`, `default`;
  `defaults()`; `NAV_HOLES` and `PERF`, the global non-per-NPC flags, listed in `GLOBAL` / `is_global(flag)`).
  `flag` is the overlay node's `show_<x>` property name. The setup window, the toggle bar and Main all read it, so a new overlay is one row here
  plus its draw script (`scenes/ai/debug/`) and a node in `npc.tscn`.

- `overlay_toggles.gd` — the **in-game overlay toggle bar** (`OverlayToggles` CanvasLayer, built by
  `main.gd` after the world spawns, both modes, only when Debug is on). A collapsible top-right panel (1.5× scale: `SCALE` in the script) of toggle buttons grouped
  from the registry (Perception / Combat / Movement / Brain / Map / Stats). `RESERVED_WIDTH` is the screen width it occupies from the right edge. `setup(flags)` seeds the buttons;
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

- `seed_display.gd` — the **seed readout** (`SeedDisplay` node). `show_seed(level_seed)` writes the
  run's seed into a 32pt label anchored to the bottom-right corner (semi-transparent), so a layout
  you like can be re-entered in the setup window.

- `spectator_inspector.gd` — the **spectator inspector** (`SpectatorInspector` node), built by `main.gd`
  only in spectator mode via `setup(combatants, flags)` (`flags` = the current overlay toggles; `set_flag(flag, on)` updates one live from the toggle bar and re-applies it to the selected NPC).
  **Space** toggles `get_tree().paused`. A **left-click** on an NPC (nearest within `PICK_RADIUS` of the
  cursor's world point, via the framing camera) selects it — revealing ONLY that NPC's *enabled* overlays
  (each toggle set from `flags`) and hiding every other NPC's; clicking it again or empty ground clears
  it. No NPC shows any overlay until clicked (the view stays focused on one NPC). With an NPC selected, a
  left-click on one of its tactical points (nearest zone within `ZONE_PICK_RADIUS`, from its
  `debug_zones()`) highlights that point (overlay `set_focus`) and fills a detail panel — top-left,
  directly beneath the match HUD's goal readout — with the zone's kind, label and Von's reasoning (`desc`). It runs `PROCESS_MODE_ALWAYS` so Space/clicks work while
  paused (freeze the match, then inspect). Decoupled like the other observers: reads the combatants'
  public `global_position`, the camera, and each NPC's `debug_zones()`, and flips the debug-overlay
  toggles (every per-NPC flag of the overlay registry) by the same
  duck-typed names `main.gd`'s `_configure_debug` uses. Reads `Keybinds.PAUSE` (Space; shares it with
  `INTERACT`, unused in the player-less match). Mouse-ignoring hint + detail labels (with text shadow).

## Interface recap

- UI observers attach by exported node path (or node name duck-typed in `main.gd`) and read only the
  Character public API/signals plus `AIController.current_act()` / `goal` (interface 7 in the
  `architecture` skill). EventBus `&"hit"` is the only cross-domain event consumed here.
- `main.gd` calls `MatchHUD.begin(combatants)`, `SetupMenu.open(defaults)` /
  `SetupMenu.set_status(text)`, and `SeedDisplay.show_seed(seed)` — the only outward calls the UI
  domain receives.
