class_name HouseSpawner

## Builds a house from a HouseDefinitions floorplan: walls per room (via the Objects
## domain's WallFactory, in the GeneralCatalog.WALL style, with every doorway opening cut into
## each wall it lies on), furniture per room (via RoomFurnisher) and each room's floor (via
## FloorFactory, the one its furnishing palette names). The house is positioned so its front
## entrance lands on a point. A plan may also carry `exit` openings (a back/side/garage door).

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

	for room in rooms:
		var rect: Rect2 = room["rect"]
		var room_name := (room["key"] as String).capitalize()
		WallFactory.spawn(rect, wall_thickness, _openings_for(rect, openings), room_name, house, GeneralCatalog.WALL)

		var furniture := Node2D.new()
		furniture.name = room_name + " Furniture"
		house.add_child(furniture)
		var interior := rect.grow(-(wall_thickness * 0.5 + INTERIOR_MARGIN))
		var palette := RoomFurnisher.furnish(room["type"], interior, blocked, rng, furniture)
		# The floor runs to the wall centerlines, so the walls cover the seams between rooms.
		var floor_def: Dictionary = GeneralCatalog.FLOORS.get(palette.get("floor", ""), {})
		if not floor_def.is_empty():
			FloorFactory.spawn(rect, floor_def, room_name + " Floor", house)

		rooms_world.append({
			"key": room["key"], "type": room["type"],
			"rect": Rect2(house.position + rect.position, rect.size),
		})

	house.set_meta("rooms", rooms_world)
	house.set_meta("openings", _openings_world(rooms, openings, house.position))
	return house


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
		if not _openings_for(room["rect"], [opening]).is_empty():
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
			return not _openings_for(room["rect"], [opening]).is_empty()).size()
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


## Openings (Wall.Side format) for every doorway lying on one of `rect`'s walls.
static func _openings_for(rect: Rect2, openings: Array) -> Array:
	return WallFactory.openings_for(rect, openings)


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
