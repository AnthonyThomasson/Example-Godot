class_name RoomDresser

## World Generation domain: dresses a furnished room the run-down way, placing what the Objects domain then draws. Where
## things gather is World-Gen's: a corner, along a wall, just beside a piece of furniture (`anchor`), never in a doorway.
##   - Clutter: 0-2 walk-over pieces a room (no key twice) from its recipe's `clutter` (`[key, weight]` pairs; default
##     GeneralCatalog.CLUTTER), each a catalogue piece spawned through ObjectFactory, its own size and detail variant, the
##     long ones lying along the edge they hug.
##   - A neon tube along the foot of one wall in about every other room (GeneralCatalog `neon_tube`, cyan or magenta).
##   - Wear: 0-3 clusters a room (more in a big one), each handed to the Objects domain's WearFactory with the free stretch of
##     wall it is by, which decides and draws its marks on the floor and that wall.
## Every room draws from RNGs of its own, seeded by the run's seed and the room's key, so dressing never shifts the shared
## RNG: a seed keeps its furniture layout. Tuning: WorldGenConfig.dress_* / wear_* / clutter_* / neon_tube_*.

const _CORNER_CHANCE := 0.3  ## How an anchor is drawn: a corner, ...
const _WALL_CHANCE := 0.7  ## ... else (below this) along a wall, else beside a piece of furniture.


## Strew `room`'s clutter and maybe its neon tube under `parent` (rects in `parent`'s space): `room` is `{ key, type, rect }`,
## `clutter` its recipe's `[key, weight]` pairs, `solids` the footprints of its solid furniture, `blocked` the doorway
## clearance boxes, `run_seed` the run's seed. Returns the clutter placed: `[{ key, node }]`.
static func strew(room: Dictionary, clutter: Array, solids: Array, blocked: Array, wall_thickness: float, run_seed: int,
		parent: Node) -> Array:
	var rect: Rect2 = room["rect"]
	var inner := rect.grow(-(wall_thickness * 0.5 + WorldGenConfig.dress_inset))
	var here := solids.filter(func(s: Rect2) -> bool: return s.intersects(rect))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, room["key"], "clutter"])
	var out: Array = []
	var roll := rng.randf()
	var count := 0 if roll < WorldGenConfig.clutter_none_chance else (2 if roll >= 1.0 - WorldGenConfig.clutter_two_chance else 1)
	var kinds := clutter.duplicate()
	var placed: Array = []  ## The clutter footprints laid so far.
	for _i in count:
		if kinds.is_empty():
			break
		var key: String = _pick(rng, kinds)
		kinds = kinds.filter(func(row: Array) -> bool: return row[0] != key)
		var definition := ObjectDefinitions.get_definition(key).duplicate(true)
		if definition.is_empty():
			push_error("RoomDresser: unknown clutter '%s'" % key)
			continue
		var scale := WorldGenConfig.clutter_scale
		var size := ((definition["size"] as Vector2) * rng.randf_range(scale.x, scale.y) / 2.0).round() * 2.0
		definition["size"] = size
		definition["art_opts"] = (definition.get("art_opts", {}) as Dictionary).merged({ "v": rng.randi_range(0, 5) }, true)
		var long := size.x >= size.y * 2.0
		for _try in WorldGenConfig.dress_tries:
			var at := anchor(rng, inner, here)
			var rotated: bool = (at["along"] == Vector2.DOWN) if long else rng.randf() < 0.5
			var foot := Vector2(size.y, size.x) if rotated else size
			var p: Vector2 = (at["p"] as Vector2).clamp(inner.position + foot * 0.5, inner.end - foot * 0.5)
			var r := Rect2(p - foot * 0.5, foot)
			if not inner.encloses(r) or here.any(func(s: Rect2) -> bool: return s.grow(2.0).intersects(r)) \
					or placed.any(func(q: Rect2) -> bool: return q.grow(10.0).intersects(r)) \
					or blocked.any(func(b: Rect2) -> bool: return b.intersects(r)) or not near_anchor(p, rect, here):
				continue
			placed.append(r)
			var facing: Vector2 = [Vector2.LEFT, Vector2.RIGHT][rng.randi_range(0, 1)] if rotated else [Vector2.DOWN, Vector2.UP][rng.randi_range(0, 1)]
			var node := ObjectFactory.spawn(definition, p, parent, { "rotated": rotated, "facing": facing, "name": key })
			out.append({ "key": key, "node": node })
			break
	_neon_tube(rect, here + placed, blocked, wall_thickness, run_seed, room["key"], parent)
	return out


## Lay `room`'s wear (its rect in `parent`'s space) on its floor `floor_definition`: 0-3 clusters by walls, corners and
## `solids`, each with the free stretch of wall it is by (not across a doorway: `doors` `{ pos, width }`), built by the
## Objects domain's WearFactory under `parent`. Returns the clusters, `[{ pos, layer }]` (`layer` the room's wear node), or
## `[]` for a room left bare.
static func wear(room: Dictionary, floor_definition: Dictionary, solids: Array, doors: Array, wall_thickness: float,
		run_seed: int, parent: Node) -> Array:
	var rect: Rect2 = room["rect"]
	var inner := rect.grow(-(wall_thickness * 0.5 + WorldGenConfig.dress_inset))
	var here := solids.filter(func(s: Rect2) -> bool: return s.intersects(rect))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, room["key"], "wear"])
	var count := 0 if rng.randf() < WorldGenConfig.wear_bare_chance else 1
	for area: float in WorldGenConfig.wear_more_area:
		if rect.get_area() > area and rng.randf() < WorldGenConfig.wear_more_chance:
			count += 1
	var clusters: Array = []
	for _c in count:
		for _try in WorldGenConfig.dress_tries:
			var at := anchor(rng, inner, here)
			var p: Vector2 = at["p"]
			if not near_anchor(p, rect, here):
				continue
			var stretch: Array = _wall_stretch(p, rect, doors) if at["by_wall"] else []
			clusters.append({ "pos": p, "wall": stretch, "seed": rng.randi() })
			break
	if clusters.is_empty():
		return []
	var layer := WearFactory.spawn(rect, floor_definition, wall_thickness, clusters, (room["key"] as String).capitalize() + " Wear", parent)
	return clusters.map(func(c: Dictionary) -> Dictionary: return { "pos": c["pos"], "layer": layer })


## A spot of `inner` where wear and clutter gather: a corner, along a wall, or just beside one of `solids`. Returns
## `{ p, along, by_wall }`: the point, the direction of the edge it hugs, and whether that edge is a wall.
static func anchor(rng: RandomNumberGenerator, inner: Rect2, solids: Array) -> Dictionary:
	var roll := rng.randf()
	var p: Vector2
	var along := Vector2.RIGHT
	var by_wall := true
	if roll < _CORNER_CHANCE:
		var corner := Vector2(inner.position.x if rng.randf() < 0.5 else inner.end.x, inner.position.y if rng.randf() < 0.5 else inner.end.y)
		var inward := (inner.get_center() - corner).sign()
		var reach := WorldGenConfig.dress_reach
		p = corner + inward * Vector2(rng.randf_range(reach.x, reach.y), rng.randf_range(reach.x, reach.y))
		along = Vector2.RIGHT if rng.randf() < 0.5 else Vector2.DOWN
	elif roll < _WALL_CHANCE or solids.is_empty():
		var side := rng.randi_range(0, 3)
		var t := rng.randf_range(0.08, 0.92)
		var inset := rng.randf_range(WorldGenConfig.dress_reach.x, WorldGenConfig.dress_reach.y)
		match side:
			0:
				p = Vector2(inner.position.x + inner.size.x * t, inner.position.y + inset)
			1:
				p = Vector2(inner.position.x + inner.size.x * t, inner.end.y - inset)
			2:
				p = Vector2(inner.position.x + inset, inner.position.y + inner.size.y * t)
			_:
				p = Vector2(inner.end.x - inset, inner.position.y + inner.size.y * t)
		along = Vector2.RIGHT if side < 2 else Vector2.DOWN
	else:
		var s: Rect2 = solids[rng.randi_range(0, solids.size() - 1)]
		var side := rng.randi_range(0, 3)
		var gap := rng.randf_range(WorldGenConfig.dress_furniture_gap.x, WorldGenConfig.dress_furniture_gap.y)
		match side:
			0:
				p = Vector2(rng.randf_range(s.position.x, s.end.x), s.position.y - gap)
			1:
				p = Vector2(rng.randf_range(s.position.x, s.end.x), s.end.y + gap)
			2:
				p = Vector2(s.position.x - gap, rng.randf_range(s.position.y, s.end.y))
			_:
				p = Vector2(s.end.x + gap, rng.randf_range(s.position.y, s.end.y))
		along = Vector2.RIGHT if side < 2 else Vector2.DOWN
		by_wall = false
	return { "p": p.clamp(inner.position, inner.end), "along": along, "by_wall": by_wall }


## Whether `p` lies within WorldGenConfig.dress_near of a wall line of `rect` or of one of `solids`: where dressing belongs.
static func near_anchor(p: Vector2, rect: Rect2, solids: Array) -> bool:
	var near := WorldGenConfig.dress_near
	if minf(minf(p.x - rect.position.x, rect.end.x - p.x), minf(p.y - rect.position.y, rect.end.y - p.y)) <= near:
		return true
	return solids.any(func(s: Rect2) -> bool:
		var d := Vector2(maxf(0.0, maxf(s.position.x - p.x, p.x - s.end.x)), maxf(0.0, maxf(s.position.y - p.y, p.y - s.end.y)))
		return d.length() <= near)


## The free stretch of `rect`'s wall nearest `p` that `p` lies beside, `[a, b]` along the wall's centre line, cut short of
## every doorway in `doors` (`{ pos, width }`) on it; `[]` when `p` faces a doorway.
static func _wall_stretch(p: Vector2, rect: Rect2, doors: Array) -> Array:
	# The wall `p` is nearest: 0 top, 1 bottom, 2 left, 3 right.
	var gaps := [p.y - rect.position.y, rect.end.y - p.y, p.x - rect.position.x, rect.end.x - p.x]
	var side := gaps.find(gaps.min())
	var horizontal := side < 2
	var line := (rect.position.y if side == 0 else rect.end.y) if horizontal else (rect.position.x if side == 2 else rect.end.x)
	var start := Vector2(rect.position.x, line) if horizontal else Vector2(line, rect.position.y)
	var length := rect.size.x if horizontal else rect.size.y
	var along := (p.x - rect.position.x) if horizontal else (p.y - rect.position.y)
	var lo := 0.0
	var hi := length
	for door: Dictionary in doors:
		var at: Vector2 = door["pos"]
		if not is_equal_approx(at.y if horizontal else at.x, line):
			continue
		var offset := (at.x - rect.position.x) if horizontal else (at.y - rect.position.y)
		if offset <= 0.0 or offset >= length:
			continue
		var a: float = offset - float(door["width"]) * 0.5 - WorldGenConfig.dress_jamb
		var b: float = offset + float(door["width"]) * 0.5 + WorldGenConfig.dress_jamb
		if along >= a and along <= b:
			return []
		if b <= along:
			lo = maxf(lo, b)
		else:
			hi = minf(hi, a)
	var dir := Vector2.RIGHT if horizontal else Vector2.DOWN
	return [start + dir * lo, start + dir * hi]


## A neon tube along the foot of one of `rect`'s walls (WorldGenConfig.neon_tube_chance of rooms), clear of `taken` and the
## doorway boxes `blocked`; its own RNG, so it never shifts the clutter's draws.
static func _neon_tube(rect: Rect2, taken: Array, blocked: Array, wall_thickness: float, run_seed: int, key: String,
		parent: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, key, "neon"])
	if rng.randf() >= WorldGenConfig.neon_tube_chance:
		return
	var definition := ObjectDefinitions.get_definition("neon_tube").duplicate(true)
	var size: Vector2 = definition["size"]
	var inset := wall_thickness * 0.5 + size.y * 0.5 + 1.0
	for _try in WorldGenConfig.dress_tries:
		var side := rng.randi_range(0, 3)
		var t := rng.randf_range(0.2, 0.8)
		var p: Vector2
		match side:
			0:
				p = Vector2(rect.position.x + rect.size.x * t, rect.position.y + inset)
			1:
				p = Vector2(rect.position.x + rect.size.x * t, rect.end.y - inset)
			2:
				p = Vector2(rect.position.x + inset, rect.position.y + rect.size.y * t)
			_:
				p = Vector2(rect.end.x - inset, rect.position.y + rect.size.y * t)
		var rotated := side >= 2
		var foot := Vector2(size.y, size.x) if rotated else size
		var r := Rect2(p - foot * 0.5, foot)
		if blocked.any(func(b: Rect2) -> bool: return b.grow(WorldGenConfig.dress_jamb).intersects(r)) \
				or taken.any(func(s: Rect2) -> bool: return s.grow(2.0).intersects(r)):
			continue
		definition["art_opts"] = (definition.get("art_opts", {}) as Dictionary).merged({ "tone": "cyan" if rng.randf() < 0.5 else "magenta" }, true)
		# A turned tube's art is turned with it, so its painter still draws along the canvas's length.
		ObjectFactory.spawn(definition, p, parent, { "rotated": rotated, "facing": Vector2.RIGHT if rotated else Vector2.DOWN, "name": "neon_tube" })
		return


## A key of a `[[key, weight], ...]` table, drawn by weight.
static func _pick(rng: RandomNumberGenerator, table: Array) -> String:
	var total := 0.0
	for row: Array in table:
		total += float(row[1])
	var roll := rng.randf() * total
	for row: Array in table:
		roll -= float(row[1])
		if roll <= 0.0:
			return row[0]
	return table[-1][0]
