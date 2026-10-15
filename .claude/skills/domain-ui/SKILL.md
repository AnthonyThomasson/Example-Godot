---
name: domain-ui
description: Overview of the UI domain (scenes/ui/) — all HUDs and menus, split into four sub-domains by folder: menus (setup window, settings page), hud (debug panel, match HUD, seed label, spectator inspector), overlays (overlay registry, toggle bar, performance overlay) and testing (test browser window, result banner). Start here for what they share (decoupled observers of the Character API, the AI controller's debug getters and the EventBus), then load the matching `domain-ui-<name>` skill. Complements the `architecture` skill.
---

# UI domain (`scenes/ui/`) — overview

`CanvasLayer` / `Node` widgets, all built entirely in code (no scene-side layout), all decoupled observers
that read only these contracts — Character public API/signals, the AI controller's
`debug_zones()` and `known_contacts_for_display()`, the tactics overlay's `set_focus(point)` / `clear_focus()` (the spectator
inspector), `PlayerStack.view()` (the stack markers, interface 17), and the EventBus `&"hit"` and `&"stun"` topics. They know nothing else of
the domains.

## Sub-domains (one folder, one skill each)

| Folder | Skill | Owns |
|---|---|---|
| `menus/` | `domain-ui-menus` | `setup_menu.gd` (pre-game window), `settings_menu.gd` (Debug + key rebinding) |
| `hud/` | `domain-ui-hud` | `debug_ui.gd`, `match_hud.gd`, `spectator_inspector.gd`, `contact_markers.gd`, `stack_markers.gd`, `stun_screen.gd`, `outfit_lines.gd` |
| `overlays/` | `domain-ui-overlays` | `overlay_registry.gd`, `overlay_toggles.gd`, `performance_overlay.gd`, `drag_handle.gd` |
| `testing/` | `domain-ui-testing` | `test_browser_window.gd`, `test_result_hud.gd` |

Load the matching sub-skill before editing a folder. What they share: every widget is built in code (no scene-side layout), takes plain
data or reads published contracts only, never reaches into another domain's internals, and runs `PROCESS_MODE_ALWAYS` when it must keep
working while the match is paused. There are no `class_name`s in this domain; callers `preload` the script by path.
`main.gd` and the Testing runner are the only outward callers (`MatchHUD.begin`, `SetupMenu.open`,
`OverlayToggles.setup`, …); `main.gd` finds its HUD nodes by name (`get_node_or_null("MatchHUD")`, `"DebugUI"`)
and calls them duck-typed. Each sub-skill lists the calls its folder receives.

**Interfaces:** 7 (observers of the Character API and the AI controller), 10 (EventBus), 13 (Testing), 14 (settings page), 17 (stack markers), 18 (stun screen) — signatures in `architecture`.
