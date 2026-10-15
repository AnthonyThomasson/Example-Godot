extends "res://scenes/objects/decals/decal_layer.gd"

## The marks laid over one piece of street (Objects domain): a Floor drawn by the street painter whose definition carries
## `marks` (`{ seed, lane, edges }`) gets this child of its visuals. The street's tiles carry only grain and slab joints, so
## everything with a shape lies here, each its own size, turn and detail, seeded: on a sidewalk the odd slab of another
## shade or with a broken corner (clustered on the slab grid), cracks, stains, gum and weeds, and its curb along `edges`
## (the sides facing the road); on a road the worn lane dashes down its middle (`lane`), cracks, patches and oil, and
## litter and puddles gathered in the gutter along `edges` (the sides by the sidewalk), the odd puddle out on the road.
## Draw-only, registers nothing. Tuning: ObjectArtConfig.street_*.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const RoomWear = preload("res://scenes/objects/decals/room_wear.gd")

const GUTTER := 14.0  ## Litter gathers within this many px of the curb.

var _size: Vector2  ## The street piece's size (px).
var _sidewalk := false  ## A sidewalk (else a road).
var _edges: Array = []  ## The sides (Vector2.UP …) the curb or gutter runs along.
var _litter: Array[Rect2] = []  ## The litter laid so far, so no two pieces overlap.


## Lay the marks of a street piece `size` px (the floor's `art_opts.kind` and `marks`; its tile grid starts `tile_offset` px
## into the tile at the floor's corner) as a child of `visuals`; returns this node.
func setup_marks(visuals: Node2D, size: Vector2, art_opts: Dictionary, marks: Dictionary, tile_offset: Vector2) -> Node2D:
	setup("StreetMarks", 0)
	_size = size
	_sidewalk = String(art_opts.get("kind", "asphalt")) == "sidewalk"
	_edges = marks.get("edges", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(marks.get("seed", 0))
	if _sidewalk:
		_slabs(rng, tile_offset)
		_walk_wear(rng)
	else:
		if marks.get("lane", false):
			_lane(rng)
		_road_wear(rng)
		_strew(rng)
	visuals.add_child(self)
	return self


func _draw() -> void:
	super()
	if not _sidewalk:
		return
	var curb := ObjectArtConfig.street_curb_color
	for side: Vector2 in _edges:  # The curb: a dark band along the edge, a paler line inside it.
		draw_rect(_edge_band(side, 0.0, 2.0), curb)
		draw_rect(_edge_band(side, 2.0, 1.0), curb.lightened(0.25))


## The band `width` px wide, `inset` px in from this piece's `side` edge, along its whole length.
func _edge_band(side: Vector2, inset: float, width: float) -> Rect2:
	match side:
		Vector2.UP:
			return Rect2(0, inset, _size.x, width)
		Vector2.DOWN:
			return Rect2(0, _size.y - inset - width, _size.x, width)
		Vector2.LEFT:
			return Rect2(inset, 0, width, _size.y)
	return Rect2(_size.x - inset - width, 0, width, _size.y)


## The piece's length along its long side.
func _length() -> float:
	return maxf(_size.x, _size.y)


## A random point near the middle line of the piece, along its length.
func _along(rng: RandomNumberGenerator, spread: float) -> Vector2:
	var t := rng.randf() * _length()
	var mid := Vector2(t, _size.y * 0.5) if _size.x >= _size.y else Vector2(_size.x * 0.5, t)
	return mid + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))


## Render a mark of `kind` tinted from `tone` into `r`, its art lying along the rect's long side.
func _mark(rng: RandomNumberGenerator, kind: String, r: Rect2, tone: Color, extra := {}) -> void:
	var facing: Vector2 = [Vector2.LEFT, Vector2.RIGHT][rng.randi_range(0, 1)] if r.size.y > r.size.x \
			else [Vector2.DOWN, Vector2.UP][rng.randi_range(0, 1)]
	var opts := { "kind": kind, "v": rng.randi_range(0, ObjectArtConfig.wear_variants - 1) }
	opts.merge(extra)
	add(ObjectArt.texture("wear", r.size, tone, facing, "", opts), r)


## A mark's rect round `at`: `size` (rounded to even px), turned a quarter at random.
static func _mark_rect(rng: RandomNumberGenerator, at: Vector2, size: Vector2) -> Rect2:
	size = (size / 2.0).round() * 2.0
	if rng.randf() < 0.5:
		size = Vector2(size.y, size.x)
	return Rect2((at - size * 0.5).round(), size)


# --- Sidewalk --------------------------------------------------------------------------------------------------------

## The odd slab of another shade (a newer one, a dirtier one) or with a broken corner, in clusters of one to three
## neighbouring slabs on the slab grid.
func _slabs(rng: RandomNumberGenerator, tile_offset: Vector2) -> void:
	var slab := ObjectArtConfig.street_slab_px
	var pavement := ObjectArtConfig.street_sidewalk_color
	var origin := -Vector2(fposmod(tile_offset.x, slab), fposmod(tile_offset.y, slab))  # Where the slab grid starts.
	var cells := Vector2i(ceili((_size.x - origin.x) / slab), ceili((_size.y - origin.y) / slab))
	var taken := {}
	var bounds := Rect2(Vector2.ZERO, _size)
	for _c in int(_length() / ObjectArtConfig.street_slab_cluster_run) + 1:
		var cell := Vector2i(rng.randi_range(0, cells.x - 1), rng.randi_range(0, cells.y - 1))
		for _m in rng.randi_range(1, 3):
			var at: Vector2i = cell + ([Vector2i.ZERO, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP][rng.randi_range(0, 4)] as Vector2i)
			var r := Rect2(origin + Vector2(at) * slab + Vector2.ONE, Vector2(slab - 1.0, slab - 1.0))
			if taken.has(at) or not bounds.encloses(r):
				continue
			taken[at] = true
			if rng.randf() < 0.7:
				var shade := [-2, -1, 1, 2][rng.randi_range(0, 3)] as int
				_mark(rng, "slab", r, pavement.lightened(0.05 * shade) if shade > 0 else pavement.darkened(-0.05 * shade))
			else:
				var chip := float(rng.randi_range(6, 12))
				var corner := Vector2(0.0 if rng.randf() < 0.5 else r.size.x - chip, 0.0 if rng.randf() < 0.5 else r.size.y - chip)
				_mark(rng, "chip", Rect2(r.position + corner, Vector2(chip, chip)), pavement)
			cell = at


## Clusters of 1-2 cracks, stains, gum and weeds along the sidewalk.
func _walk_wear(rng: RandomNumberGenerator) -> void:
	var bounds := Rect2(Vector2.ZERO, _size)
	for _c in int(_length() / ObjectArtConfig.street_walk_cluster_run):
		var p := _along(rng, 4.0)
		for _m in rng.randi_range(1, 2):
			var kind: String = RoomWear.pick(rng, ObjectArtConfig.street_walk_wear)
			var size := Vector2(rng.randf_range(24, 40), rng.randf_range(8, 14)) if kind in ["crack", "weeds"] \
					else Vector2(rng.randf_range(10, 22), rng.randf_range(8, 18))
			var r := _mark_rect(rng, p + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)), size)
			if bounds.encloses(r):
				_mark(rng, kind, r, ObjectArtConfig.street_sidewalk_color)


# --- Road ------------------------------------------------------------------------------------------------------------

## The lane line down the road's middle: every dash its own length, gap and wear, the odd one gone.
func _lane(rng: RandomNumberGenerator) -> void:
	var along_x := _size.x >= _size.y
	var mid := (_size.y if along_x else _size.x) * 0.5
	var t := rng.randf_range(4.0, 30.0)
	while t < _length() - 34.0:
		var length := float(rng.randi_range(22, 30))
		var roll := rng.randf()
		if roll >= 0.06:  # Else: worn away altogether.
			var fade := rng.randi_range(2, 5) if roll < 0.2 else rng.randi_range(6, 10)
			var across := mid - 2.0 + float(rng.randi_range(-1, 0))
			var width := float(rng.randi_range(3, 4))
			var r := Rect2(Vector2(t, across), Vector2(length, width)) if along_x else Rect2(Vector2(across, t), Vector2(width, length))
			_mark(rng, "dash", r.abs(), ObjectArtConfig.street_lane_color, { "fade": fade })
		t += length + rng.randf_range(24.0, 32.0)


## Clusters of 1-3 cracks, patches and oil out on the road, off its gutter.
func _road_wear(rng: RandomNumberGenerator) -> void:
	var bounds := Rect2(Vector2.ZERO, _size).grow(-4.0)
	for _c in int(_size.x * _size.y / ObjectArtConfig.street_road_cluster_area):
		var p := Vector2(rng.randf_range(30, maxf(30, _size.x - 30)), rng.randf_range(30, maxf(30, _size.y - 30)))
		for _m in rng.randi_range(1, 3):
			var at := p + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0, 50)
			var kind: String = RoomWear.pick(rng, ObjectArtConfig.street_road_wear)
			var size := Vector2(rng.randf_range(40, 110), rng.randf_range(10, 20)) if kind == "crack" \
					else (Vector2(rng.randf_range(24, 60), rng.randf_range(18, 40)) if kind == "patch" else Vector2(rng.randf_range(20, 50), rng.randf_range(14, 32)))
			var r := _mark_rect(rng, at, size)
			if bounds.encloses(r) and not _in_gutter(r):
				_mark(rng, kind, r, ObjectArtConfig.street_asphalt_color)


## Litter and puddles where they gather: clusters of one to three in the gutter, and the odd puddle out on the road.
func _strew(rng: RandomNumberGenerator) -> void:
	for side: Vector2 in _edges:
		var run := _size.x if side.x == 0.0 else _size.y
		for _c in int(run / ObjectArtConfig.street_litter_cluster_run * 0.7):
			var t := rng.randf() * run
			var depth := rng.randf_range(4.0, GUTTER)
			var p: Vector2
			match side:
				Vector2.UP:
					p = Vector2(t, depth)
				Vector2.DOWN:
					p = Vector2(t, _size.y - depth)
				Vector2.LEFT:
					p = Vector2(depth, t)
				_:
					p = Vector2(_size.x - depth, t)
			for m in rng.randi_range(1, 3):
				var at := p + (Vector2.ZERO if m == 0 else Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(16, 44))
				_litter_piece(rng, at, rng.randf() < 0.45)
	if rng.randf() < 0.5:  # Rain standing in a dip in the road.
		_litter_piece(rng, Vector2(rng.randf_range(40, maxf(40, _size.x - 40)), rng.randf_range(40, maxf(40, _size.y - 40))), true)


## One puddle or heap of trash centred near `at`, if it lies on the piece clear of the litter already down.
func _litter_piece(rng: RandomNumberGenerator, at: Vector2, puddle: bool) -> void:
	var size := Vector2(rng.randi_range(36, 70), rng.randi_range(22, 40)) if puddle else Vector2(rng.randi_range(18, 30), rng.randi_range(14, 22))
	size = (size / 2.0).round() * 2.0
	var facing: Vector2 = [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT][rng.randi_range(0, 3)]
	var foot := Vector2(size.y, size.x) if facing.x != 0.0 else size
	var r := Rect2((at - foot * 0.5).round(), foot)
	if not Rect2(Vector2.ZERO, _size).grow(-2.0).encloses(r) or _litter.any(func(q: Rect2) -> bool: return q.grow(6).intersects(r)):
		return
	_litter.append(r)
	var opts := { "kind": "puddle" if puddle else "trash", "v": rng.randi_range(0, ObjectArtConfig.wear_variants - 1) }
	add(ObjectArt.texture("decor", size, Color.BLACK, facing, "", opts), r)


## Whether `r` reaches into the gutter along one of the piece's edges.
func _in_gutter(r: Rect2) -> bool:
	for side: Vector2 in _edges:
		if _edge_band(side, 0.0, GUTTER).intersects(r):
			return true
	return false
