class_name WallFactory

## Objects-domain factory: turns a plain rect + doorway openings into a runtime Wall entity
## (a StaticBody2D that builds its own colliders and is hittable/deformable). World-Gen
## calls this with geometry and an optional style dict — it never touches the Wall's fields.

const WallScript = preload("res://scenes/objects/wall/wall.gd")
const WallVisualsScript = preload("res://scenes/objects/wall/wall_visuals.gd")

## `rect` is the room's outline (walls run along its centerline); `openings` are doorways
## in Wall.Side format (see wall.gd). `style` is the cap's look: `art` (a tiling painter id),
## `color`, `art_opts`; empty = a flat gray line.
static func spawn(rect: Rect2, thickness: float, openings: Array, wall_name: String, parent: Node,
		style: Dictionary = {}) -> Node:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.position = rect.position
	wall.script = WallScript

	wall.size = rect.size
	wall.wall_thickness = thickness
	wall.openings = openings
	wall.art = style.get("art", "")
	wall.art_color = style.get("color", Color(0.6, 0.6, 0.6))
	wall.art_opts = style.get("art_opts", {})

	var visuals := Node2D.new()
	visuals.name = "WallVisuals"
	visuals.script = WallVisualsScript
	wall.add_child(visuals)

	parent.add_child(wall)
	return wall
