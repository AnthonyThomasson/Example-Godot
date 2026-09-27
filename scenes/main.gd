extends Node2D

## Top-down demo scene. A placeholder circle (Player) moves with WASD and collides
## with the square Room. See player.gd and room.gd for the details.

func _ready() -> void:
	_spawn_objects()

func _spawn_objects() -> void:
	var objects_container := $ObjectsContainer
	var room_right := $Room.position.x + 300 + 50
	var start_pos := Vector2(room_right, 150)
	var cols := 4
	var spacing_x := 140.0
	var spacing_y := 140.0

	var keys := ObjectDefinitions.get_all()
	for i in range(keys.size()):
		var col := i % cols
		var row := i / cols
		var pos := start_pos + Vector2(col * spacing_x, row * spacing_y)
		ObjectSpawner.spawn(keys[i], pos, objects_container)
