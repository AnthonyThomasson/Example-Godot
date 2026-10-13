class_name DebrisLayer
extends Node2D

## Physics System: the chips that have come to rest, drawn as one layer under a world node instead of one node each.
## A chip (`debris.gd`) is a node only while it flies; as it lands it hands its place, turn, colour, size and shape here
## and frees itself, so a floor strewn with a thousand chips costs a few draw calls and no nodes. Chips are grouped in
## `CHUNK`-px squares and only the chunk that gained or lost one redraws. The oldest are dropped past
## `Despawner.max_scene_objects`, the same bound the flying chips are tracked against, so the floor never accumulates
## chips without end. A layer draws under whatever is added to its node after it, as `BloodDecals` does.

## Side (px) of a chunk.
const CHUNK := 128.0
const NODE_NAME := "DebrisLayer"

## Every resting chip, oldest first: { chunk, at (world), turn (world radians), color, size, shape }.
var _chips: Array[Dictionary] = []
## chunk cell -> the chips drawn by that chunk.
var _by_chunk: Dictionary = {}
## chunk cell -> its drawing node.
var _chunks: Dictionary = {}


## The debris layer held by `parent`, or null if none yet.
static func find(parent: Node) -> DebrisLayer:
	return parent.get_node_or_null(NODE_NAME) as DebrisLayer


## The debris layer under `parent` (the node the chips were spawned in), made on first use. Each parent has its own
## layer, freed with it.
static func layer(parent: Node) -> DebrisLayer:
	var found := find(parent)
	if found != null:
		return found
	var made := DebrisLayer.new()
	made.name = NODE_NAME
	parent.add_child(made)
	return made


## Lay a chip to rest at world `at`, turned by `turn` (world radians): `size` px across, `shape` ("rect" | "tri" |
## "circle") in `color`, drawn exactly as the flying chip was.
func rest(at: Vector2, turn: float, color: Color, size: Vector2, shape: String) -> void:
	var cell := _chunk_cell(at)
	var chip := { "chunk": cell, "at": at, "turn": turn, "color": color, "size": size, "shape": shape }
	_chips.append(chip)
	if not _by_chunk.has(cell):
		_by_chunk[cell] = []
	(_by_chunk[cell] as Array).append(chip)
	_chunk_node(cell).queue_redraw()
	while _chips.size() > Despawner.max_scene_objects:
		var old: Dictionary = _chips.pop_front()
		var old_cell: Vector2i = old["chunk"]
		(_by_chunk[old_cell] as Array).erase(old)
		if _chunks.has(old_cell):
			(_chunks[old_cell] as Node).queue_redraw()


## Number of resting chips held.
func count() -> int:
	return _chips.size()


## Every resting chip (oldest first), for tests and tools.
func items() -> Array[Dictionary]:
	return _chips


## The chips chunk `cell` draws.
func chips_in(cell: Vector2i) -> Array:
	return _by_chunk.get(cell, [])


## The chunk grid cell containing world `pos`.
func _chunk_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CHUNK).floor())


## The draw chunk for `cell`, created on first use.
func _chunk_node(cell: Vector2i) -> Node2D:
	if not _chunks.has(cell):
		var node := DebrisChunk.new()
		node.owner_layer = self
		node.cell = cell
		add_child(node)
		_chunks[cell] = node
	return _chunks[cell]


## One chunk: draws the layer's chips that fall in its cell, each at its own place and turn.
class DebrisChunk:
	extends Node2D

	var owner_layer: DebrisLayer
	var cell := Vector2i.ZERO

	func _draw() -> void:
		var to_world := global_transform.affine_inverse()  # chips are placed in world space
		for chip in owner_layer.chips_in(cell):
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
