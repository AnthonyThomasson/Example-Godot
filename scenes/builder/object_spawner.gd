class_name ObjectSpawner

const EnvironmentObject = preload("res://scenes/objects/environment_object.gd")
const EnvironmentObjectVisuals = preload("res://scenes/objects/environment_object_visuals.gd")

## Spawn an object from its definition. `opts`:
##   rotated: bool  — swap the footprint's width/height (a 90° turn).
##   color: Color   — override the definition color (e.g. a room palette tone).
static func spawn(object_key: String, position: Vector2, parent: Node, opts: Dictionary = {}) -> Node:
	var definition := ObjectDefinitions.get_definition(object_key)
	if definition.is_empty():
		push_error("Unknown object type: ", object_key)
		return null

	var size: Vector2 = definition["size"]
	if opts.get("rotated", false):
		size = Vector2(size.y, size.x)
	var color: Color = opts.get("color", definition["color"])

	var obj := StaticBody2D.new()
	obj.name = object_key.capitalize()
	obj.position = position
	obj.script = EnvironmentObject

	obj.shape_type = definition["shape"]
	obj.object_name = definition["name"]
	obj.size = size
	obj.color = color
	obj.text_color = Color.BLACK if color.get_luminance() > 0.6 else Color.WHITE
	obj.solid = definition.get("solid", true)
	obj.object_material = definition.get("material", "")
	obj.coverage = definition.get("coverage", 0.0)
	obj.penetration = definition.get("penetration", 0.0)
	obj.weight = definition.get("weight", 10.0)

	var visuals := Node2D.new()
	visuals.name = "EnvironmentObjectVisuals"
	visuals.script = EnvironmentObjectVisuals
	obj.add_child(visuals)

	parent.add_child(obj, true)  # Readable unique names (Chair, Chair2, ...).
	return obj
