class_name ObjectSpawner

const EnvironmentObject = preload("res://scenes/objects/environment_object.gd")
const EnvironmentObjectVisuals = preload("res://scenes/objects/environment_object_visuals.gd")

static func spawn(object_key: String, position: Vector2, parent: Node) -> Node:
	var definition := ObjectDefinitions.get_definition(object_key)
	if definition.is_empty():
		push_error("Unknown object type: ", object_key)
		return null

	var obj := StaticBody2D.new()
	obj.name = object_key.capitalize()
	obj.position = position
	obj.script = EnvironmentObject

	obj.set_meta("shape_type", definition["shape"])
	obj.set_meta("object_name", definition["name"])
	obj.set_meta("size", definition["size"])
	obj.set_meta("color", definition["color"])
	obj.set_meta("text_color", Color(1, 1, 1, 1))

	obj.shape_type = definition["shape"]
	obj.object_name = definition["name"]
	obj.size = definition["size"]
	obj.color = definition["color"]
	obj.text_color = Color(1, 1, 1, 1)

	var visuals := Node2D.new()
	visuals.name = "EnvironmentObjectVisuals"
	visuals.script = EnvironmentObjectVisuals
	obj.add_child(visuals)

	parent.add_child(obj)
	return obj

static func spawn_all(parent: Node, start_position: Vector2, spacing: Vector2) -> Array:
	var objects := []
	var keys := ObjectDefinitions.get_all()

	for i in range(keys.size()):
		var pos := start_position + (spacing * i)
		var obj := spawn(keys[i], pos, parent)
		if obj:
			objects.append(obj)

	return objects
