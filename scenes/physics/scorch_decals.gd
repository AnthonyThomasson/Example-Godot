class_name ScorchDecals
extends "res://scenes/physics/chunked_layer.gd"

## A layer of scorch marks (the black burn a frag leaves on the floor) under a world node, batching every mark so a floor
## full of them costs a few draw calls and no nodes of their own (`chunked_layer.gd`, as `DebrisLayer` and `BloodDecals`).
## A mark is stepped rows of `PhysicsConfig.explosion_pixel` px, ragged at the edge, a darker core inside a lighter rim, with
## a few specks flung out round it. Marks are grouped in `CHUNK`-px squares and only the chunk that gained or lost one
## redraws. The oldest are dropped past `Despawner.max_scene_objects`, the same bound every other kept mark answers to.
## Drawn at the blood decals' depth, under the furniture and the living.

const NODE_NAME := "ScorchDecals"
## The rim is this share of the core's alpha, and the core this share of the mark's radius.
const RIM_ALPHA := 0.55
const CORE_SHARE := 0.6
## Specks thrown round a mark.
const SPECKS := 7


## The scorch layer held by `parent`, or null if none yet.
static func find(parent: Node) -> ScorchDecals:
	return parent.get_node_or_null(NODE_NAME) as ScorchDecals


## The scorch layer under `parent` (the world node), made on first use. Each parent has its own layer, freed with it.
static func layer(parent: Node) -> ScorchDecals:
	return _get_or_make(parent, NODE_NAME, ScorchDecals, BloodConfig.print_z_index) as ScorchDecals


## Burn a mark of `radius` px at world `at`.
func burn(at: Vector2, radius: float) -> void:
	var step := maxf(PhysicsConfig.explosion_pixel, 1.0)
	var rects: Array[Rect2] = []
	var tones: Array[Color] = []
	var base := PhysicsConfig.scorch_color
	var rim := Color(base.r, base.g, base.b, base.a * RIM_ALPHA)
	var rows := int(ceil(radius / step))
	for j in range(-rows, rows):
		var y := (float(j) + 0.5) * step
		var edge := sqrt(maxf(radius * radius - y * y, 0.0)) * randf_range(0.78, 1.12)
		_row(rects, tones, at, j, step, edge, rim)
		var core := sqrt(maxf(pow(radius * CORE_SHARE, 2.0) - y * y, 0.0)) * randf_range(0.8, 1.1)
		_row(rects, tones, at, j, step, core, base)
	for _i in SPECKS:
		var spot := at + Vector2.from_angle(randf() * TAU) * radius * randf_range(0.9, 1.35)
		rects.append(Rect2((spot / step).floor() * step, Vector2(step, step)))
		tones.append(rim)
	# A mark: { chunk, rects (world), tones (the colour of each rect) }.
	_add({ "chunk": _chunk_cell(at), "rects": rects, "tones": tones }, Despawner.max_scene_objects)


## One row `j` (counted from the mark's centre) of a disc, `half` px each way from `at`, stepped to the pixel grid.
func _row(rects: Array[Rect2], tones: Array[Color], at: Vector2, j: int, step: float, half: float, tone: Color) -> void:
	var cells := roundi(half / step)
	if cells <= 0:
		return
	rects.append(Rect2(at + Vector2(-cells * step, j * step), Vector2(2.0 * cells * step, step)))
	tones.append(tone)


## A draw chunk for this layer's marks in `cell`.
func _make_chunk(cell: Vector2i) -> Node2D:
	var node := ScorchChunk.new()
	node.owner_layer = self
	node.cell = cell
	return node


## One chunk: draws the layer's marks whose centre falls in its cell.
class ScorchChunk:
	extends Node2D

	var owner_layer: ScorchDecals
	var cell := Vector2i.ZERO

	func _draw() -> void:
		draw_set_transform_matrix(global_transform.affine_inverse())  # marks are in world space
		for mark: Dictionary in owner_layer.marks_in(cell):
			var rects: Array[Rect2] = mark["rects"]
			var tones: Array[Color] = mark["tones"]
			for i in rects.size():
				draw_rect(rects[i], tones[i])
