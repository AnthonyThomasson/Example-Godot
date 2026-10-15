class_name HouseSpawner

## World Generation domain: builds a house from a HouseDefinitions floorplan: walls per room (via
## the Objects domain's WallFactory, in the GeneralCatalog.WALL style, with every doorway opening
## cut into each wall it lies on), furniture per room (via RoomFurnisher), its clutter and neon (RoomDresser) and each
## room's floor (via FloorFactory, the one its furnishing palette names); then, once every room stands, each room's wear
## (RoomDresser, through WearFactory), the street ring round the house (FloorFactory) and the street lamps along its front
## (ObjectFactory), clear of its doorways. The house is positioned so its front entrance lands on a point. A plan may also
## carry `exit` openings (a back/side/garage door).

const OPENING_CLEARANCE := 50.0  ## Kept free of furniture on each side of a doorway opening.
const INTERIOR_MARGIN := 6.0   ## Gap between wall faces and furniture.


## Build the named floorplan under `parent`, positioned so its front entrance lands on
## `front_entrance_world`. `rng` drives every random choice. Every doorway is left as a plain open
## archway. Returns the house root.
static func spawn(plan_key: String, front_entrance_world: Vector2, rng: RandomNumberGenerator, parent: Node) -> Node2D:
	var plan := HouseDefinitions.get_plan(plan_key)
	if plan.is_empty():
		push_error("Unknown house plan: ", plan_key)
		return null

	var rooms: Array = plan["rooms"].duplicate(true)
	var openings: Array = plan["openings"].duplicate(true)
	if rng.randf() < 0.5:
		_mirror_x(rooms, openings)

	var front: Array = openings.filter(func(o: Dictionary) -> bool: return o.get("front", false))
	if front.size() != 1:
		push_error("House plan needs exactly one front entrance: ", plan_key)
		return null

	_validate(rooms, openings, plan_key)

	var house := Node2D.new()
	house.name = "House"
	house.position = front_entrance_world - (front[0]["pos"] as Vector2)
	parent.add_child(house)

	var wall_thickness: float = plan["wall_thickness"]
	var blocked := _opening_clearances(rooms, openings)

	# Room rects in WORLD space (captured after mirroring), for callers that spawn entities
	# into rooms. Exposed via WorldGen.get_rooms(house).
	var rooms_world: Array = []
	var clutter_world: Array = []
	var dressing: Array = []  ## Per room, for the wear pass: `[room, floor definition, solids]`.

	for room in rooms:
		var rect: Rect2 = room["rect"]
		var room_name := (room["key"] as String).capitalize()
		WallFactory.spawn(rect, wall_thickness, WallFactory.openings_for(rect, openings), room_name, house, GeneralCatalog.WALL)

		var furniture := Node2D.new()
		furniture.name = room_name + " Furniture"
		house.add_child(furniture)
		var interior := rect.grow(-(wall_thickness * 0.5 + INTERIOR_MARGIN))
		var solids: Array = []
		var palette := RoomFurnisher.furnish(room["type"], interior, blocked, rng, furniture, solids)
		var recipe := ArrangementDefinitions.get_recipe(room["type"])
		for piece: Dictionary in RoomDresser.strew(room, recipe.get("clutter", GeneralCatalog.CLUTTER), solids, blocked,
				wall_thickness, rng.seed, furniture):
			clutter_world.append({ "room": room["key"], "key": piece["key"], "node": piece["node"] })
		# The floor runs to the wall centerlines, so the walls cover the seams between rooms.
		var floor_def: Dictionary = GeneralCatalog.FLOORS.get(palette.get("floor", ""), {})
		if not floor_def.is_empty():
			FloorFactory.spawn(rect, floor_def, room_name + " Floor", house)
		dressing.append([room, floor_def, solids])

		rooms_world.append({
			"key": room["key"], "type": room["type"],
			"rect": Rect2(house.position + rect.position, rect.size),
		})

	# Wear after every room stands, so a mark on a shared wall draws over both rooms' caps.
	var wear_world: Array = []
	for entry: Array in dressing:
		for cluster: Dictionary in RoomDresser.wear(entry[0], entry[1], entry[2], openings, wall_thickness, rng.seed, house):
			wear_world.append({ "room": entry[0]["key"], "pos": house.position + (cluster["pos"] as Vector2), "layer": cluster["layer"] })

	house.set_meta("rooms", rooms_world)
	house.set_meta("openings", _openings_world(rooms, openings, house.position))
	house.set_meta("clutter", clutter_world)
	house.set_meta("wear", wear_world)
	house.set_meta("street", _street(rooms, house, rng.seed))
	house.set_meta("streetlights", _streetlights(rooms, openings, house, rng.seed))
	return house


## The street lamps along the front sidewalk, spawned under `house` (a `Street Lamps` node) through ObjectFactory from the
## catalogue's `streetlight` and, every other one, `street_sign` (its neon cyan or magenta): one about every
## `WorldGenConfig.streetlight_every` px, jittered, the row centred on the front, each post `streetlight_curb` px in from the
## curb with its arm out over the road (facing south). A lamp any part of which (post or overhang) would stand by a front or
## exit doorway (`_door_zones`) is dropped. Its own RNG, seeded from `run_seed`, so the furniture layout never shifts.
## Returns them as `[{ pos, node }]` (`pos` in world space).
static func _streetlights(rooms: Array, openings: Array, house: Node2D, run_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, "streetlights"])
	var bounds := _bounds(rooms)
	var side := WorldGenConfig.street_sidewalk
	var every := WorldGenConfig.streetlight_every
	var west := bounds.position.x - side
	var length := bounds.size.x + side * 2.0
	var count := maxi(1, int(length / every))
	var first := west + (length - (count - 1) * every) * 0.5
	var y := bounds.end.y + side - WorldGenConfig.streetlight_curb
	var zones := _door_zones(rooms, openings)
	var holder := Node2D.new()
	holder.name = "Street Lamps"
	house.add_child(holder)
	var out: Array = []
	for i in count:
		var at := Vector2(first + i * every + rng.randf_range(-WorldGenConfig.streetlight_jitter, WorldGenConfig.streetlight_jitter), y)
		var neon := "cyan" if rng.randf() < 0.5 else "magenta"
		var definition := ObjectDefinitions.get_definition("street_sign" if i % 2 == 1 else "streetlight")
		if not _clear_of_doors(_lamp_extent(definition, at, Vector2.DOWN), zones):
			continue
		var node := ObjectFactory.spawn(definition, at, holder, { "facing": Vector2.DOWN, "neon": neon if i % 2 == 1 else "" })
		out.append({ "pos": house.position + at, "node": node })
	return out


## Where a lamp of `definition` at `at` with its arm out along `facing` stands: its post's bounding square and its overhang.
static func _lamp_extent(definition: Dictionary, at: Vector2, facing: Vector2) -> Array:
	var size: Vector2 = definition["size"]
	var extent: Array = [Rect2(at - size * 0.5, size)]
	var overhang: Dictionary = definition.get("overhang", {})
	if not overhang.is_empty():
		var canonical: Vector2 = overhang["size"]
		var drawn := Vector2(canonical.y, canonical.x) if absf(facing.x) > absf(facing.y) else canonical
		extent.append(Rect2(at + facing * float(overhang["reach"]) - drawn * 0.5, drawn))
	return extent


## The no-lamp zone of each front or exit doorway: `{ pos, strip }`, its centre and the strip straight out of it (its width
## plus `streetlight_door_strip_margin` each side, `streetlight_door_strip_reach` out from the wall of its room it lies on).
static func _door_zones(rooms: Array, openings: Array) -> Array:
	var zones: Array = []
	for opening in openings:
		if not (opening.get("front", false) or opening.get("exit", false)):
			continue
		var p: Vector2 = opening["pos"]
		var keys := room_keys_on(rooms, opening)
		if keys.size() != 1:
			continue
		var rect: Rect2 = rooms.filter(func(room: Dictionary) -> bool: return room["key"] == keys[0])[0]["rect"]
		var out := Vector2.RIGHT if absf(p.x - rect.end.x) < 1.0 else Vector2.LEFT
		if absf(p.y - rect.end.y) < 1.0:
			out = Vector2.DOWN
		elif absf(p.y - rect.position.y) < 1.0:
			out = Vector2.UP
		var half: float = opening["width"] * 0.5 + WorldGenConfig.streetlight_door_strip_margin
		var across := Vector2(out.y, out.x).abs()
		var strip := Rect2(p - across * half, Vector2.ZERO).expand(p + across * half + out * WorldGenConfig.streetlight_door_strip_reach)
		zones.append({ "pos": p, "strip": strip })
	return zones


## Whether every rect of `extent` keeps `streetlight_door_clear` from each zone's doorway and out of its strip.
static func _clear_of_doors(extent: Array, zones: Array) -> bool:
	for zone: Dictionary in zones:
		var p: Vector2 = zone["pos"]
		for rect: Rect2 in extent:
			if p.distance_to(p.clamp(rect.position, rect.end)) < WorldGenConfig.streetlight_door_clear:
				return false
			if rect.intersects(zone["strip"]):
				return false
	return true


## The bounds of `rooms`' rects.
static func _bounds(rooms: Array) -> Rect2:
	var bounds: Rect2 = rooms[0]["rect"]
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	return bounds


## The street ring round the house: a sidewalk hugging the outline of its rooms and asphalt beyond it, four strips of each
## (the top and bottom ones spanning the corners), laid through FloorFactory under `house` from GeneralCatalog.STREET, each
## with its marks (seeded from `run_seed`; the lane down the road in front, on the south). Returns them as
## `[{ kind, rect, node }]` (`rect` in world space).
static func _street(rooms: Array, house: Node2D, run_seed: int) -> Array:
	var bounds := _bounds(rooms)
	var side := WorldGenConfig.street_sidewalk
	var walk := bounds.grow(side)
	var outer := bounds.grow(WorldGenConfig.street_reach)
	var road := WorldGenConfig.street_reach - side
	# [kind, rect, the edges its curb (sidewalk) or gutter (road) runs along, lane].
	var pieces := [
		["sidewalk", Rect2(walk.position.x, walk.position.y, walk.size.x, side), [Vector2.UP, Vector2.LEFT, Vector2.RIGHT], false],
		["sidewalk", Rect2(walk.position.x, bounds.end.y, walk.size.x, side), [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT], false],
		["sidewalk", Rect2(walk.position.x, bounds.position.y, side, bounds.size.y), [Vector2.LEFT], false],
		["sidewalk", Rect2(bounds.end.x, bounds.position.y, side, bounds.size.y), [Vector2.RIGHT], false],
		["street", Rect2(outer.position.x, outer.position.y, outer.size.x, road), [Vector2.DOWN], false],
		["street", Rect2(outer.position.x, walk.end.y, outer.size.x, road), [Vector2.UP], true],
		["street", Rect2(outer.position.x, walk.position.y, road, walk.size.y), [Vector2.RIGHT], false],
		["street", Rect2(walk.end.x, walk.position.y, road, walk.size.y), [Vector2.LEFT], false],
	]
	var out: Array = []
	for i in pieces.size():
		var piece: Array = pieces[i]
		var kind: String = piece[0]
		var definition: Dictionary = GeneralCatalog.STREET["sidewalk" if kind == "sidewalk" else "asphalt"].duplicate(true)
		definition["marks"] = { "seed": hash([run_seed, "street", i]), "edges": piece[2], "lane": piece[3] }
		definition["tile_from"] = walk.position if kind == "sidewalk" else outer.position
		var node := FloorFactory.spawn(piece[1], definition, "%s %d" % [kind.capitalize(), i % 4 + 1], house)
		out.append({ "kind": kind, "rect": Rect2(house.position + (piece[1] as Rect2).position, (piece[1] as Rect2).size), "node": node })
	return out


## Every doorway as `{ pos, width, front, exit, rooms }` in WORLD space; `rooms` are the keys of the
## rooms whose wall it cuts (one for the front entrance or an exit, two for an interior door).
static func _openings_world(rooms: Array, openings: Array, origin: Vector2) -> Array:
	var result: Array = []
	for opening in openings:
		result.append({
			"pos": origin + (opening["pos"] as Vector2), "width": opening["width"],
			"front": opening.get("front", false), "exit": opening.get("exit", false), "rooms": room_keys_on(rooms, opening),
		})
	return result


## The keys of the rooms whose wall `opening` (`{ pos, width }`) lies on.
static func room_keys_on(rooms: Array, opening: Dictionary) -> Array:
	var keys: Array = []
	for room in rooms:
		if not WallFactory.openings_for(room["rect"], [opening]).is_empty():
			keys.append(room["key"])
	return keys


## Author-error checks (warnings only): overlapping rooms, an opening not on the wall(s) it should be on, and
## anything LayoutRules finds illogical (a bathroom front door, a pass-through bathroom, a room nothing reaches).
static func _validate(rooms: Array, openings: Array, plan_key: String) -> void:
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var a: Rect2 = rooms[i]["rect"]
			var b: Rect2 = rooms[j]["rect"]
			if a.grow(-1.0).intersects(b.grow(-1.0)):
				push_warning("House %s: rooms %s and %s overlap" % [plan_key, rooms[i]["key"], rooms[j]["key"]])

	for opening in openings:
		var touching := rooms.filter(func(room: Dictionary) -> bool:
			return not WallFactory.openings_for(room["rect"], [opening]).is_empty()).size()
		if opening.get("front", false) or opening.get("exit", false):
			if touching != 1:
				push_warning("House %s: %s at %s is not on exactly one room wall" % [plan_key, "front entrance" if opening.get("front", false) else "exit", opening["pos"]])
		elif touching != 2:
			push_warning("House %s: interior opening at %s is not on a shared wall" % [plan_key, opening["pos"]])

	for problem: String in LayoutRules.check(rooms, _openings_world(rooms, openings, Vector2.ZERO)):
		push_warning("House %s: %s" % [plan_key, problem])


## Flip the floorplan left-to-right for extra layout variety.
static func _mirror_x(rooms: Array, openings: Array) -> void:
	var width := 0.0
	for room in rooms:
		width = maxf(width, (room["rect"] as Rect2).end.x)
	for room in rooms:
		var r: Rect2 = room["rect"]
		room["rect"] = Rect2(width - r.end.x, r.position.y, r.size.x, r.size.y)
	for opening in openings:
		var p: Vector2 = opening["pos"]
		opening["pos"] = Vector2(width - p.x, p.y)


## A box straddling each doorway opening that furniture must stay out of.
static func _opening_clearances(rooms: Array, openings: Array) -> Array:
	var blocked: Array = []
	for opening in openings:
		var p: Vector2 = opening["pos"]
		var width: float = opening["width"]
		var on_horizontal_wall := rooms.any(func(room: Dictionary) -> bool:
			var r: Rect2 = room["rect"]
			var on_edge := is_equal_approx(p.y, r.position.y) or is_equal_approx(p.y, r.end.y)
			return on_edge and p.x > r.position.x and p.x < r.end.x)
		if on_horizontal_wall:
			blocked.append(Rect2(p.x - width * 0.5, p.y - OPENING_CLEARANCE, width, OPENING_CLEARANCE * 2.0))
		else:
			blocked.append(Rect2(p.x - OPENING_CLEARANCE, p.y - width * 0.5, OPENING_CLEARANCE * 2.0, width))
	return blocked
