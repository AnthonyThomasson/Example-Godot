extends RefCounted

## UI domain: the ONE table of debug overlays — which toggle each is, how it is labelled and grouped, and
## whether it starts on (all start off). The in-game toggle bar (`overlay_toggles.gd`), the pre-game setup window
## (`setup_menu.gd`) and Main all read it, so adding an overlay is one row here plus its draw script.
##
## `flag` is the overlay node's `show_<x>` property name (found by duck-typed property, like Main's
## `_configure_debug` and the spectator inspector's `_flags`), except the GLOBAL flags (not per NPC):
## `show_nav_holes` (the navmesh furniture holes, applied to Main's single NavDebug node) and
## `show_perf` (the performance overlay).

## Flag of the world-space furniture-holes overlay.
const NAV_HOLES := "show_nav_holes"
## Flag of the performance overlay.
const PERF := "show_perf"
## Flags that belong to one global overlay rather than to every NPC.
const GLOBAL := [NAV_HOLES, PERF]

## `{ flag, label, group, default }` rows, in display order, grouped for the toggle bar.
const ENTRIES := [
	{ "flag": "show_vision", "label": "Vision cones", "group": "Perception", "default": false },
	{ "flag": "show_contacts", "label": "Contacts", "group": "Perception", "default": false },
	{ "flag": "show_hearing", "label": "Hearing & radio", "group": "Perception", "default": false },
	{ "flag": "show_room_zones", "label": "Room zones", "group": "Perception", "default": false },
	{ "flag": "show_search", "label": "Search coverage", "group": "Perception", "default": false },
	{ "flag": "show_tactics", "label": "Tactics zones", "group": "Combat", "default": false },
	{ "flag": "show_routes", "label": "Routes & exposure", "group": "Combat", "default": false },
	{ "flag": "show_combat", "label": "Combat state", "group": "Combat", "default": false },
	{ "flag": "show_territory", "label": "Territory", "group": "Combat", "default": false },
	{ "flag": "show_actions", "label": "Agent labels", "group": "Movement", "default": false },
	{ "flag": "show_path", "label": "Agent paths", "group": "Movement", "default": false },
	{ "flag": "show_targets", "label": "Move & use targets", "group": "Movement", "default": false },
	{ "flag": "show_stuck", "label": "Stuck detection", "group": "Movement", "default": false },
	{ "flag": "show_brain", "label": "Brain (Von)", "group": "Brain", "default": false },
	{ "flag": "show_entry", "label": "Entry plan", "group": "Entry", "default": false },
	{ "flag": "show_entry_team", "label": "Entry team & guard", "group": "Entry", "default": false },
	{ "flag": "show_nav_holes", "label": "Furniture holes", "group": "Map", "default": false },
	{ "flag": "show_perf", "label": "Performance", "group": "Stats", "default": false },
]


## Whether `flag` drives a single global overlay instead of each NPC's.
static func is_global(flag: String) -> bool:
	return GLOBAL.has(flag)


## Every flag's default, `{ flag: bool }`.
static func defaults() -> Dictionary:
	var out := {}
	for e in ENTRIES:
		out[e["flag"]] = e["default"]
	return out
