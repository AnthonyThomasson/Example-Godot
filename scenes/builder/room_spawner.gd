class_name RoomSpawner

const RoomScript = preload("res://scenes/room/room.gd")
const RoomVisualsScript = preload("res://scenes/room/room_visuals.gd")

static func spawn(room_key: String, parent: Node) -> Node:
	var definition := RoomDefinitions.get_definition(room_key)
	if definition.is_empty():
		push_error("Unknown room type: ", room_key)
		return null
	return spawn_from(definition, room_key.capitalize(), parent)

## Build a room from a definition dict: `position`, `size` (Vector2), `wall_thickness`,
## `openings` (see room.gd).
static func spawn_from(definition: Dictionary, room_name: String, parent: Node) -> Node:
	var room := StaticBody2D.new()
	room.name = room_name
	room.position = definition["position"]
	room.script = RoomScript

	room.size = definition["size"]
	room.wall_thickness = definition["wall_thickness"]
	room.openings = definition.get("openings", [])

	var visuals := Node2D.new()
	visuals.name = "RoomVisuals"
	visuals.script = RoomVisualsScript
	room.add_child(visuals)

	parent.add_child(room)
	return room
