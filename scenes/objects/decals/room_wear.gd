extends Node2D

## One room's wear (Objects domain), built by WearFactory: the damage of a run-down room placed in the world, never in its
## repeating floor or wall tile, so no mark shows up twice. World-Gen says where wear gathers (a few clusters, each by a
## wall, a corner or a piece of furniture, seeded); this node decides what each cluster is: 1-3 floor marks round its
## centre that follow the room's floor (planks break along a plank row, tiles go missing on the tile grid, carpet wears
## bald, concrete cracks and takes oil) and, for a cluster by a wall, often a mark on that wall's free stretch (peeling
## plaster, a water stain, a hairline crack, a run of stapled cable). Drawn by two decal layers (decal_layer.gd): the floor
## marks on the floor's rung (`FloorWear`), the wall marks on the walls' (`WallWear`); built after the house's floors and
## walls, so each draws over them. One per room, so it is lit like that room's floor. Draw-only. Tuning:
## ObjectArtConfig.wear_*.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const DecalLayer = preload("res://scenes/objects/decals/decal_layer.gd")

var _floor_layer: Node2D  ## `FloorWear`: the floor marks.
var _wall_layer: Node2D  ## `WallWear`: the wall marks.


## Build the wear of the room `rect` (in the parent's space; this node sits at its corner) on the floor `floor_definition`
## (its `color` and `art_opts.pattern`) inside walls `wall_thickness` thick, one cluster per `clusters` entry
## (`{ pos, wall, seed }`: its centre and the free stretch of wall it is by, `[a, b]` or empty, in the parent's space); returns
## this node.
func setup(rect: Rect2, floor_definition: Dictionary, wall_thickness: float, clusters: Array) -> Node2D:
	position = rect.position
	_floor_layer = DecalLayer.new().setup("FloorWear", ObjectArtConfig.floor_z_index)
	_wall_layer = DecalLayer.new().setup("WallWear", DrawLayers.STANDING)
	add_child(_floor_layer)
	add_child(_wall_layer)
	var room := Rect2(Vector2.ZERO, rect.size)
	var inner := room.grow(-(wall_thickness * 0.5 + ObjectArtConfig.wear_inset))
	var pattern := String((floor_definition.get("art_opts", {}) as Dictionary).get("pattern", "planks"))
	var tone := ObjectArt.drawn_color(floor_definition.get("color", Color.GRAY))
	var placed: Array[Rect2] = []
	for cluster: Dictionary in clusters:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(cluster.get("seed", 0))
		var at: Vector2 = (cluster["pos"] as Vector2) - rect.position
		if ObjectArtConfig.wear_floor_kinds.has(pattern) and inner.size.x >= 40.0 and inner.size.y >= 40.0:
			_floor_marks(rng, at, inner, pattern, tone, placed)
		var wall: Array = cluster.get("wall", [])
		if wall.size() == 2 and rng.randf() < ObjectArtConfig.wear_wall_chance:
			_wall_mark(rng, (wall[0] as Vector2) - rect.position, (wall[1] as Vector2) - rect.position, at, wall_thickness)
	return self


## The layer drawing the floor marks.
func floor_layer() -> Node2D:
	return _floor_layer


## The layer drawing the wall marks.
func wall_layer() -> Node2D:
	return _wall_layer


## An entry of a `[[value, weight], ...]` table, drawn by weight.
static func pick(rng: RandomNumberGenerator, table: Array) -> Variant:
	var total := 0.0
	for row: Array in table:
		total += float(row[1])
	var roll := rng.randf() * total
	for row: Array in table:
		roll -= float(row[1])
		if roll <= 0.0:
			return row[0]
	return table[-1][0]


# --- Floor ---------------------------------------------------------------------------------------------------------

## 1-3 marks of the floor `pattern` round `at`, inside `inner`, clear of the marks already `placed`.
func _floor_marks(rng: RandomNumberGenerator, at: Vector2, inner: Rect2, pattern: String, tone: Color, placed: Array[Rect2]) -> void:
	var marks := 1 if rng.randf() < ObjectArtConfig.wear_one_chance else (2 if rng.randf() < ObjectArtConfig.wear_two_chance else 3)
	for m in marks:
		var spread := ObjectArtConfig.wear_spread
		var offset := Vector2.ZERO if m == 0 else Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(spread.x, spread.y)
		var kind: String = pick(rng, ObjectArtConfig.wear_floor_kinds[pattern])
		var mark := _floor_mark(kind, at + offset, pattern, rng)
		if mark.is_empty():
			continue
		var r := _fit(mark["rect"], inner, mark["step"])
		if not inner.encloses(r) or placed.any(func(q: Rect2) -> bool: return q.grow(ObjectArtConfig.wear_gap).intersects(r)):
			continue
		placed.append(r)
		var opts: Dictionary = mark["opts"]
		opts["kind"] = kind
		opts["v"] = rng.randi_range(0, ObjectArtConfig.wear_variants - 1)
		_floor_layer.add(ObjectArt.texture("wear", r.size, tone, mark["facing"], "", opts), r)


## A floor mark of `kind` near `p` on a floor of `pattern` whose tile starts at this node's origin: `{ rect, step, facing,
## opts }` (the rect, how it may be moved to fit (whole rows or cells for a grid-bound mark, a pixel for a free one), the
## turn its art is drawn at, the painter's grid options), or `{}` for a kind it does not know.
static func _floor_mark(kind: String, p: Vector2, pattern: String, rng: RandomNumberGenerator) -> Dictionary:
	var px := ArtConfig.pixel_size
	match kind:
		"plank_gap":
			var row_h := maxi(3, roundi(ObjectArtConfig.floor_plank_px / px))
			var rows := 1 if rng.randf() < 0.7 else 2
			var length := roundf(rng.randf_range(20, 56) / px)
			var row := floori(p.y / (row_h * px))
			var r := Rect2(roundf(p.x / px - length * 0.5) * px, (row * row_h + 1) * px, length * px, (rows * row_h - 1) * px)
			return { "rect": r, "step": Vector2(px, row_h * px), "facing": Vector2.DOWN, "opts": { "row_h": row_h, "rows": rows } }
		"strip_gap":
			# Parquet: one strip of a basket-weave square (strips across in one square, along in the next), or two side by side.
			var cell := ObjectArtConfig.floor_parquet_px / px
			var strip := maxi(2, int(cell / 4.0))
			var g := Vector2i(floori(p.x / (cell * px)), floori(p.y / (cell * px)))
			var s := rng.randi_range(0, int(cell / strip) - 1)
			var n := 1 if rng.randf() < 0.6 or s == int(cell / strip) - 1 else 2
			var cell_o := Vector2(g) * cell * px
			var r := Rect2(cell_o + Vector2(0, s * strip * px), Vector2(cell, strip * n) * px) if (g.x + g.y) % 2 == 0 \
					else Rect2(cell_o + Vector2(s * strip * px, 0), Vector2(strip * n, cell) * px)
			return { "rect": r, "step": Vector2(cell, cell) * px, "facing": Vector2.DOWN, "opts": {} }
		"missing_cells":
			var cell := maxi(3, roundi(ObjectArtConfig.floor_mosaic_px / px)) if pattern == "mosaic" \
					else maxi(4, roundi(ObjectArtConfig.floor_tile_px / px))
			var most := 3 if pattern == "mosaic" else 2
			var n := Vector2i(rng.randi_range(1, most), rng.randi_range(1, most))
			var g := Vector2i(floori(p.x / (cell * px)), floori(p.y / (cell * px)))
			var r := Rect2(Vector2(g * cell) * px, Vector2(n * cell + Vector2i.ONE) * px)
			return { "rect": r, "step": Vector2(cell, cell) * px, "facing": Vector2.DOWN, "opts": { "cell": cell, "nx": n.x, "ny": n.y } }
	if not ObjectArtConfig.wear_sizes.has(kind):
		return {}
	var lo: Vector2 = ObjectArtConfig.wear_sizes[kind][0]
	var hi: Vector2 = ObjectArtConfig.wear_sizes[kind][1]
	var size := (Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y)) / 2.0).round() * 2.0
	var turned := rng.randf() < 0.5
	var foot := Vector2(size.y, size.x) if turned else size
	var facing: Vector2 = [Vector2.LEFT, Vector2.RIGHT][rng.randi_range(0, 1)] if turned else [Vector2.DOWN, Vector2.UP][rng.randi_range(0, 1)]
	return { "rect": Rect2(((p - foot * 0.5) / px).round() * px, foot), "step": Vector2(px, px), "facing": facing, "opts": {} }


## `r` moved inside `inner` in whole `step`s (a grid-bound mark keeps to its grid), as far as it fits.
static func _fit(r: Rect2, inner: Rect2, step: Vector2) -> Rect2:
	var shift := Vector2.ZERO
	for axis in 2:
		if r.position[axis] < inner.position[axis]:
			shift[axis] = ceilf((inner.position[axis] - r.position[axis]) / step[axis]) * step[axis]
		elif r.end[axis] > inner.end[axis]:
			shift[axis] = -ceilf((r.end[axis] - inner.end[axis]) / step[axis]) * step[axis]
	return Rect2(r.position + shift, r.size)


# --- Wall ----------------------------------------------------------------------------------------------------------

## One wall mark on the stretch `a`-`b` (the wall's centre line, this node's frame) `thickness` thick, as near `at`'s
## place along it as it fits.
func _wall_mark(rng: RandomNumberGenerator, from: Vector2, to: Vector2, at: Vector2, thickness: float) -> void:
	var a := from.min(to)  # A wall runs along x or y: walk it from its lower end.
	var b := from.max(to)
	var length := a.distance_to(b)
	var kind: String = pick(rng, ObjectArtConfig.wear_wall_kinds)
	var span: Vector2 = ObjectArtConfig.wear_wall_lengths[kind]
	var mark := roundf(minf(rng.randf_range(span.x, span.y), length - 8.0))
	if mark < span.x:
		return
	var dir := (b - a) / length
	var s := roundf(clampf((at - a).dot(dir) - mark * 0.5, 4.0, length - 4.0 - mark))
	var opts := { "kind": kind, "v": rng.randi_range(0, ObjectArtConfig.wear_variants - 1) }
	var r: Rect2
	var facing := Vector2.DOWN
	if absf(dir.x) > 0.5:
		r = Rect2(a + dir * s - Vector2(0, thickness * 0.5), Vector2(mark, thickness))
	else:
		r = Rect2(a + dir * s - Vector2(thickness * 0.5, 0), Vector2(thickness, mark))
		facing = Vector2.RIGHT  # The art runs along its canvas's length, turned onto the wall.
	_wall_layer.add(ObjectArt.texture("wear", r.size, ObjectArtConfig.wear_plaster_color, facing, "", opts), r)
