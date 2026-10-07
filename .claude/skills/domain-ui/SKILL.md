---
name: domain-ui
description: Deep implementation detail for the UI domain (scenes/ui/) — debug player panel, spectator match HUD, pre-game setup window, and seed readout. Use when editing scenes/ui/ or working on any in-game overlay, the setup menu, or the seed label. All four are decoupled observers: they read only the Character public API/signals, the AI controller's current_act()/goal, and the EventBus — never domain internals. Complements the `architecture` skill.
---

# UI domain (`scenes/ui/`)

Four `CanvasLayer` nodes, all built entirely in code (no scene-side layout), all decoupled observers
that read only published contracts — Character public API/signals, the AI controller's `current_act()`
and `goal`, and the EventBus `&"hit"` topic. They know nothing of the domains.

## Files

- `debug_ui.gd` — the **player debug panel** (`DebugUI` node). Bottom-right stats block: current
  item slot, punch active flag, active interaction, reach. Top-left hit banner: last body hit, method
  (punch left/right or gunshot), damage, and elapsed time. Listens to `hit_landed` on the character;
  freed in spectator mode. Font sizes: stats 34pt, hit banner 32pt.

- `match_hud.gd` — the **spectator match HUD** (`MatchHUD` node). `begin(combatants)` wires it to
  any number of NPCs; each combatant gets a compact floating panel (300×145 px, 28pt font) — name,
  faction, health bar, current act — whose bottom-centre is placed 24 px above the NPC's on-screen origin each
  frame via `get_global_transform_with_canvas()` (clamped inside the viewport). Also: a top-centre
  running timer (34pt), a top-left goal readout listing every NPC's name and goal (28pt), a centre
  winner banner (62pt gold), and a bottom-left combat feed (28pt orange, last 6 hits from EventBus
  `&"hit"`). Declares the winner once an entire faction is eliminated.

- `setup_menu.gd` — the **pre-game setup window** (`SetupMenu` node). `open(defaults)` shows a
  full-screen modal (40 px margins, VBox separation 20) with: "Human player" checkbox, "Spawn doors"
  checkbox, "Seed" text field (blank = random), Defenders/Invaders spinboxes, three debug-overlay
  checkboxes ("Agent labels", "Agent paths", "Vision cones"), and a Start button. Pressing Start
  emits `start_requested({ has_player, seed, spawn_doors, defenders, invaders, show_agent_labels,
  show_agent_paths, show_vision })`. Main opens it on a fresh launch; a scripted `restart` sets the
  Engine `skip_setup` meta so the harness bypasses it. Title 64pt; controls 30pt; separator 28pt;
  Start button 32pt.

- `seed_display.gd` — the **seed readout** (`SeedDisplay` node). `show_seed(level_seed)` writes the
  run's seed into a 32pt label anchored to the bottom-right corner (semi-transparent), so a layout
  you like can be re-entered in the setup window.

## Interface recap

- UI observers attach by exported node path (or node name duck-typed in `main.gd`) and read only the
  Character public API/signals plus `AIController.current_act()` / `goal` (interface 7 in the
  `architecture` skill). EventBus `&"hit"` is the only cross-domain event consumed here.
- `main.gd` calls `MatchHUD.begin(combatants)`, `SetupMenu.open(defaults)`, and
  `SeedDisplay.show_seed(seed)` — the only outward calls the UI domain receives.
