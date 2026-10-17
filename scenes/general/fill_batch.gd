class_name FillBatch
extends RefCounted

## General domain: plain-coloured shapes drawn on a canvas item as ONE triangle array (`flush`) instead of one polygon or
## circle command each, shared infrastructure (like `DrawLayers`) for any domain that draws many of them every frame.
## Rendering windowed, the engine builds a vertex buffer for every polygon command (`draw_colored_polygon`, `draw_circle`),
## about 9 µs each against a fifth of one for a rect: a body's limbs and shadow, a blood splat's outlines, a chunk of resting
## chips. A batch cuts each polygon into the triangles the engine itself would (`Geometry2D.triangulate_polygon`) and a circle into
## the 64-gon `draw_circle` draws (point `i` at angle `i * TAU / 64`; fanned from its first corner, which covers the same pixels as
## any cut of a convex polygon), and draws them all in the order they were added: the same shapes, so the same pixels. A batch
## is drawn at the canvas item's draw transform at `flush`: shapes added under different transforms are placed by the caller
## (`xform`).
## Under the headless display (`batching` false) nothing is rendered, a command costs no vertex buffer and building the array
## would cost more than the commands it replaces: there a batch hands each shape to its canvas as it is added.

## Whether shapes are gathered into one triangle array (else each is drawn by its own command as it is added): not under the
## headless display, whose renderer draws nothing.
static var batching := DisplayServer.get_name() != "headless"
## The corners of `draw_circle`'s 64-gon round the unit circle, from angle 0.
static var _UNIT_CIRCLE := _circle_points()
## A fan (corner 0 with each pair of neighbours) of `n` corners numbered from a first index, by Vector2i(first index, n): the
## 64-gon's, and those of `fill_convex`.
static var _fans := {}

var _canvas: CanvasItem  ## The canvas item the batch draws on.
## The draw transform the caller has set on the canvas (`draw_set_transform_matrix`), put back after a shape drawn on its own
## under its `xform`.
var _base: Transform2D
var _points := PackedVector2Array()  ## The corners of every shape added since the last `flush` (canvas px).
var _colors := PackedColorArray()  ## Each corner's colour, by `_points` index.
var _indices := PackedInt32Array()  ## The triangles to draw, three `_points` indices each, in the order added.


## A batch drawn on `canvas`, whose draw transform the caller has set to `base` (if any).
func _init(canvas: CanvasItem, base := Transform2D.IDENTITY) -> void:
	_canvas = canvas
	_base = base


## Add `poly` (canvas px) in `color`, moved by `xform` first. A polygon the engine cannot cut into triangles is drawn on its own,
## after what was added before it, so it is reported as `draw_colored_polygon` reports it.
func fill(poly: PackedVector2Array, color: Color, xform := Transform2D.IDENTITY) -> void:
	var placed := poly if xform == Transform2D.IDENTITY else xform * poly
	if not batching:
		_canvas.draw_colored_polygon(placed, color)
		return
	var tris := Geometry2D.triangulate_polygon(placed)
	if tris.is_empty():
		flush()
		_canvas.draw_colored_polygon(placed, color)
		return
	_add(placed, tris, color)


## Add `poly` (canvas px), which the caller knows to be CONVEX, in `color`, moved by `xform` first: fanned from its first corner,
## which covers the same pixels as the engine's cut of it (any cut of a convex polygon does), without cutting it.
func fill_convex(poly: PackedVector2Array, color: Color, xform := Transform2D.IDENTITY) -> void:
	var placed := poly if xform == Transform2D.IDENTITY else xform * poly
	if not batching:
		_canvas.draw_colored_polygon(placed, color)
		return
	_add_fan(placed, color)


## Add the disc `draw_circle(center, radius, color)` draws, moved by `xform` first.
func circle(center: Vector2, radius: float, color: Color, xform := Transform2D.IDENTITY) -> void:
	if not batching:
		if xform == Transform2D.IDENTITY:
			_canvas.draw_circle(center, radius, color)
		else:  # the canvas's own polygon command would cut the 64-gon: the disc command, placed by the transform
			_canvas.draw_set_transform_matrix(_base * xform)
			_canvas.draw_circle(center, radius, color)
			_canvas.draw_set_transform_matrix(_base)
		return
	_add_fan(xform * Transform2D(0.0, Vector2(radius, radius), 0.0, center) * _UNIT_CIRCLE, color)


## Add the convex `placed` (canvas px) in `color` as a fan from its first corner (`_fans`).
func _add_fan(placed: PackedVector2Array, color: Color) -> void:
	var base := _points.size()
	var n := placed.size()
	var key := Vector2i(base, n)
	var fan: Variant = _fans.get(key)
	if fan == null:
		var made := PackedInt32Array()
		for i in range(1, n - 1):
			made.append_array([base, base + i, base + i + 1])
		_fans[key] = made
		fan = made
	_indices.append_array(fan)
	_points.append_array(placed)
	var tint := PackedColorArray()
	tint.resize(n)
	tint.fill(color)
	_colors.append_array(tint)


## Whether nothing is waiting to be drawn.
func is_empty() -> bool:
	return _indices.is_empty()


## Draw what was added on the canvas, at its current draw transform, and start again.
func flush() -> void:
	if _indices.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(_canvas.get_canvas_item(), _indices, _points, _colors)
	_points = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()


## Add `placed` (canvas px) in `color`, cut into `tris` (its triangles, three indices into it each).
func _add(placed: PackedVector2Array, tris: PackedInt32Array, color: Color) -> void:
	var base := _points.size()
	for i in tris:
		_indices.append(base + i)
	_points.append_array(placed)
	var tint := PackedColorArray()
	tint.resize(placed.size())
	tint.fill(color)
	_colors.append_array(tint)


## The 64 corners of `draw_circle`'s polygon round the unit circle, point `i` at angle `i * TAU / 64`.
static func _circle_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 64:
		var angle := TAU * i / 64.0
		out.append(Vector2(cos(angle), sin(angle)))
	return out
