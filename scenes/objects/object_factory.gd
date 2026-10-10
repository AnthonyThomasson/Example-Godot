class_name ObjectFactory

## Objects-domain factory: turns an object DEFINITION (a plain data dict, looked up by
## World-Gen from its catalogue) into a runtime EnvironmentObject node. Objects owns the
## field schema; World-Gen owns which objects exist. This keeps the two domains talking
## through a plain Dictionary, so neither reaches into the other's internals.
##
## Definition fields: name, shape ("circle"|"square"|"rect"), size, color (required);
##   material, coverage, penetration, weight, solid, interactions (all optional);
##   art (pixel-art painter id: "sofa"|"table"|"chair"; omitted = flat shape + label) and
##   art_opts (painter overrides, see ObjectArtConfig) (optional).
## `opts`:
##   name:    String  — node name (readable hit labels; defaults to the definition name).
##   rotated: bool    — swap the footprint's width/height (a 90° turn).
##   color:   Color   — override the definition color (e.g. a room palette tone).
##   facing:  Vector2 — which way the piece's front faces (cardinal; default DOWN). Orients art.

const EnvironmentObject = preload("res://scenes/objects/environment_object.gd")
const EnvironmentObjectVisuals = preload("res://scenes/objects/environment_object_visuals.gd")

## Build a runtime object from its definition and add it under `parent`. Returns the node.
static func spawn(definition: Dictionary, position: Vector2, parent: Node, opts: Dictionary = {}) -> Node:
	if definition.is_empty():
		push_error("ObjectFactory: empty definition")
		return null

	var size: Vector2 = definition["size"]
	if opts.get("rotated", false):
		size = Vector2(size.y, size.x)
	var color: Color = opts.get("color", definition["color"])

	var obj := RigidBody2D.new()
	obj.name = String(opts.get("name", definition.get("name", "Object"))).capitalize()
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
	obj.interactions = definition.get("interactions", [])
	obj.art = definition.get("art", "")
	obj.art_opts = definition.get("art_opts", {})
	obj.facing = opts.get("facing", Vector2.DOWN)

	var visuals := Node2D.new()
	visuals.name = "EnvironmentObjectVisuals"
	visuals.script = EnvironmentObjectVisuals
	obj.add_child(visuals)

	parent.add_child(obj, true)  # Readable unique names (Chair, Chair2, ...).
	return obj
