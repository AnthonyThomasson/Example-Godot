extends Node2D

## Navigation domain: an optional, draw-only debug overlay for the baked navigation map. It draws the
## furniture HOLES carved out of the navmesh — the grown solid-furniture footprints the bake added as
## obstructions, so paths route around them. The holes are a STATIC snapshot taken right after the bake
## (via `NavBuilder.furniture_holes`), matching the navmesh exactly: like the baked holes, they do NOT
## follow a piece that is later shoved off its spot (that piece gets no dynamic avoidance — the NPC
## bulldozes it). A single world-space node (the map is global, not per-NPC): Main builds it once after
## baking. It reads nothing back and feeds nothing in. Toggle with `show_holes`.

## Whether to draw the furniture-hole overlay at all. Off by default.
@export var show_holes: bool = false
## Fill colour of a carved hole.
@export var hole_color: Color = Color(1.0, 0.2, 0.2, 0.2)
## Outline colour of a carved hole.
@export var outline_color: Color = Color(1.0, 0.35, 0.35, 0.9)

## The carved holes, each a closed world-space polygon, snapshotted once at bake time.
var _holes: Array = []


## Capture the holes a bake of `house` carved, once, right after the bake (before any piece is shoved).
## Called by Main; the node sits at the world origin so the world-space polygons draw as-is.
func setup(house: Node2D) -> void:
	_holes = NavBuilder.furniture_holes(house)
	queue_redraw()


## Draw each carved hole as a filled polygon + outline. Nothing moves, so it only redraws on a toggle.
func _draw() -> void:
	if not show_holes:
		return
	for poly in _holes:
		if (poly as PackedVector2Array).size() < 3:
			continue
		draw_colored_polygon(poly, hole_color)
		draw_polyline(_closed(poly), outline_color, 1.5)


## A polygon with its first point repeated at the end, so draw_polyline closes the loop.
func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out


## Runtime toggle setter so Main (and the setup menu) can flip the overlay like the AI debug ones.
func set_show_holes(on: bool) -> void:
	show_holes = on
	queue_redraw()
