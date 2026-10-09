---
name: domain-ui
description: Deep implementation detail for the UI domain (scenes/ui/) — debug player panel, spectator match HUD, pre-game setup window, and seed readout. Use when editing scenes/ui/ or working on any in-game overlay, the setup menu, or the seed label. All four are decoupled observers: they read only the Character public API/signals, the AI controller's current_act()/goal, and the EventBus — never domain internals. Complements the `architecture` skill.
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
  running timer (34pt), a top-left goal readout listing every NPC's name and goal (28pt), a centre
  winner banner (62pt gold), and a bottom-left combat feed (28pt orange, last 6 hits from EventBus
  `&"hit"`). Declares the winner once an entire faction is eliminated.

- `setup_menu.gd` — the **pre-game setup window** (`SetupMenu` node). `open(defaults)` shows a
  full-screen modal (40 px margins, VBox separation 20) with: "Human player" checkbox, "Spawn doors"
  checkbox, "Seed" text field (blank = random), Defenders/Invaders spinboxes, six debug-overlay
  checkboxes ("Agent labels", "Agent paths", "Vision cones", "Tactics zones", "Room zones",
  "Furniture holes"), and a Start button. Pressing Start emits `start_requested({ has_player, seed,
  spawn_doors, defenders, invaders, show_agent_labels, show_agent_paths, show_vision, show_tactics,
  show_room_zones, show_nav_holes })`. Main opens it on a fresh launch; a scripted `restart` sets the
  Engine `skip_setup` meta so the harness bypasses it. Title 64pt; controls 30pt; separator 28pt;
  Start button 32pt. Pressing Start also **disables the button**, because Main may hold the start
  open for a moment (it waits for the Von decision server) and a second press would build the world
  twice. `set_status(text)` writes a 24pt line above the Start button (hidden when blank) — Main
  shows "Waiting for the decision server…" there so that pause is never silent.

- `seed_display.gd` — the **seed readout** (`SeedDisplay` node). `show_seed(level_seed)` writes the
  run's seed into a 32pt label anchored to the bottom-right corner (semi-transparent), so a layout
  you like can be re-entered in the setup window.

- `spectator_inspector.gd` — the **spectator inspector** (`SpectatorInspector` node), built by `main.gd`
  only in spectator mode via `setup(combatants, flags)` (`flags` = the setup menu's overlay toggles).
  **Space** toggles `get_tree().paused`. A **left-click** on an NPC (nearest within `PICK_RADIUS` of the
  cursor's world point, via the framing camera) selects it — revealing ONLY that NPC's *enabled* overlays
  (each toggle set from `flags`) and hiding every other NPC's; clicking it again or empty ground clears
  it. No NPC shows any overlay until clicked (the view stays focused on one NPC). With an NPC selected, a
  left-click on one of its tactical points (nearest zone within `ZONE_PICK_RADIUS`, from its
  `debug_zones()`) highlights that point (overlay `set_focus`) and fills a detail panel — top-left,
  directly beneath the match HUD's goal readout — with the zone's kind, label and Von's reasoning (`desc`). It runs `PROCESS_MODE_ALWAYS` so Space/clicks work while
  paused (freeze the match, then inspect). Decoupled like the other observers: reads the combatants'
  public `global_position`, the camera, and each NPC's `debug_zones()`, and flips the debug-overlay
  toggles (`show_actions` / `show_path` / `show_vision` / `show_tactics` / `show_room_zones`) by the same
  duck-typed names `main.gd`'s `_configure_debug` uses. Reads `Keybinds.PAUSE` (Space; shares it with
  `INTERACT`, unused in the player-less match). Mouse-ignoring hint + detail labels (with text shadow).

## Interface recap

- UI observers attach by exported node path (or node name duck-typed in `main.gd`) and read only the
  Character public API/signals plus `AIController.current_act()` / `goal` (interface 7 in the
  `architecture` skill). EventBus `&"hit"` is the only cross-domain event consumed here.
- `main.gd` calls `MatchHUD.begin(combatants)`, `SetupMenu.open(defaults)` /
  `SetupMenu.set_status(text)`, and `SeedDisplay.show_seed(seed)` — the only outward calls the UI
  domain receives.
