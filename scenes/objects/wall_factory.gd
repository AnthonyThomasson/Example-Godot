class_name WallFactory

## Objects-domain factory: turns a plain rect + door openings into a runtime Wall entity
## (a StaticBody2D that builds its own colliders and is hittable/deformable). World-Gen
## calls this with geometry only — it never touches the Wall's fields directly.

const WallScript = preload("res://scenes/objects/wall/wall.gd")
const WallVisualsScript = preload("res://scenes/objects/wall/wall_visuals.gd")

## `rect` is the room's outline (walls run along its centerline); `openings` are doorways
## in Wall.Side format (see wall.gd).
static func spawn(rect: Rect2, thickness: float, openings: Array, wall_name: String, parent: Node) -> Node:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.position = rect.position
	wall.script = WallScript

	wall.size = rect.size
	wall.wall_thickness = thickness
	wall.openings = openings

	var visuals := Node2D.new()
	visuals.name = "WallVisuals"
	visuals.script = WallVisualsScript
	wall.add_child(visuals)

	parent.add_child(wall)
	return wall
