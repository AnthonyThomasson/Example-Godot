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

## Non-player character dropped into one of the generated rooms, driven by a decision model.
const NPC_SCENE := preload("res://scenes/character/npc.tscn")

@onready var _player: Node2D = $Player


func _ready() -> void:
	_spawn_world()


## Ask World-Gen for a house placed so its front door sits just above the player.
func _spawn_world() -> void:
	var front_door := _player.global_position + Vector2(0, -door_distance)
	var house := WorldGen.generate(house_seed, force_plan, front_door, self)
	# Keep the house beneath the player in draw order.
	move_child(house, _player.get_index())
	# Bake the navigation map from the rooms + walls before the NPC starts pathing.
	var rooms := WorldGen.get_rooms(house)
	NavBuilder.build(house, rooms, self)
	_spawn_npc(rooms)


## Drop one AI-driven NPC at the center of a random room and point its controller at the
## player. Seeded from `house_seed` so a pinned layout also pins the NPC's room. Added after the
## house, so it draws above it. `rooms` is WorldGen.get_rooms(house), already fetched by the caller.
func _spawn_npc(rooms: Array) -> void:
	if rooms.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed if house_seed != 0 else randi()
	var room: Dictionary = rooms[rng.randi() % rooms.size()]
	var rect: Rect2 = room["rect"]
	var npc := NPC_SCENE.instantiate()
	add_child(npc)
	npc.global_position = rect.position + rect.size * 0.5
	_aim_npc_at(npc, _player)


## Point an NPC's controller at `target`, found by the same `control` duck-type the character
## uses to pick its controller — so Main doesn't depend on the controller's node name. No-op if
## the controller takes no target (e.g. a controller that ignores it).
func _aim_npc_at(npc: Node, target: Node) -> void:
	for child in npc.get_children():
		if child.has_method("control"):
			if "target" in child:
				child.target = target
			return
