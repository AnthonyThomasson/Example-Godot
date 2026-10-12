---
name: domain-ui
description: Overview of the UI domain (scenes/ui/) — all HUDs and menus, split into four sub-domains by folder: menus (setup window, settings page), hud (debug panel, match HUD, seed label, spectator inspector), overlays (overlay registry, toggle bar, performance overlay) and testing (test browser window, result banner). Start here for what they share (decoupled observers of the Character API, the AI controller's debug getters and the EventBus), then load the matching `domain-ui-<name>` skill. Complements the `architecture` skill.
---

# UI domain (`scenes/ui/`) — overview

`CanvasLayer` / `Node` widgets, all built entirely in code (no scene-side layout), all decoupled observers
that read only published contracts — Character public API/signals, the AI controller's
`debug_status()` / `current_act()` and `goal_text()`, and the EventBus `&"hit"` topic. They know nothing of
the domains.

## Sub-domains (one folder, one skill each)

| Folder | Skill | Owns |
|---|---|---|
| `menus/` | `domain-ui-menus` | `setup_menu.gd` (pre-game window), `settings_menu.gd` (Debug + key rebinding) |
| `hud/` | `domain-ui-hud` | `debug_ui.gd`, `match_hud.gd`, `seed_display.gd`, `spectator_inspector.gd`, `contact_markers.gd` |
| `overlays/` | `domain-ui-overlays` | `overlay_registry.gd`, `overlay_toggles.gd`, `performance_overlay.gd`, `drag_handle.gd` |
| `testing/` | `domain-ui-testing` | `test_browser_window.gd`, `test_result_hud.gd` |

Load the matching sub-skill before editing a folder. What they share: every widget is built in code (no scene-side layout), takes plain
data or reads published contracts only, never reaches into another domain's internals, and runs `PROCESS_MODE_ALWAYS` when it must keep
working while the match is paused. There are no `class_name`s in this domain; callers `preload` the script by path.

## Interface recap

- UI observers attach by exported node path (or node name duck-typed in `main.gd`) and read only the
  Character public API/signals plus `AIController.current_act()` / `goal_text()` (interface 7 in the
  `architecture` skill). EventBus `&"hit"` is the only cross-domain event consumed here.
- `main.gd` and the Testing runner are the only outward callers (`MatchHUD.begin`, `SetupMenu.open`, `SeedDisplay.show_seed`,
  `OverlayToggles.setup`, …); each sub-skill lists the calls its folder receives.
