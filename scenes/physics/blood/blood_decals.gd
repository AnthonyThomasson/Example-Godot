class_name BloodDecals
extends "res://scenes/physics/chunked_layer.gd"

## A layer of bloody footprints and smears under a world node, batching every print (a polygon) and
## ribbon (a smear's feathered, varying-width trail) so thousands of marks cost a few draw calls instead
## of thousands of nodes. Marks are grouped in `CHUNK`-px squares and only the chunk that gained a mark
## (or whose ribbon grew) redraws (`chunked_layer.gd`). They dry from `BloodConfig.color` to `dried_color` over
## `print_dry_time` (chunks holding wet marks redraw at `DRY_REDRAW` Hz), and the oldest are dropped past
## `BloodConfig.print_max`. Kept off the shared Despawner so a trail can't evict casings and splatters.

## Redraws per second of a chunk that still holds wet marks.
const DRY_REDRAW := 2.0
const NODE_NAME := "BloodDecals"


## The decal layer held by `parent`, or null if none yet.
static func find(parent: Node) -> BloodDecals:
	return parent.get_node_or_null(NODE_NAME) as BloodDecals


## The decal layer under `parent` (the node the marks' maker lives in, like a splatter's parent), made
## on first use. Each parent has its own layer, freed with it.
static func layer(parent: Node) -> BloodDecals:
	return _get_or_make(parent, NODE_NAME, BloodDecals, BloodConfig.print_z_index) as BloodDecals


## Add a filled polygon (world space) at `alpha` 0..1 of the blood colour.
func print_at(poly: PackedVector2Array, alpha: float) -> void:
	if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty():
		return  # the engine can't draw it; drop it rather than log an error
	var born := Engine.get_physics_frames()
	_add({ "kind": "print", "chunk": _chunk_cell(poly[0]), "born": born, "poly": poly, "alpha": alpha }, BloodConfig.print_max)


## Start a smear ribbon at world `point`: `width` px across and `alpha` 0..1 there. Grow it with
## `ribbon_extend`. Drawn as a feathered band whose width and opacity follow its samples. Returns the mark.
func ribbon_begin(point: Vector2, width: float, alpha: float) -> Dictionary:
	var mark := {
		"kind": "ribbon", "chunk": _chunk_cell(point), "born": Engine.get_physics_frames(), "alpha": 1.0,
		"points": PackedVector2Array([point]), "widths": PackedFloat32Array([width]),
		"alphas": PackedFloat32Array([alpha]),
	}
	_add(mark, BloodConfig.print_max)
	return mark


## Append a sample to ribbon `mark` (a width of 0 closes it to a point). Ignored once the mark was dropped.
func ribbon_extend(mark: Dictionary, point: Vector2, width: float, alpha: float) -> void:
	if mark.get("dead", false):
		return
	# Packed arrays are values: take each out, grow it, put it back.
	var points: PackedVector2Array = mark["points"]
	var widths: PackedFloat32Array = mark["widths"]
	var alphas: PackedFloat32Array = mark["alphas"]
	points.append(point)
	widths.append(width)
	alphas.append(alpha)
	mark["points"] = points
	mark["widths"] = widths
	mark["alphas"] = alphas
	if _chunks.has(mark["chunk"]):
		(_chunks[mark["chunk"]] as Node).queue_redraw()


## Number of footprints held.
func print_count() -> int:
	return _count("print")


## Number of smear ribbons held.
func ribbon_count() -> int:
	return _count("ribbon")


## The blood colour of mark `m` right now: dries toward dried_color, alpha scaled by the mark's own.
func color_of(m: Dictionary) -> Color:
	var seconds := BloodConfig.print_dry_time
	var dried := 1.0
	if seconds > 0.0:
		var age := float(Engine.get_physics_frames() - int(m["born"])) / float(Engine.physics_ticks_per_second)
		dried = clampf(age / seconds, 0.0, 1.0)
	var c: Color = BloodConfig.color.lerp(BloodConfig.dried_color, dried)
	c.a *= float(m["alpha"])
	return c


## How many held marks are of `kind` ("print" or "ribbon").
func _count(kind: String) -> int:
	var n := 0
	for m in _marks:
		if m["kind"] == kind:
			n += 1
	return n


## A draw chunk for this layer's marks in `cell`.
func _make_chunk(cell: Vector2i) -> Node2D:
	var node := DecalChunk.new()
	node.owner_layer = self
	node.cell = cell
	return node


## One chunk: draws the layer's marks that fall in its cell.
class DecalChunk:
	extends Node2D

	var owner_layer: BloodDecals
	var cell := Vector2i.ZERO
	var _since_redraw := 0.0

	func _process(delta: float) -> void:
		# Only wet marks change on their own (drying); a chunk of dry marks has nothing to redraw.
		_since_redraw += delta
		if _since_redraw >= 1.0 / BloodDecals.DRY_REDRAW and _has_drying():
			_since_redraw = 0.0
			queue_redraw()

	func _draw() -> void:
		draw_set_transform_matrix(global_transform.affine_inverse())  # marks are in world space
		for m in owner_layer.marks_in(cell):
			var color := owner_layer.color_of(m)
			if m["kind"] == "print":
				draw_colored_polygon(m["poly"], color)
			else:
				_draw_ribbon(m, color)

	## A ribbon as two quads per segment (each half of the band), solid along the centre line and
	## fading to `smear_feather` of that at the edges. Quads are drawn as raw triangles, so a sharp bend
	## or a pinched tail can never fail triangulation.
	func _draw_ribbon(m: Dictionary, color: Color) -> void:
		var pts: PackedVector2Array = m["points"]
		var widths: PackedFloat32Array = m["widths"]
		var alphas: PackedFloat32Array = m["alphas"]
		var n := pts.size()
		if n < 2:
			return
		var normals := PackedVector2Array()
		normals.resize(n)
		for i in n:
			var a := pts[maxi(i - 1, 0)]
			var b := pts[mini(i + 1, n - 1)]
			var tangent := b - a
			normals[i] = tangent.normalized().orthogonal() if tangent.length_squared() > 0.0001 else Vector2.ZERO
		var none := PackedVector2Array()
		for i in n - 1:
			if pts[i].distance_squared_to(pts[i + 1]) < 0.0001:
				continue
			var mid_a := Color(color.r, color.g, color.b, color.a * alphas[i])
			var mid_b := Color(color.r, color.g, color.b, color.a * alphas[i + 1])
			var edge_a := Color(color.r, color.g, color.b, mid_a.a * BloodConfig.smear_feather)
			var edge_b := Color(color.r, color.g, color.b, mid_b.a * BloodConfig.smear_feather)
			var la := pts[i] + normals[i] * widths[i] * 0.5
			var ra := pts[i] - normals[i] * widths[i] * 0.5
			var lb := pts[i + 1] + normals[i + 1] * widths[i + 1] * 0.5
			var rb := pts[i + 1] - normals[i + 1] * widths[i + 1] * 0.5
			draw_primitive(PackedVector2Array([la, pts[i], pts[i + 1], lb]), PackedColorArray([edge_a, mid_a, mid_b, edge_b]), none)
			draw_primitive(PackedVector2Array([pts[i], ra, rb, pts[i + 1]]), PackedColorArray([mid_a, edge_a, edge_b, mid_b]), none)

	## Whether any mark in this chunk is still drying, so it needs its periodic redraw.
	func _has_drying() -> bool:
		var seconds := BloodConfig.print_dry_time
		if seconds <= 0.0:
			return false
		var frames := seconds * Engine.physics_ticks_per_second
		for m in owner_layer.marks_in(cell):
			if Engine.get_physics_frames() - int(m["born"]) < frames:
				return true
		return false
