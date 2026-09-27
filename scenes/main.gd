extends Node2D

## Top-down demo scene. On start, spawns a procedurally furnished house (see
## scenes/builder/house_spawner.gd) just ahead of the player, front door first.

## Seed for the house layout; 0 = a new random house every run. The seed used is
## printed at startup so a layout you like can be pinned here.
@export var house_seed: int = 0
## Force a specific floorplan (a key in HouseDefinitions); "" = pick one at random.
@export var force_plan: String = ""
## Distance from the player to the front door's center, straight up the screen.
@export var door_distance: float = 70.0

@onready var _player: Node2D = $Player

## Data on every object spawned in the house (material, coverage, penetration, ...).
var _inventory: BuildingInventory


func _ready() -> void:
	_spawn_world()


func _spawn_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed if house_seed != 0 else randi()
	var all_plans: Array = HouseDefinitions.get_all()
	var pick: String = all_plans[rng.randi() % all_plans.size()]
	var plan_key: String = force_plan if force_plan != "" else pick
	print("House: ", plan_key, "  seed: ", rng.seed)

	var front_door := _player.global_position + Vector2(0, -door_distance)
	var house := HouseSpawner.spawn(plan_key, front_door, rng, self)
	# Keep the house beneath the player in draw order.
	move_child(house, _player.get_index())

	# Record every spawned object's data (material/coverage/penetration) for the
	# penetration & coverage system. Stored on the house too, for other systems.
	_inventory = BuildingInventory.from_house(house)
	house.set_meta("inventory", _inventory)
	print("Building inventory: %d objects" % _inventory.size())
