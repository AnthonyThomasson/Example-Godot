extends Node2D

## Top-down demo scene. A placeholder circle (Player) moves with WASD and collides
## with the square Room. See player.gd and room.gd for the details.

func _ready() -> void:
	_spawn_world()

func _spawn_world() -> void:
	var room: StaticBody2D = RoomSpawner.spawn("main_room", self)

	var objects_container: Node2D = $ObjectsContainer
	var room_right: float = room.position.x + 300 + 20
	var start_pos: Vector2 = Vector2(room_right, room.position.y - 150)
	var cols: int = 6
	var spacing_x: float = 100.0
	var spacing_y: float = 110.0

	var keys: Array = ObjectDefinitions.get_all()
	for i in range(keys.size()):
		var col: int = i % cols
		var row: int = i / cols
		var pos: Vector2 = start_pos + Vector2(col * spacing_x, row * spacing_y)
		ObjectSpawner.spawn(keys[i], pos, objects_container)
