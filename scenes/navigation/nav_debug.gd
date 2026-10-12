extends Node2D

## Navigation domain: an optional, draw-only debug overlay for the baked navigation map. It draws the
## furniture HOLES carved out of the navmesh — the grown solid-furniture footprints the bake added as
## obstructions, so paths route around them — and, in another colour, the holes the characters at rest
## leave in the steering map. It snapshots the holes via `NavBuilder.furniture_holes`
## (in `setup`), so the drawing matches the navmesh exactly. The snapshot follows the furniture: Main
## builds this once after the initial bake, and `nav_updater.gd` calls `setup` again after each re-bake
## so the overlay re-snapshots at the pieces' current positions. A single world-space node (the map is
## global, not per-NPC). It reads nothing back and feeds nothing in. Toggle with `show_holes`.

## Whether to draw the hole overlay at all, furniture and characters at rest. Off by default.
@export var show_holes: bool = false
## Fill colour of a carved hole.
@export var hole_color: Color = Color(1.0, 0.2, 0.2, 0.2)
## Outline colour of a carved hole.
@export var outline_color: Color = Color(1.0, 0.35, 0.35, 0.9)
## Fill and outline colours of a hole a living character leaves in the steering map.
@export var character_hole_color: Color = Color(1.0, 0.7, 0.1, 0.2)
@export var character_outline_color: Color = Color(1.0, 0.8, 0.3, 0.9)

## The carved holes, each a closed world-space polygon, snapshotted once at bake time.
var _holes: Array = []
## The holes the characters at rest carve in the steering map (the node's parent is the world they stand in).
var _character_holes: Array = []


## Capture the holes a bake of `house` carved, at the furniture's and the characters' current positions. Called by Main
## right after the initial bake and again by `nav_updater.gd` after each re-bake, so the overlay stays
## matched to the live navmesh. The node sits at the world origin so the world-space polygons draw as-is.
func setup(house: Node2D) -> void:
	_holes = NavBuilder.furniture_holes(house)
	_character_holes = NavBuilder.character_holes(house.get_parent())
	queue_redraw()


## Draw each carved hole as a filled polygon + outline. Redraws on a toggle and whenever `setup`
## re-snapshots the holes (the initial bake, then each re-bake by nav_updater.gd).
func _draw() -> void:
	if not show_holes:
		return
	_draw_holes(_holes, hole_color, outline_color)
	_draw_holes(_character_holes, character_hole_color, character_outline_color)


## Fill and outline each polygon of `holes`.
func _draw_holes(holes: Array, fill: Color, outline: Color) -> void:
	for poly in holes:
		if (poly as PackedVector2Array).size() < 3:
			continue
		draw_colored_polygon(poly, fill)
		draw_polyline(_closed(poly), outline, 1.5)


## A polygon with its first point repeated at the end, so draw_polyline closes the loop.
func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out
