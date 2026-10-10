class_name FloorFactory

## Objects-domain factory: turns a room rect + a floor DEFINITION (a plain data dict from World-Gen's
## catalogue: `art`, `color`, `material`, `art_opts`) into a runtime Floor entity. World-Gen never
## touches the Floor's fields directly.

const FloorScript = preload("res://scenes/objects/floor/floor.gd")
const FloorVisualsScript = preload("res://scenes/objects/floor/floor_visuals.gd")


## Build a floor covering `rect` (in `parent`'s space) under `parent`. Returns the node.
static func spawn(rect: Rect2, definition: Dictionary, floor_name: String, parent: Node) -> Node:
	var node := Node2D.new()
	node.name = floor_name
	node.position = rect.position
	node.script = FloorScript

	node.size = rect.size
	node.art = definition.get("art", "floor")
	node.color = definition.get("color", Color(0.6, 0.5, 0.4))
	node.floor_material = definition.get("material", "")
	node.art_opts = definition.get("art_opts", {})

	var visuals := Node2D.new()
	visuals.name = "FloorVisuals"
	visuals.script = FloorVisualsScript
	node.add_child(visuals)

	parent.add_child(node)
	return node
