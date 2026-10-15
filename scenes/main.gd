extends Node2D

## Top-down demo scene and the game's composition root (with the test runner, the only code that
## knows every domain): it wires the domains together. On start it asks the World Generation domain (WorldGen.generate) for a
## procedurally furnished house just ahead of the player, front entrance first.

## Seed for the house layout; 0 = a new random seed each run, resolved to a concrete value at
## spawn so the whole run (house + NPC placement) reproduces from it. The seed is shown in the
## corner (SeedDisplay) and can be re-entered in the setup window to pin a layout you like.
@export var house_seed: int = 0
## Force a specific floorplan (a key in HouseDefinitions); "" = pick one at random.
@export var force_plan: String = ""
## Distance from the player to the front entrance's center, straight up the screen.
@export var entrance_distance: float = 70.0
## How many defender NPCs to drop into the house (0 = none). Raise it to exercise coordinated
## flanking from the defending side.
@export var defender_count: int = 1
## How many invader NPCs to spawn outside the house (0 = none). With more than one they start on
## different sides and flank a shared target (a pincer).
@export var invader_count: int = 1
## Distance (px) beyond the house's outer edge an invader starts at (inside the navmesh's outer band).
@export var invader_margin: float = 80.0
## Room (px) a defender is dropped with: its centre stays this far from every solid furniture footprint and
## twice this from anyone already placed. A body spawned inside a piece is ejected along with it, and the
## piece's momentum flings the character across the map.
@export var spawn_clearance: float = 20.0
## Spectator match mode: run as an AI-only contest (the defenders vs the invaders) with no human player —
## frees the Player and its HUD, frames every NPC, and shows the match HUD. Off = the normal player-driven scene.
@export var spectator_mode: bool = true
## Which side a human player takes when there is one ("defender" / "invader"). The player joins that
## side on top of its NPC count, carrying the side's loadout.
@export var player_side: StringName = &"defender"
## What the defenders (and a player defending) carry and wear: `{ weapon, magazine, spares, stuns, frags, outfit }`, anything
## missing = the `LoadoutConfig` default (a random gun with its own magazine and spares, no grenades, and
## `LoadoutConfig.default_outfit`'s plain clothes: a t-shirt, jeans and shoes).
@export var defender_loadout: Dictionary = {}
## What the invaders (and a player invading) carry and wear; same shape as `defender_loadout`. They come with a stun grenade
## and a frag grenade each, in a helmet, a shirt, a plate carrier with a steel III plate front and back, tactical pants
## and boots.
@export var invader_loadout: Dictionary = {
	"stuns": 1, "frags": 1,
	"outfit": {
		"head": &"helmet", "body": &"shirt", "vest": &"plate_carrier", "pants": &"tactical_pants", "feet": &"boots",
		"front_plate": &"steel_iii", "back_plate": &"steel_iii",
	},
}
## Endless run: seconds between a match ending and the next one starting.
@export var endless_delay: float = 5.0
## Endless run: seconds before an undecided match is called a draw, so a stalemate can't stall the run
## (0 = no limit).
@export var endless_time_limit: float = 180.0
## Master switch for the AI debug overlays: off = every overlay is hidden and the in-game toggle bar is
## not built. This export is the default; on a fresh launch the saved `Settings.debug` (the settings
## page's Debug checkbox) takes over, while a scripted restart keeps this value.
@export var debug_overlays: bool = true
## Initial state of the debug overlays. The authoritative set is `_overlay_flags` (one entry per row of
## `overlay_registry.gd`), seeded from these exports for the overlays they name, from the setup window on
## a fresh launch, and flipped live by the in-game toggle bar. Overlays without an export here start at
## their registry default.
## When false, the floating action-status label drawn above each NPC is hidden.
@export var show_agent_labels: bool = false
## When false, the navigation-path polyline drawn under each NPC is hidden.
@export var show_agent_paths: bool = false
## When false, the line-of-sight / awareness overlay drawn around each NPC is hidden.
@export var show_vision: bool = false
## When false, the tactical navigation-zone overlay drawn around each NPC is hidden.
@export var show_tactics: bool = false
## When false, the tactical room-zone overlay (each room tinted by how the NPC regards it) is hidden.
@export var show_room_zones: bool = false
## When false, the search-coverage overlay (room sample points a searcher is seeing / still to see) is hidden.
@export var show_search: bool = false
## When false, the navigation-hole overlay (the footprints of furniture and characters at rest carved out of the navmesh) is hidden.
@export var show_nav_holes: bool = false

## NPC placement for one match (where defenders and invaders start; see match_spawner.gd).
const MATCH_SPAWNER := preload("res://scenes/match_spawner.gd")
## Faction tags the two NPC scenes carry (authored on the scenes); a human joining a side takes its tag
## so that side's NPCs treat them as an ally.
const DEFENDER_FACTION := &"household"
const INVADER_FACTION := &"invader"
## Draw-only overlay for the baked navmesh's holes, furniture and characters at rest (Navigation domain).
const NAV_DEBUG := preload("res://scenes/navigation/nav_debug.gd")
## Periodic navmesh re-baker: re-carves furniture holes as pieces are shoved around (Navigation domain).
const NAV_UPDATER := preload("res://scenes/navigation/nav_updater.gd")
## Spectator inspector (UI): Space-pause + click an NPC to show its tactical zones.
const SPECTATOR_INSPECTOR := preload("res://scenes/ui/hud/spectator_inspector.gd")
## The floor markers of the human's place in an AI stack (world space, under `World`).
const STACK_MARKERS := preload("res://scenes/ui/hud/stack_markers.gd")
const STUN_SCREEN := preload("res://scenes/ui/hud/stun_screen.gd")
## The overlay table (UI) and the in-game bar of toggle buttons built from it.
const OVERLAY_REGISTRY := preload("res://scenes/ui/overlays/overlay_registry.gd")
const OVERLAY_TOGGLES := preload("res://scenes/ui/overlays/overlay_toggles.gd")
## The test browser scene (Testing domain), opened from the setup window's Tests button.
const TEST_BROWSER := "res://scenes/testing/test_browser.tscn"
## The performance overlay (docks left of the toggle bar).
const PERFORMANCE_OVERLAY := preload("res://scenes/ui/overlays/performance_overlay.gd")
## The settings page (UI), opened over the setup window by its Settings button.
const SETTINGS_MENU := preload("res://scenes/ui/menus/settings_menu.gd")

## The human player (freed in a spectator match).
@onready var _player: Node2D = $Player
## Pre-game setup window (General). On a fresh launch Main opens it and waits for Start before building
## the world; a scripted restart skips it (see `_ready`).
@onready var _setup_menu: CanvasLayer = $SetupMenu
## Dev-only Von server launcher (AI). The match start waits on it so no NPC decides against a cold
## server; absent (or resolved to "none coming") it imposes no delay.
@onready var _von_launcher: Node = get_node_or_null("DecisionServerLauncher")

## Where the player stood in the scene: the house is placed relative to this point (its front entrance
## just above), and an invading human starts here.
var _anchor: Vector2 = Vector2.ZERO
## Everything one match builds (house, nav map, NPCs, inspector, and the blood / debris they leave) lives
## under this node, so an endless run clears a match by freeing it.
var _world: Node2D = null
## Endless run: on while the setup window's Endless button chose it.
var _endless: bool = false
## Endless run: the highest defender / invader counts a random match may draw (the counts chosen in setup).
var _endless_max := { "defenders": 1, "invaders": 1 }
## Endless run: seconds left until the next match (-1 while a match is being played).
var _next_match_in: float = -1.0
## Places this match's NPCs and keeps the list of them (`combatants`) — the spectator camera + match HUD observe it.
var _spawner: RefCounted = null
## Every debug overlay's on/off state, `{ show_<x>: bool }` keyed like `overlay_registry.gd`.
var _overlay_flags: Dictionary = {}
## The spectator inspector (spectator mode only), told of live toggles so the selected NPC follows them.
var _inspector: Node = null
## The world-space navigation-hole overlay, one of the two overlays that aren't per NPC.
var _nav_debug: Node2D = null
## The performance overlay (the other global overlay); null when Debug is off.
var _perf_overlay: CanvasLayer = null
## The overlay toggle bar (built once, kept across an endless run's matches); null when Debug is off.
var _overlay_toggles: Node = null
## The settings page while it is open over the setup window, else null.
var _settings_menu: CanvasLayer = null


func _ready() -> void:
	# The saved settings (key bindings, Debug) are layered over the defaults here, in the composition
	# root, so the headless test runner never reads a developer's file. The Debug export seeds the
	# setting first, so a file that doesn't name it leaves the export standing.
	Settings.debug = debug_overlays
	Settings.load_file()
	_overlay_flags = _initial_overlays()
	_anchor = _player.global_position
	var hud := get_node_or_null("MatchHUD")
	if hud and hud.has_signal("match_ended"):
		hud.match_ended.connect(_on_match_ended)
	# A scripted restart (the dev command server's `restart`) sets `skip_setup` so a reloaded scene
	# builds immediately — the headless match harness never clicks the setup window. A fresh launch
	# opens the window first and builds the world once the player presses Start.
	if Engine.has_meta("skip_setup") or _setup_menu == null:
		_spawn_world()
	else:
		# Hide the debug overlay while the setup menu is shown so it doesn't bleed through.
		var _debug_ui := get_node_or_null("DebugUI")
		if _debug_ui:
			_debug_ui.visible = false
		_setup_menu.start_requested.connect(_on_setup_chosen)
		_setup_menu.tests_requested.connect(_open_tests)
		_setup_menu.settings_requested.connect(_open_settings)
		# The exports are the defaults; what the player chose last time (kept in the settings file) wins.
		var defaults := {
			"side": str(player_side),
			"seed": house_seed,
			"defenders": _side_defaults(defender_count, defender_loadout),
			"invaders": _side_defaults(invader_count, invader_loadout),
		}
		_setup_menu.open(_with_saved_setup(defaults).merged({
			"weapons": LoadoutConfig.options(),
			"grenades": LoadoutConfig.grenade_options(),
			"outfits": LoadoutConfig.outfit_options(),
			"ticket": _ticket(),
		}))


## The name this run is tagged with: the `GAME_TICKET` env var (`tools/editor.sh` sets it to the worktree
## name), else a `--ticket=<name>` user arg, else the worktree's directory name when run from the editor;
## blank in an exported build. The setup window shows it at the top.
func _ticket() -> String:
	var ticket := OS.get_environment("GAME_TICKET")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ticket="):
			ticket = arg.trim_prefix("--ticket=")
	if ticket.strip_edges().is_empty() and OS.has_feature("editor"):
		ticket = ProjectSettings.globalize_path("res://").trim_suffix("/").get_file()
	return ticket.strip_edges()


## The setup window's `defaults` with what the player chose last time (kept in the settings file) over them, side by
## side: a choice an older save does not name (the grenade counts, the outfit) keeps its default.
func _with_saved_setup(defaults: Dictionary) -> Dictionary:
	var out := defaults.merged(Settings.setup, true)
	for side in ["defenders", "invaders"]:
		if defaults[side] is Dictionary and Settings.setup.get(side) is Dictionary:
			out[side] = defaults[side].merged(Settings.setup[side], true)
	return out


## A side's setup-window defaults: `{ count, weapon, magazine, spares, stuns, frags, outfit }` from its count and loadout.
func _side_defaults(count: int, loadout: Dictionary) -> Dictionary:
	var out := LoadoutConfig.normalize(loadout).merged({ "count": count })
	if out["spares"] < 0:
		out.erase("spares")  # unset: the window shows its own default
	return out


## Apply the parameters chosen in the setup window, then build the world. The window's `mode` is
## "play" (a human takes `side`), "watch" (the AIs alone: the spectator contest) or "endless" (watch,
## then a fresh randomised match after each one ends); anything but "play" has no human player.
func _on_setup_chosen(config: Dictionary) -> void:
	Settings.set_setup(config)
	var mode := str(config.get("mode", "play" if not spectator_mode else "watch"))
	spectator_mode = mode != "play"
	_endless = mode == "endless"
	player_side = StringName(config.get("side", player_side))
	house_seed = int(config.get("seed", house_seed))
	defender_count = int(_side_value(config.get("defenders"), "count", defender_count))
	invader_count = int(_side_value(config.get("invaders"), "count", invader_count))
	defender_loadout = _side_loadout(config.get("defenders"), defender_loadout)
	invader_loadout = _side_loadout(config.get("invaders"), invader_loadout)
	if _endless:
		if defender_count + invader_count == 0:
			defender_count = 1
			invader_count = 1  # nothing to watch otherwise
		_endless_max = { "defenders": defender_count, "invaders": invader_count }
	debug_overlays = Settings.debug
	_overlay_flags = _initial_overlays()  # Recomputed now that the master switch is chosen.
	# Hold the start until the decision server is live, so the NPCs' first decisions don't fail
	# against a booting server and leave them holding steady. The window stays up (showing why)
	# until then; this returns immediately when a server is already up or none is coming.
	await _await_decision_server()
	if not is_inside_tree():
		return  # Escape returned us to setup (reloading the scene) while we were waiting.
	_setup_menu.queue_free()
	var _debug_ui := get_node_or_null("DebugUI")
	if _debug_ui:
		_debug_ui.visible = true  # restored here; _setup_spectator frees it in spectator mode
	_spawn_world()


## One entry of a side's config (`{ count, weapon, … }`, or a bare count from an older caller), else `fallback`.
func _side_value(side: Variant, key: String, fallback: Variant) -> Variant:
	if side is Dictionary:
		return side.get(key, fallback)
	return side if key == "count" and side != null else fallback


## A side's loadout dict from its config entry, keeping `fallback` for what the entry doesn't name.
func _side_loadout(side: Variant, fallback: Dictionary) -> Dictionary:
	var out := fallback.duplicate()
	if side is Dictionary:
		for key in ["weapon", "magazine", "spares", "stuns", "frags", "outfit"]:
			if side.has(key):
				out[key] = side[key]
	return out


## Save the setup window's choices as they stand, if it is open, so leaving it without starting (to the
## test browser, or Escape reloading the scene) doesn't lose them.
func _remember_setup() -> void:
	if not is_instance_valid(_setup_menu) or _setup_menu.is_queued_for_deletion():
		return
	var config: Dictionary = _setup_menu.current_config()
	if not config.is_empty():  # empty = a scripted restart that never opened the window
		Settings.set_setup(config)


## The setup window's Tests button: leave for the test browser (Testing domain), which plays single
## game tests and returns here on Back.
func _open_tests() -> void:
	_remember_setup()
	get_tree().change_scene_to_file(TEST_BROWSER)


## The setup window's Settings button: open the settings page over it. The page only reports what the
## player changed; each change goes to `Settings` (which saves it) and the page's rows are redrawn from it.
func _open_settings() -> void:
	if _settings_menu != null:
		return
	_settings_menu = SETTINGS_MENU.new()
	add_child(_settings_menu)
	_settings_menu.debug_changed.connect(Settings.set_debug)
	_settings_menu.rebind_requested.connect(_on_rebind_requested)
	_settings_menu.reset_requested.connect(_on_reset_requested)
	_settings_menu.reset_all_requested.connect(_on_reset_all_requested)
	_settings_menu.back_requested.connect(_close_settings)
	_settings_menu.open({ "debug": Settings.debug, "rows": Settings.binding_rows() })


## The page captured a key or button for `action`: bind it and redraw the page.
func _on_rebind_requested(action: String, event: InputEvent) -> void:
	if Settings.rebind(action, event):
		_settings_menu.set_rows(Settings.binding_rows())


## The page reset one action: restore its default and redraw.
func _on_reset_requested(action: String) -> void:
	Settings.reset(action)
	_settings_menu.set_rows(Settings.binding_rows())


## The page reset every key: restore all defaults and redraw.
func _on_reset_all_requested() -> void:
	Settings.reset_all()
	_settings_menu.set_rows(Settings.binding_rows())


## Close the settings page, back to the setup window.
func _close_settings() -> void:
	_settings_menu.queue_free()
	_settings_menu = null


## Wait for the Von decision server to settle before the world is built. Returns at once when the
## launcher has already resolved — a reused server, or none coming (exported build, blank von_path,
## timeout) — so the usual case adds no delay at all. The launcher guarantees it always resolves, so
## this cannot stall the setup window indefinitely; a run without a server still starts, just with
## NPCs that hold steady.
func _await_decision_server() -> void:
	if _von_launcher == null or not _von_launcher.has_method("is_resolved") or _von_launcher.is_resolved():
		return
	if _setup_menu != null and _setup_menu.has_method("set_status"):
		_setup_menu.set_status("Waiting for the decision server…")
	var live: bool = await _von_launcher.resolved
	if not live:
		push_warning("Starting without a decision server — NPCs will hold steady until one answers.")


## Escape returns to the setup window to start a fresh match. Routed through Keybinds like all input,
## and handled here (not in a controller) so it works in both player and spectator mode — the dev
## command server's `menu` verb calls the same `return_to_setup()`.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(Keybinds.MENU) and not event.is_echo():
		return_to_setup()


## Reopen the pre-game setup window for a fresh match: drop the `skip_setup` and `match_seed` metas a
## scripted restart may have set (so the reloaded scene shows the window again and the window's own
## seed choice — not a stale pin — decides the layout) and reload the scene. Also the `menu` command verb.
func return_to_setup() -> void:
	_remember_setup()
	if Engine.has_meta("skip_setup"):
		Engine.remove_meta("skip_setup")
	if Engine.has_meta("match_seed"):
		Engine.remove_meta("match_seed")
	get_tree().reload_current_scene()


## Ask World-Gen for a house placed so its front entrance sits just above the player's anchor, and
## populate it. Everything is built under a fresh `World` node, so `_teardown_world` can clear the match.
func _spawn_world() -> void:
	# A dev/headless harness can pin the next match's layout via Engine meta (it survives the scene
	# reload the `restart` command does); otherwise the exported seed (0 = random) stands.
	if Engine.has_meta("match_seed"):
		house_seed = Engine.get_meta("match_seed")
	# Resolve 0 to a concrete seed here so the whole run (house AND NPC placement) is reproducible
	# from it, and so it can be displayed and re-entered to pin this layout.
	if house_seed == 0:
		house_seed = randi()
	var seed_display := get_node_or_null("SeedDisplay")
	if seed_display and seed_display.has_method("show_seed"):
		seed_display.show_seed(house_seed)
	_world = Node2D.new()
	_world.name = "World"
	_world.add_to_group(&"match_world")  # how the dev command server finds the match's nodes
	add_child(_world)
	_spawner = MATCH_SPAWNER.new()
	_spawner.world = _world
	_spawner.spawn_clearance = spawn_clearance
	_spawner.invader_margin = invader_margin
	var front_entrance := _anchor + Vector2(0, -entrance_distance)
	var house := WorldGen.generate(house_seed, force_plan, front_entrance, _world)
	# Bake the navigation map from the rooms + walls before the NPC starts pathing.
	var rooms := WorldGen.get_rooms(house)
	_spawner.openings = WorldGen.get_openings(house)
	var nav_region := NavBuilder.build(house, rooms, _world)
	# Debug overlay (world-space, single node): snapshot the holes carved into the navmesh right after the bake.
	# The updater below re-snapshots it after each re-bake so it tracks furniture and characters.
	var nav_debug: Node2D = NAV_DEBUG.new()
	nav_debug.name = "NavDebug"
	_world.add_child(nav_debug)
	nav_debug.setup(house)
	_nav_debug = nav_debug
	nav_debug.show_holes = _overlay_flags.get(OVERLAY_REGISTRY.NAV_HOLES, false)
	# Keep the navmesh in step with furniture that gets shoved around: re-carves the holes at the
	# pieces' current positions on an interval (and refreshes the overlay), so paths route around
	# scattered objects instead of their original spots.
	var nav_updater: Node = NAV_UPDATER.new()
	nav_updater.name = "NavUpdater"
	_world.add_child(nav_updater)
	nav_updater.setup(nav_region, house, rooms, nav_debug)
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed
	for i in defender_count:
		_spawner.spawn_defender(rooms, rng, i)
	for i in invader_count:
		_spawner.spawn_invader(rooms, rng, i, invader_count, front_entrance)
	var combatants: Array = _spawner.combatants.filter(func(c): return is_instance_valid(c))
	if not spectator_mode and is_instance_valid(_player):
		_join_player(rooms, rng)
		combatants.append(_player)
		_build_stack_markers(rooms)
		_build_stun_screen()
	_arm_characters(combatants)
	_configure_debug()
	_begin_match_hud(combatants)
	if spectator_mode:
		_setup_spectator(combatants)
	_build_overlays()


## Salt mixed into the house seed for the loadout draws, so picking guns never shifts the NPC placement
## that the house seed already pins ("LOAD").
const LOADOUT_SEED_SALT := 0x4C4F4144


## Arm the player (when there is one) and every NPC with their side's loadout (`defender_loadout` /
## `invader_loadout`): the chosen gun with its magazine and spares, or for "random" one gun drawn per
## character, and dress each in the side's outfit. Drawn from the house seed, so a pinned seed pins the random guns too. Tests and sandboxes
## build their own characters and never come through here, so they keep the weapon they ask for.
func _arm_characters(characters: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed ^ LOADOUT_SEED_SALT
	for character in characters:
		var defending: bool = character.get("faction") == DEFENDER_FACTION
		var gun := LoadoutConfig.apply(character, defender_loadout if defending else invader_loadout, rng)
		if gun != &"":
			GameLog.say("%s is armed with the %s" % [character.name, character.item_name()])


## Free the match built by `_spawn_world`: the whole `World` node (house, nav map, NPCs, inspector, and
## any blood / debris / casings they left) goes, and the bookkeeping that pointed into it is cleared.
## Removed from the tree at once (not just queued) so the next match's `World` takes the same name.
func _teardown_world() -> void:
	if is_instance_valid(_world):
		remove_child(_world)
		_world.queue_free()
	_world = null
	Sound.focus = null  # nobody's ears until the next match names the human
	_spawner = null
	_inspector = null
	_nav_debug = null


## Start the match HUD on `combatants` (every character in the match, a human included, so a result is
## shown whichever way the match is played). An endless run gives it a time limit; a match with a human
## in it shows only the timer and the result.
func _begin_match_hud(combatants: Array) -> void:
	var hud := get_node_or_null("MatchHUD")
	if hud and hud.has_method("begin"):
		hud.begin(combatants, endless_time_limit if _endless else 0.0, spectator_mode)


## Turn the scene into a pure AI spectator match: drop the human player and its player-HUD, point the
## camera at the NPCs, and add the Space-pause / click-to-inspect inspector. Composition-root wiring
## only — each observer reads the characters' public API/signals, never their internals.
func _setup_spectator(combatants: Array) -> void:
	var cam := get_node_or_null("MainCamera")
	if cam and cam.has_method("frame"):
		cam.frame(combatants)
	# Space pauses the match; a click selects one NPC (showing only its enabled overlays) and a click on
	# one of its tactical points shows that point's details. Spectator-only (in player mode Space is the
	# player's INTERACT), so it is wired here, not on a gameplay node. It is handed the same overlay
	# toggles the setup menu chose, and reveals exactly those on the clicked NPC.
	var inspector := SPECTATOR_INSPECTOR.new()
	inspector.name = "SpectatorInspector"
	_world.add_child(inspector)
	_inspector = inspector
	var npc_flags := _overlay_flags.duplicate()
	for flag in OVERLAY_REGISTRY.GLOBAL:  # global overlays, not per NPC
		npc_flags.erase(flag)
	inspector.setup(combatants, npc_flags, OVERLAY_TOGGLES.RESERVED_WIDTH)  # its outfit panel keeps clear of the bar's column
	var debug := get_node_or_null("DebugUI")
	if debug:
		debug.queue_free()
	if is_instance_valid(_player):
		_player.queue_free()


## Put the human in the match as a member of `player_side`: that side's faction (so its NPCs treat them
## as an ally) and a starting spot — a defender at a clear spot in a random room, an invader where the
## player stands in the scene (just outside the front entrance). Reparented under `World` so draw order
## stays house < player < NPCs.
func _join_player(rooms: Array, rng: RandomNumberGenerator) -> void:
	var defending := player_side == &"defender"
	_player.set("faction", DEFENDER_FACTION if defending else INVADER_FACTION)
	if defending and not rooms.is_empty():
		_player.global_position = _spawner.clear_spot(rooms[rng.randi() % rooms.size()]["rect"], rng)
	_player.reparent(_world, true)
	_world.move_child(_player, 1)  # just above the house (child 0), below the NPCs


## Give the human the stack radio and draw its place in an AI stack on the floor: the markers (a child of `World`, so
## world space) watch the stack the spawner attached to the player. Only a human invader is ever reserved a slot, since
## only the invaders' entries come over the radio.
func _build_stack_markers(rooms: Array) -> void:
	var stack: Node = _spawner.bind_player(_player, rooms)
	var markers: Node2D = STACK_MARKERS.new()
	markers.name = "StackMarkers"
	_world.add_child(markers)
	markers.watch(stack)


## The human's stun: the white-out of a flash (a `CanvasLayer` under `World`, watching the player) and, through
## `Sound.focus`, the muffle and tinnitus of a bang. Both read the player's `stun_view()`; neither knows of the other.
func _build_stun_screen() -> void:
	Sound.focus = _player
	var screen: CanvasLayer = STUN_SCREEN.new()
	_world.add_child(screen)
	screen.watch(_player)


## The performance overlay and the toggle bar, built the first time a match starts with Debug on and
## kept for the rest of an endless run.
func _build_overlays() -> void:
	if not debug_overlays or is_instance_valid(_overlay_toggles):
		return
	_perf_overlay = PERFORMANCE_OVERLAY.new()
	_perf_overlay.name = "PerformanceOverlay"
	add_child(_perf_overlay)
	_perf_overlay.set_shown(_overlay_flags.get(OVERLAY_REGISTRY.PERF, false))
	var toggles := OVERLAY_TOGGLES.new()
	toggles.name = "OverlayToggles"
	add_child(toggles)
	toggles.setup(_overlay_flags)
	toggles.overlay_toggled.connect(_on_overlay_toggled)
	_overlay_toggles = toggles


## The match HUD decided the match. In an endless run, start the countdown to the next one.
func _on_match_ended(_verdict: String) -> void:
	if _endless:
		_next_match_in = endless_delay


## Endless run: tick the countdown (Main is pausable, so pausing the match pauses it), then replace the
## finished match with a fresh randomised one.
func _process(delta: float) -> void:
	if _next_match_in < 0.0:
		return
	_next_match_in -= delta
	var hud := get_node_or_null("MatchHUD")
	if _next_match_in > 0.0:
		if hud:
			hud.set_countdown("Next match in %d...  (Esc to stop)" % ceili(_next_match_in))
		return
	_next_match_in = -1.0
	if hud:
		hud.set_countdown("")
	_teardown_world()
	_randomize_match()
	_spawn_world()


## Choose the next endless match's parameters: a new seed, each side's count drawn from 1..its setup
## count (a side set to 0 stays empty) and a random gun and outfit for each side, with the grenades it was set up with.
## Everything the player picked in the setup window is the upper limit; the rest is luck.
func _randomize_match() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	house_seed = 0
	defender_count = _random_count(rng, _endless_max["defenders"])
	invader_count = _random_count(rng, _endless_max["invaders"])
	defender_loadout = LoadoutConfig.random(rng).merged(LoadoutConfig.grenade_counts(defender_loadout))
	invader_loadout = LoadoutConfig.random(rng).merged(LoadoutConfig.grenade_counts(invader_loadout))


## A count drawn from 1..`most`, or 0 when `most` is 0.
func _random_count(rng: RandomNumberGenerator, most: int) -> int:
	return 0 if most <= 0 else rng.randi_range(1, most)


## The overlays' starting state: each registry default, overridden by the Main exports that name an
## overlay (labels / paths / vision / tactics / room zones / search / navigation holes).
func _initial_overlays() -> Dictionary:
	var flags: Dictionary = OVERLAY_REGISTRY.defaults()
	flags["show_actions"] = show_agent_labels
	flags["show_path"] = show_agent_paths
	flags["show_vision"] = show_vision
	flags["show_tactics"] = show_tactics
	flags["show_room_zones"] = show_room_zones
	flags["show_search"] = show_search
	flags[OVERLAY_REGISTRY.NAV_HOLES] = show_nav_holes
	for flag in Settings.overlays:  # the player's last toggles win over the exports
		if flags.has(flag):
			flags[flag] = Settings.overlays[flag]
	if not debug_overlays:
		for flag in flags:
			flags[flag] = false
	return flags


## Apply the current debug-overlay toggles to every spawned NPC. Duck-typed by property name so Main
## doesn't depend on the debug nodes' class or path — any NPC child with a matching `show_<x>` property
## gets that flag's value. (In spectator mode the inspector then shows them only on the selected NPC.)
func _configure_debug() -> void:
	if _spawner == null:
		return
	var flags := {}
	for flag in _overlay_flags:
		if not OVERLAY_REGISTRY.is_global(flag):
			flags[flag] = _overlay_flags[flag]
	for npc in _spawner.combatants:
		OVERLAY_REGISTRY.apply(npc, flags)


## A toggle-bar button was pressed: record the flag and apply it live. The navigation holes go to the single
## NavDebug node and the performance flag to the performance overlay; spectator mode hands the flag to the inspector (it shows overlays on the selected NPC
## only); in player mode every NPC's overlay takes it directly.
func _on_overlay_toggled(flag: String, on: bool) -> void:
	_overlay_flags[flag] = on
	Settings.set_overlay(flag, on)
	if flag == OVERLAY_REGISTRY.NAV_HOLES:
		if is_instance_valid(_nav_debug):
			_nav_debug.show_holes = on
			_nav_debug.queue_redraw()
	elif flag == OVERLAY_REGISTRY.PERF:
		if is_instance_valid(_perf_overlay):
			_perf_overlay.set_shown(on)
	elif _inspector != null and is_instance_valid(_inspector):
		_inspector.set_flag(flag, on)
	else:
		_configure_debug()
