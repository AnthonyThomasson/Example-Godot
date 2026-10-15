extends Node2D

## Physics System: the shared base of the batched decal layers (`DebrisLayer`, `ScorchDecals`, `BloodDecals`): one node under a
## world node holding every mark as plain data, drawn by a few chunk nodes instead of one node each. Marks are grouped in
## `CHUNK`-px squares and only the chunk that gained or lost one redraws; past a layer's cap the oldest is dropped (and
## flagged `dead`). A layer supplies its marks' recipe, its cap and its chunk node (`_make_chunk`), whose `_draw` reads
## `marks_in` its cell.

## Side (px) of a chunk.
const CHUNK := 128.0

## Every mark, oldest first: { chunk, ... } (the rest is the layer's recipe).
var _marks: Array[Dictionary] = []
## chunk cell -> the marks drawn by that chunk.
var _by_chunk: Dictionary = {}
## chunk cell -> its drawing node.
var _chunks: Dictionary = {}


## The layer named `node_name` under `parent`, made from `script` (at `z` z-index) on first use. Each parent has its own
## layer, freed with it.
static func _get_or_make(parent: Node, node_name: String, script: GDScript, z: int = 0) -> Node:
	var found := parent.get_node_or_null(node_name)
	if found != null:
		return found
	var made: Node2D = script.new()
	made.name = node_name
	made.z_index = z
	parent.add_child(made)
	return made


## Number of marks held.
func count() -> int:
	return _marks.size()


## Every mark still held (oldest first), for tests and tools.
func items() -> Array[Dictionary]:
	return _marks


## The marks chunk `cell` draws.
func marks_in(cell: Vector2i) -> Array:
	return _by_chunk.get(cell, [])


## File `mark` (its `chunk` cell already set) as the newest, redraw its chunk, and drop the oldest past `cap`.
func _add(mark: Dictionary, cap: int) -> void:
	_marks.append(mark)
	var cell: Vector2i = mark["chunk"]
	if not _by_chunk.has(cell):
		_by_chunk[cell] = []
	(_by_chunk[cell] as Array).append(mark)
	_chunk_node(cell).queue_redraw()
	while _marks.size() > cap:
		var old: Dictionary = _marks.pop_front()
		old["dead"] = true
		var old_cell: Vector2i = old["chunk"]
		(_by_chunk[old_cell] as Array).erase(old)
		if _chunks.has(old_cell):
			(_chunks[old_cell] as Node).queue_redraw()


## The chunk grid cell containing world `pos`.
func _chunk_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CHUNK).floor())


## The draw chunk for `cell`, created on first use.
func _chunk_node(cell: Vector2i) -> Node2D:
	if not _chunks.has(cell):
		var node := _make_chunk(cell)
		add_child(node)
		_chunks[cell] = node
	return _chunks[cell]


## A new, not yet added draw chunk for `_cell`; each layer returns its own.
func _make_chunk(_cell: Vector2i) -> Node2D:
	return Node2D.new()
