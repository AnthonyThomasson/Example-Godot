class_name DebrisLayer
extends "res://scenes/physics/chunked_layer.gd"

## Physics System: the chips that have come to rest, drawn as one layer under a world node instead of one node each.
## A chip (`debris.gd`) is a node only while it flies; as it lands it hands its place, turn, colour, size and shape here
## and frees itself, so a floor strewn with a thousand chips costs a few draw calls and no nodes. Chips are grouped in
## `CHUNK`-px squares and only the chunk that gained or lost one redraws (`chunked_layer.gd`). The oldest are dropped past
## `Despawner.max_scene_objects`, the same bound the flying chips are tracked against, so the floor never accumulates
## chips without end. A layer draws under whatever is added to its node after it, as `BloodDecals` does.

const NODE_NAME := "DebrisLayer"


## The debris layer held by `parent`, or null if none yet.
static func find(parent: Node) -> DebrisLayer:
	return parent.get_node_or_null(NODE_NAME) as DebrisLayer


## The debris layer under `parent` (the node the chips were spawned in), made on first use. Each parent has its own
## layer, freed with it.
static func layer(parent: Node) -> DebrisLayer:
	return _get_or_make(parent, NODE_NAME, DebrisLayer) as DebrisLayer


## Lay a chip to rest at world `at`, turned by `turn` (world radians): `size` px across, `shape` ("rect" | "tri" |
## "circle") in `color`, drawn exactly as the flying chip was.
func rest(at: Vector2, turn: float, color: Color, size: Vector2, shape: String) -> void:
	var chip := { "chunk": _chunk_cell(at), "at": at, "turn": turn, "color": color, "size": size, "shape": shape }
	_add(chip, Despawner.max_scene_objects)


## A draw chunk for this layer's chips in `cell`.
func _make_chunk(cell: Vector2i) -> Node2D:
	var node := DebrisChunk.new()
	node.owner_layer = self
	node.cell = cell
	return node


## One chunk: draws the layer's chips that fall in its cell, each at its own place and turn.
class DebrisChunk:
	extends Node2D

	var owner_layer: DebrisLayer
	var cell := Vector2i.ZERO

	## Every chip in one triangle array (General's FillBatch), oldest first, each moved to its own place and turn: the
	## shapes `debris_visuals.gd` draws (its disc, triangle or rect, both convex so added uncut), the same pixels for a fraction
	## of the commands.
	func _draw() -> void:
		var to_world := global_transform.affine_inverse()  # chips are placed in world space
		if not FillBatch.batching:
			_draw_each(to_world)
			return
		var batch := FillBatch.new(self)
		for chip in owner_layer.marks_in(cell):
			var xform := to_world * Transform2D(chip["turn"], chip["at"])
			var color: Color = chip["color"]
			var s: Vector2 = chip["size"]
			match chip["shape"]:
				"circle":
					batch.circle(Vector2.ZERO, s.x * 0.5, color, xform)
				"tri":
					batch.fill_convex(PackedVector2Array([
						Vector2(0.0, -s.y * 0.5), Vector2(s.x * 0.5, s.y * 0.5), Vector2(-s.x * 0.5, s.y * 0.5)]), color, xform)
				_:  # "rect"
					var h := s * 0.5
					batch.fill_convex(PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y),
						Vector2(-h.x, h.y)]), color, xform)
		batch.flush()

	## Each chip by its own command, as the batch's would be under the headless display (nothing is rendered there, and these
	## cost the least).
	func _draw_each(to_world: Transform2D) -> void:
		for chip in owner_layer.marks_in(cell):
			draw_set_transform_matrix(to_world * Transform2D(chip["turn"], chip["at"]))
			var color: Color = chip["color"]
			var s: Vector2 = chip["size"]
			match chip["shape"]:
				"circle":
					draw_circle(Vector2.ZERO, s.x * 0.5, color)
				"tri":
					draw_colored_polygon(PackedVector2Array([
						Vector2(0.0, -s.y * 0.5), Vector2(s.x * 0.5, s.y * 0.5), Vector2(-s.x * 0.5, s.y * 0.5)]), color)
				_:  # "rect"
					draw_rect(Rect2(-s * 0.5, s), color)
