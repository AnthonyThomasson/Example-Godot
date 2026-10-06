extends Node2D

## Top-down demo scene and composition root: the one place that wires the domains
## together. On start it asks the World Generation domain (WorldGen.generate) for a
## procedurally furnished house just ahead of the player, front door first.

## Seed for the house layout; 0 = a new random house every run. The seed used is
## printed at startup so a layout you like can be pinned here.
@export var house_seed: int = 0
## Force a specific floorplan (a key in HouseDefinitions); "" = pick one at random.
@export var force_plan: String = ""
## Distance from the player to the front door's center, straight up the screen.
@export var door_distance: float = 70.0
## How many defender NPCs to drop into the house (0 = none). Raise it to exercise coordinated
## flanking from the defending side.
@export var defender_count: int = 1
## How many invader NPCs to spawn outside the house (0 = none). With more than one they start on
## different sides and flank a shared target (a pincer).
@export var invader_count: int = 1
## Distance (px) beyond the house's outer edge an invader starts at (inside the navmesh's outer band).
@export var invader_margin: float = 80.0
## Spectator match mode: run as a 2-AI contest (defender vs invader) with no human player — frees the
## Player and its HUD, frames both NPCs, and shows the match HUD. Off = the normal player-driven scene.
@export var spectator_mode: bool = true

## The house defender, dropped into one of the generated rooms.
const DEFENDER_SCENE := preload("res://scenes/character/npc_defender.tscn")
## The house invader, dropped just outside the house. Same AI, different data.
const INVADER_SCENE := preload("res://scenes/character/npc_invader.tscn")

@onready var _player: Node2D = $Player

## Every NPC spawned this run, in spawn order — the spectator camera + match HUD observe these.
var _combatants: Array = []


func _ready() -> void:
	_spawn_world()


## Ask World-Gen for a house placed so its front door sits just above the player.
func _spawn_world() -> void:
	# A dev/headless harness can pin the next match's layout via Engine meta (it survives the scene
	# reload the `restart` command does); otherwise the exported seed (0 = random) stands.
	if Engine.has_meta("match_seed"):
		house_seed = Engine.get_meta("match_seed")
	var front_door := _player.global_position + Vector2(0, -door_distance)
	var house := WorldGen.generate(house_seed, force_plan, front_door, self)
	# Keep the house beneath the player in draw order.
	move_child(house, _player.get_index())
	# Bake the navigation map from the rooms + walls before the NPC starts pathing.
	var rooms := WorldGen.get_rooms(house)
	NavBuilder.build(house, rooms, self)
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed if house_seed != 0 else randi()
	for i in defender_count:
		_spawn_defender(rooms, rng, i)
	for i in invader_count:
		_spawn_invader(rooms, rng, i, invader_count)
	if spectator_mode:
		_setup_spectator()


## Turn the scene into a pure 2-AI spectator match: drop the human player and its player-HUD, point
## the camera at both NPCs, and activate the match HUD. Composition-root wiring only — each observer
## reads the characters' public API/signals, never their internals.
func _setup_spectator() -> void:
	var combatants := _combatants.filter(func(c): return is_instance_valid(c))
	var cam := get_node_or_null("MainCamera")
	if cam and cam.has_method("frame"):
		cam.frame(combatants)
	var hud := get_node_or_null("MatchHUD")
	if hud and hud.has_method("begin"):
		hud.begin(combatants)
	var debug := get_node_or_null("DebugUI")
	if debug:
		debug.queue_free()
	if _player:
		_player.queue_free()


## Drop defender number `index` at the center of a random room. `rng` is seeded from `house_seed` so a
## pinned layout also pins the NPCs. Added after the house, so it draws above it. `rooms` is
## WorldGen.get_rooms(house), already fetched by the caller.
func _spawn_defender(rooms: Array, rng: RandomNumberGenerator, index: int) -> void:
	if rooms.is_empty():
		return
	var room: Dictionary = rooms[rng.randi() % rooms.size()]
	var rect: Rect2 = room["rect"]
	_add_npc(DEFENDER_SCENE, _npc_name("Defender", index), rect.position + rect.size * 0.5, rooms)


## Drop invader number `index` (of `count`) just outside the house (the rooms' bounding box),
## `invader_margin` px out. Invaders are spread evenly around the perimeter (one even fraction per
## index, plus a little jitter) so several attackers start on different sides and flank a shared
## target rather than stacking on one side.
func _spawn_invader(rooms: Array, rng: RandomNumberGenerator, index: int, count: int) -> void:
	if rooms.is_empty():
		return
	var bounds: Rect2 = rooms[0]["rect"]
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	bounds = bounds.grow(invader_margin)
	var frac := fposmod((index + 0.5) / maxi(count, 1) + rng.randf_range(-0.05, 0.05), 1.0)
	_add_npc(INVADER_SCENE, _npc_name("Invader", index), _perimeter_point(bounds, frac), rooms)


## A point at fraction `frac` (0..1, clockwise from the top-left) around the perimeter of `rect`.
func _perimeter_point(rect: Rect2, frac: float) -> Vector2:
	var d := frac * 4.0  # Four equal sides.
	if d < 1.0:
		return Vector2(lerpf(rect.position.x, rect.end.x, d), rect.position.y)          # top
	elif d < 2.0:
		return Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, d - 1.0))         # right
	elif d < 3.0:
		return Vector2(lerpf(rect.end.x, rect.position.x, d - 2.0), rect.end.y)         # bottom
	return Vector2(rect.position.x, lerpf(rect.end.y, rect.position.y, d - 3.0))        # left


## The node name for NPC `index` of a kind: the plain base for the first (so existing tooling that
## addresses "Defender"/"Invader" keeps working), then "<base> 2", "<base> 3", … for the rest.
func _npc_name(base: String, index: int) -> String:
	return base if index == 0 else "%s %d" % [base, index + 1]


## Instance an NPC scene named `npc_name` at `pos`, hand its controller the house's rooms, and record
## it as a combatant (for the spectator camera + match HUD).
func _add_npc(scene: PackedScene, npc_name: String, pos: Vector2, rooms: Array) -> void:
	var npc := scene.instantiate()
	npc.name = npc_name
	add_child(npc)
	npc.global_position = pos
	_bind_npc(npc, rooms)
	_combatants.append(npc)


## Wire an NPC's controller to the world: hand it the house's `rooms` (world-space rects), found by
## the same `control` duck-type the character uses to pick its controller — so Main doesn't depend on
## the controller's node name. This keeps the World-Gen boundary in Main: the AI never calls WorldGen
## itself. (The AI finds the characters it perceives on its own, by sight.)
func _bind_npc(npc: Node, rooms: Array) -> void:
	for child in npc.get_children():
		if child.has_method("control"):
			if "rooms" in child:
				child.rooms = rooms
			return
