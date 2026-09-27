class_name RoomSpawner

const RoomScript = preload("res://scenes/room/room.gd")
const RoomVisualsScript = preload("res://scenes/room/room_visuals.gd")

static func spawn(room_key: String, parent: Node) -> Node:
	var definition := RoomDefinitions.get_definition(room_key)
	if definition.is_empty():
		push_error("Unknown room type: ", room_key)
		return null

	var room := StaticBody2D.new()
	room.name = room_key.capitalize()
	room.position = definition["position"]
	room.script = RoomScript

	room.size = definition["size"]
	room.wall_thickness = definition["wall_thickness"]
	room.opening_side = definition["opening_side"]
	room.opening_width = definition["opening_width"]

	var visuals := Node2D.new()
	visuals.name = "RoomVisuals"
	visuals.script = RoomVisualsScript
	room.add_child(visuals)

	parent.add_child(room)
	return room
