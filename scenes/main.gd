extends Node2D

## Top-down demo scene. On start, spawns a procedurally furnished house (see
## scenes/builder/house_spawner.gd) just ahead of the player, front door first.

## Seed for the house layout; 0 = a new random house every run. The seed used is
## printed at startup so a layout you like can be pinned here.
@export var house_seed: int = 0
## Distance from the player to the front door's center, straight up the screen.
@export var door_distance: float = 70.0

@onready var _player: Node2D = $Player


func _ready() -> void:
	_spawn_world()


func _spawn_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed if house_seed != 0 else randi()
	print("House seed: ", rng.seed)

	var front_door := _player.global_position + Vector2(0, -door_distance)
	var house := HouseSpawner.spawn("starter_home", front_door, rng, self)
	# Keep the house beneath the player in draw order.
	move_child(house, _player.get_index())
