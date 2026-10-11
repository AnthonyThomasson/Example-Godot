class_name WallFactory

## Objects-domain factory: turns a plain rect + doorway openings into a runtime Wall entity
## (a StaticBody2D that builds its own colliders and is hittable/deformable). World-Gen
## calls this with geometry and an optional style dict — it never touches the Wall's fields.

const WallScript = preload("res://scenes/objects/wall/wall.gd")
const WallVisualsScript = preload("res://scenes/objects/wall/wall_visuals.gd")

## The doorways in `doors` (`{ pos, width }`, one point on a wall's centerline each) that lie on one of
## `rect`'s walls, as the `openings` array `spawn` takes. A door whose point is on no wall of `rect` is skipped.
static func openings_for(rect: Rect2, doors: Array) -> Array:
	var cut: Array = []
	for door in doors:
		var p: Vector2 = door["pos"]
		var width: float = door["width"]
		var within_x := p.x > rect.position.x and p.x < rect.end.x
		var within_y := p.y > rect.position.y and p.y < rect.end.y
		if within_x and is_equal_approx(p.y, rect.position.y):
			cut.append({ "side": WallScript.Side.TOP, "offset": p.x - rect.position.x, "width": width })
		elif within_x and is_equal_approx(p.y, rect.end.y):
			cut.append({ "side": WallScript.Side.BOTTOM, "offset": p.x - rect.position.x, "width": width })
		elif within_y and is_equal_approx(p.x, rect.position.x):
			cut.append({ "side": WallScript.Side.LEFT, "offset": p.y - rect.position.y, "width": width })
		elif within_y and is_equal_approx(p.x, rect.end.x):
			cut.append({ "side": WallScript.Side.RIGHT, "offset": p.y - rect.position.y, "width": width })
	return cut


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
