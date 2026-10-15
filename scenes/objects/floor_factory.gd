class_name FloorFactory

## Objects-domain factory: turns a room rect + a floor DEFINITION (a plain data dict from World-Gen's
## catalogue: `art`, `color`, `material`, `art_opts`, and optionally `sound_surface` (false: registers no SoundSurface, so
## footsteps on it sound like the open ground: the street), `marks` (world-placed marks laid over it: the street's
## `{ seed, lane, edges }`, see street_marks.gd) and `tile_from` (a point in `parent`'s space the repeating tile's grid is laid
## from, so neighbouring pieces share one grid; default the floor's own corner)) into a runtime Floor entity. World-Gen
## never touches the Floor's fields directly.

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
	node.sound_surface = definition.get("sound_surface", true)
	node.marks = definition.get("marks", {})
	node.tile_offset = rect.position - (definition.get("tile_from", rect.position) as Vector2)
	node.light_layer = definition.get("light_layer", "")

	var visuals := Node2D.new()
	visuals.name = "FloorVisuals"
	visuals.script = FloorVisualsScript
	node.add_child(visuals)

	parent.add_child(node)
	return node
