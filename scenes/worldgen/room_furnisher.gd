class_name RoomFurnisher

## World Generation domain: fills a room's interior with arrangements from its recipe (ArrangementDefinitions).
## Arrangements are placed as whole blocks: each one's footprint is fitted against a
## wall (or free-standing for "center" placement) without overlapping other placed
## blocks or any blocked area (doorway-opening clearances), then its items are spawned.

## Which wall an arrangement's local "top wall" frame is mapped onto.
enum Orient { TOP, BOTTOM, LEFT, RIGHT }

const PADDING := 8.0       ## Minimum gap between arrangements (and doorway-opening clearances).
const STEP := 10.0         ## Spacing of candidate offsets along a wall.
const CENTER_TRIES := 40   ## Random spots tried for free-standing arrangements.

## Walkability: a placement is rejected if it cuts a room's doorways off from each other (a doorway is the free grid cells inside its clearance box). An agent is
## a point on a coarse grid; furniture is grown by `FURNITURE_CLEAR` (agent radius + nav hole margin +
## slack) and the room edge by `WALL_CLEAR` (agent radius less the interior inset).
const PLAN_ATTEMPTS := 12  ## Layouts tried before settling for one that misses a required zone.
## A gap between furniture (or furniture and a wall) that is wider than touching but too narrow to walk
## through is a dead slot, and the baked nav hole offsets either side of it overlap and can crash the map
## bake; so a gap must be at most SLOT_MIN (just the padding: the holes fuse) or at least SLOT_MAX (an agent fits).
const SLOT_MIN := 8.5
const SLOT_MAX := 48.0
const WALK_CELL := 10.0
const FURNITURE_CLEAR := 22.0
const WALL_CLEAR := 8.0


## `interior` and `blocked` rects are in `parent`'s coordinate space. Returns the palette picked
## for the room (its `wood` / `fabric` tones and `floor` key), or {} if the type has no recipe.
static func furnish(room_type: String, interior: Rect2, blocked: Array, rng: RandomNumberGenerator, parent: Node) -> Dictionary:
	var recipe := ArrangementDefinitions.get_recipe(room_type)
	if recipe.is_empty():
		push_error("No furnishing recipe for room type: ", room_type)
		return {}

	var palettes: Array = recipe["palettes"]
	var palette: Dictionary = palettes[rng.randi_range(0, palettes.size() - 1)]

	# Plan the layout before spawning anything, so a layout that leaves a required zone unplaced
	# (walkability can make a tight room unable to fit it) is re-rolled instead of spawned.
	var plan := {}
	for attempt in range(PLAN_ATTEMPTS):
		plan = _plan(recipe, interior, blocked, rng)
		if plan["missing"].is_empty():
			break
	for zone_options in plan["missing"]:
		push_warning("RoomFurnisher: no room for required zone %s in %s" % [zone_options, room_type])
	for placement in plan["placements"]:
		_spawn_items(placement["arrangement"], placement["spot"], palette, parent)
	return palette


## One attempt at the recipe's layout: `{ placements: [{ arrangement, spot }], missing: [options] }`
## where `missing` lists the required zones that found no walkable spot. The zones come first, then the
## recipe's optional `fill` (see _fill).
static func _plan(recipe: Dictionary, interior: Rect2, blocked: Array, rng: RandomNumberGenerator) -> Dictionary:
	var state := {
		"interior": interior, "occupied": blocked.duplicate(), "used_tags": {}, "walk": _walk_state(interior, blocked),
		"placements": [], "ground": [],
	}
	var missing: Array = []

	for zone in recipe["zones"]:
		var count_range: Vector2i = zone["count"]
		var wanted := rng.randi_range(count_range.x, count_range.y)
		var placed := 0
		for key in _shuffled(zone["options"], rng):
			if placed >= wanted:
				break
			if _try_place(ArrangementDefinitions.get_arrangement(key), state, rng):
				placed += 1
		# A required zone that couldn't place any of its (large) options falls back to a
		# guaranteed-small arrangement, so essentials always appear even in tight rooms.
		if placed == 0 and wanted > 0 and zone.has("fallback"):
			if _try_place(ArrangementDefinitions.get_arrangement(zone["fallback"]), state, rng):
				placed = 1
		if zone.get("required", false) and placed == 0 and wanted > 0:
			missing.append(zone["options"])

	_fill(recipe.get("fill", {}), state, rng)
	return { "placements": state["placements"], "missing": missing }


## Place `arrangement` in the planned room if its tags are free and a spot fits; true if it was placed.
## A "ground" arrangement (rug, runner, mat) is non-solid decor: it may lie under furniture, so it only avoids
## other ground pieces and never touches the walkability grid.
static func _try_place(arrangement: Dictionary, state: Dictionary, rng: RandomNumberGenerator) -> bool:
	var tags: Array = arrangement.get("tags", [])
	var used_tags: Dictionary = state["used_tags"]
	if tags.any(func(t: String) -> bool: return used_tags.has(t)):
		return false
	var interior: Rect2 = state["interior"]
	var ground: bool = arrangement.get("ground", false)
	var spot := _find_ground_spot(arrangement, interior, state["ground"], rng) if ground \
			else _find_spot(arrangement, interior, state["occupied"], rng, state["walk"])
	if spot.is_empty():
		return false
	var rect: Rect2 = spot["rect"]
	if ground:
		state["ground"].append(rect)
	else:
		var walk: Dictionary = state["walk"]
		state["occupied"].append(rect)
		walk["grid"] = _stamp(walk, rect)
		walk["furniture"].append(rect)
	for tag in tags:
		used_tags[tag] = true
	state["placements"].append({ "arrangement": arrangement, "spot": spot })
	return true


## The recipe's fill pass: `{ target, options }` keeps drawing arrangements from `options` until the room's
## solid footprints cover `target` (a fraction of the interior area), so big rooms are not left bare. Every
## piece goes through the same placement checks as a zone. Each listed option is tried once, hit or miss (list
## one twice to allow two of it): a miss can't turn into a hit later because a fuller room never gains a spot
## and a taken tag stays taken, so a full room ends the pass quickly. Bounded and scaled by WorldGenConfig.
static func _fill(fill: Dictionary, state: Dictionary, rng: RandomNumberGenerator) -> void:
	if fill.is_empty() or not WorldGenConfig.fill_enabled:
		return
	var pool: Array = (fill["options"] as Array).duplicate()
	var interior: Rect2 = state["interior"]
	var goal: float = fill["target"] * WorldGenConfig.fill_scale * interior.get_area()
	var covered := _covered(state["placements"])
	var added := 0
	var tries := 0
	while not pool.is_empty() and covered < goal and added < WorldGenConfig.fill_max_pieces \
			and tries < WorldGenConfig.fill_attempts:
		tries += 1
		var pick := rng.randi_range(0, pool.size() - 1)
		if _try_place(ArrangementDefinitions.get_arrangement(pool[pick]), state, rng):
			added += 1
			covered = _covered(state["placements"])
		pool.remove_at(pick)


## Floor area (px^2) taken up by the planned solid arrangements (ground pieces lie beneath and don't count).
static func _covered(placements: Array) -> float:
	var area := 0.0
	for placement: Dictionary in placements:
		if not placement["arrangement"].get("ground", false):
			area += (placement["spot"]["rect"] as Rect2).get_area()
	return area


## Returns { rect, orient, mirror } for a free spot, or {} if none fits.
static func _find_spot(arrangement: Dictionary, interior: Rect2, occupied: Array, rng: RandomNumberGenerator, walk: Dictionary) -> Dictionary:
	var fp: Vector2 = arrangement["footprint"]
	var mirror := rng.randf() < 0.5

	if arrangement.get("placement", "wall") == "center":
		return _centre_spot(fp, interior, mirror, rng,
			func(rect: Rect2) -> bool: return _fits(rect, interior, occupied) and _leaves_no_slot(rect, walk) and _keeps_walkable(rect, walk))

	for orient in _shuffled([Orient.TOP, Orient.BOTTOM, Orient.LEFT, Orient.RIGHT], rng):
		var wall_length := interior.size.x if orient in [Orient.TOP, Orient.BOTTOM] else interior.size.y
		var max_offset := wall_length - fp.x
		if max_offset < 0.0:
			continue
		for offset in _offsets(max_offset, arrangement.get("prefer_corner", false), rng):
			var rect := _wall_rect(orient, offset, fp, interior)
			if _fits(rect, interior, occupied) and _leaves_no_slot(rect, walk) and _keeps_walkable(rect, walk):
				return { "rect": rect, "orient": orient, "mirror": mirror }
	return {}


## Like a free-standing spot, but for a "ground" arrangement: dead center first, then random, rejecting only an
## overlap with another ground piece. Returns { rect, orient, mirror }, or {} if none fits.
static func _find_ground_spot(arrangement: Dictionary, interior: Rect2, ground: Array, rng: RandomNumberGenerator) -> Dictionary:
	return _centre_spot(arrangement["footprint"], interior, rng.randf() < 0.5, rng,
		func(rect: Rect2) -> bool: return ground.all(func(other: Rect2) -> bool: return not rect.intersects(other)))


## A free-standing spot for a footprint `fp` in `interior`: dead centre first, then up to `CENTER_TRIES` random spots,
## in a random orientation each, the first that `accepts` taken. Returns { rect, orient, mirror }, or {} if none fits.
static func _centre_spot(fp: Vector2, interior: Rect2, mirror: bool, rng: RandomNumberGenerator, accepts: Callable) -> Dictionary:
	for i in range(CENTER_TRIES):
		var orient: int = rng.randi_range(Orient.TOP, Orient.RIGHT)
		var size := _oriented_size(fp, orient)
		var slack := interior.size - size
		if slack.x < 0.0 or slack.y < 0.0:
			continue
		var t := Vector2(0.5, 0.5) if i == 0 else Vector2(rng.randf(), rng.randf())
		var rect := Rect2(interior.position + slack * t, size)
		if accepts.call(rect):
			return { "rect": rect, "orient": orient, "mirror": mirror }
	return {}


## The room's walkability grid (1 = blocked: near a wall or placed furniture) and its doorways: for each
## clearance rect touching the interior, the free grid cells inside it.
static func _walk_state(interior: Rect2, blocked: Array) -> Dictionary:
	var cols := ceili(interior.size.x / WALK_CELL)
	var rows := ceili(interior.size.y / WALK_CELL)
	var grid := PackedByteArray()
	grid.resize(cols * rows)
	var walkable := interior.grow(-WALL_CLEAR)
	for i in range(cols * rows):
		if not walkable.has_point(_cell_center(interior, i % cols, int(i / float(cols)))):
			grid[i] = 1
	var doors: Array = []
	for clearance: Rect2 in blocked:
		if not clearance.intersects(interior):
			continue
		var cells: Array = []
		for i in range(cols * rows):
			if grid[i] == 0 and clearance.has_point(_cell_center(interior, i % cols, int(i / float(cols)))):
				cells.append(i)
		if not cells.is_empty():
			doors.append(cells)
	return { "interior": interior, "cols": cols, "rows": rows, "grid": grid, "doors": doors, "furniture": [] }


## The centre of walk-grid cell (`col`, `row`) in world space.
static func _cell_center(interior: Rect2, col: int, row: int) -> Vector2:
	return interior.position + Vector2(col + 0.5, row + 0.5) * WALK_CELL


## Block the grid cells within agent reach of `rect`.
static func _stamp(walk: Dictionary, rect: Rect2, grid: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var interior: Rect2 = walk["interior"]
	var cols: int = walk["cols"]
	var rows: int = walk["rows"]
	var target: PackedByteArray = walk["grid"] if grid.is_empty() else grid
	var grown := rect.grow(FURNITURE_CLEAR)
	var c0 := maxi(int((grown.position.x - interior.position.x) / WALK_CELL) - 1, 0)
	var c1 := mini(int((grown.end.x - interior.position.x) / WALK_CELL) + 1, cols - 1)
	var r0 := maxi(int((grown.position.y - interior.position.y) / WALK_CELL) - 1, 0)
	var r1 := mini(int((grown.end.y - interior.position.y) / WALK_CELL) + 1, rows - 1)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if grown.has_point(_cell_center(interior, c, r)):
				target[r * cols + c] = 1
	return target


## True if `rect` leaves no dead slot (see SLOT_MIN / SLOT_MAX) against a wall or placed furniture.
static func _leaves_no_slot(rect: Rect2, walk: Dictionary) -> bool:
	var interior: Rect2 = walk["interior"]
	for d in [rect.position.x - interior.position.x, interior.end.x - rect.end.x,
			rect.position.y - interior.position.y, interior.end.y - rect.end.y]:
		if d > 1.0 and d < SLOT_MAX:
			return false
	for other: Rect2 in walk["furniture"]:
		var gx := maxf(other.position.x - rect.end.x, rect.position.x - other.end.x)
		var gy := maxf(other.position.y - rect.end.y, rect.position.y - other.end.y)
		if (gy < 0.0 and gx > SLOT_MIN and gx < SLOT_MAX) or (gx < 0.0 and gy > SLOT_MIN and gy < SLOT_MAX):
			return false
	return true


## True if, with `rect` added, every doorway cell is still free and reachable from the first one.
static func _keeps_walkable(rect: Rect2, walk: Dictionary) -> bool:
	var doors: Array = walk["doors"]
	if doors.is_empty():
		return true
	var cols: int = walk["cols"]
	var rows: int = walk["rows"]
	var grid := _stamp(walk, rect, (walk["grid"] as PackedByteArray).duplicate())
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var stack: Array = []
	for cell: int in doors[0]:
		if grid[cell] == 0:
			seen[cell] = 1
			stack.append(cell)
	while not stack.is_empty():
		var n: int = stack.pop_back()
		var col := n % cols
		var row := int(n / float(cols))
		for next in [n - 1 if col > 0 else -1, n + 1 if col < cols - 1 else -1,
				n - cols if row > 0 else -1, n + cols if row < rows - 1 else -1]:
			if next >= 0 and grid[next] == 0 and seen[next] == 0:
				seen[next] = 1
				stack.append(next)
	# Every doorway must have a free, reached cell (the first one's own cells seed the fill).
	return doors.all(func(cells: Array) -> bool: return cells.any(func(c: int) -> bool: return seen[c] == 1))


## Candidate offsets along a wall; corners first when preferred, otherwise shuffled.
static func _offsets(max_offset: float, prefer_corner: bool, rng: RandomNumberGenerator) -> Array:
	var offsets: Array = []
	var offset := 0.0
	while offset < max_offset:
		offsets.append(offset)
		offset += STEP
	offsets.append(max_offset)
	offsets = _shuffled(offsets, rng)
	if prefer_corner:
		offsets = _shuffled([0.0, max_offset], rng) + offsets
	return offsets


## World rect of a footprint backed against `orient`'s wall at `offset` along it.
static func _wall_rect(orient: int, offset: float, fp: Vector2, interior: Rect2) -> Rect2:
	var p := interior.position
	var e := interior.end
	match orient:
		Orient.TOP:
			return Rect2(p.x + offset, p.y, fp.x, fp.y)
		Orient.BOTTOM:
			return Rect2(p.x + offset, e.y - fp.y, fp.x, fp.y)
		Orient.LEFT:
			return Rect2(p.x, p.y + offset, fp.y, fp.x)
		_:
			return Rect2(e.x - fp.y, p.y + offset, fp.y, fp.x)


## A footprint's size once mapped onto the given wall orientation.
static func _oriented_size(fp: Vector2, orient: int) -> Vector2:
	return fp if orient in [Orient.TOP, Orient.BOTTOM] else Vector2(fp.y, fp.x)


## True if `rect` fits inside the interior and clears every occupied rect (with padding).
static func _fits(rect: Rect2, interior: Rect2, occupied: Array) -> bool:
	if not interior.encloses(rect):
		return false
	var padded := rect.grow(PADDING)
	for other in occupied:
		if padded.intersects(other):
			return false
	return true


## Map each item from the arrangement's top-wall frame into the chosen spot and spawn it.
static func _spawn_items(arrangement: Dictionary, spot: Dictionary, palette: Dictionary, parent: Node) -> void:
	var fp: Vector2 = arrangement["footprint"]
	var rect: Rect2 = spot["rect"]
	var orient: int = spot["orient"]
	var mirror: bool = spot["mirror"]
	var sideways := orient == Orient.LEFT or orient == Orient.RIGHT

	for item in arrangement["items"]:
		var key: String = item["key"]
		var local: Vector2 = item["pos"]
		if mirror:
			local.x = fp.x - local.x
		var mapped: Vector2
		match orient:
			Orient.TOP:
				mapped = local
			Orient.BOTTOM:
				mapped = Vector2(local.x, fp.y - local.y)
			Orient.LEFT:
				mapped = Vector2(local.y, local.x)
			_:
				mapped = Vector2(fp.y - local.y, local.x)

		# World-Gen owns the catalogue: look the definition up here and hand the plain
		# dict to the Objects factory (which never knows about ObjectDefinitions).
		var definition := ObjectDefinitions.get_definition(key)
		if definition.is_empty():
			push_error("Unknown object type: ", key)
			continue
		var opts := {
			"rotated": item.get("rotated", false) != sideways, "name": key,
			"facing": _map_dir(item.get("facing", Vector2.DOWN), orient, mirror),
		}
		var material: String = definition.get("material", "")
		if palette.has(material):
			opts["color"] = palette[material]
		ObjectFactory.spawn(definition, rect.position + mapped, parent, opts)


## Map a direction from the arrangement's top-wall frame onto the chosen wall, the same way
## _spawn_items maps item positions (mirror flips x; LEFT/RIGHT swap the axes).
static func _map_dir(dir: Vector2, orient: int, mirror: bool) -> Vector2:
	if mirror:
		dir.x = -dir.x
	match orient:
		Orient.TOP:
			return dir
		Orient.BOTTOM:
			return Vector2(dir.x, -dir.y)
		Orient.LEFT:
			return Vector2(dir.y, dir.x)
		_:
			return Vector2(-dir.y, dir.x)


## Fisher–Yates shuffle driven by `rng`, so a seed reproduces the whole house.
static func _shuffled(items: Array, rng: RandomNumberGenerator) -> Array:
	var result := items.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result
