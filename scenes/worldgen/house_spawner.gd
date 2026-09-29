class_name HouseSpawner

## Builds a house from a HouseDefinitions floorplan: walls per room (via the Objects
## domain's WallFactory, with every door cut into each wall it lies on) and furniture per
## room (via RoomFurnisher). The house is positioned so its front door lands on a point.

const Wall = preload("res://scenes/objects/wall/wall.gd")

const DOOR_CLEARANCE := 50.0   ## Kept free of furniture on each side of a doorway.
const INTERIOR_MARGIN := 6.0   ## Gap between wall faces and furniture.


## Build the named floorplan under `parent`, positioned so its front door lands on
## `front_door_world`. `rng` drives every random choice. Returns the house root.
static func spawn(plan_key: String, front_door_world: Vector2, rng: RandomNumberGenerator, parent: Node) -> Node2D:
	var plan := HouseDefinitions.get_plan(plan_key)
	if plan.is_empty():
		push_error("Unknown house plan: ", plan_key)
		return null

	var rooms: Array = plan["rooms"].duplicate(true)
	var doors: Array = plan["doors"].duplicate(true)
	if rng.randf() < 0.5:
		_mirror_x(rooms, doors)

	var front: Array = doors.filter(func(d: Dictionary) -> bool: return d.get("front", false))
	if front.size() != 1:
		push_error("House plan needs exactly one front door: ", plan_key)
		return null

	_validate(rooms, doors, plan_key)

	var house := Node2D.new()
	house.name = "House"
	house.position = front_door_world - (front[0]["pos"] as Vector2)
	parent.add_child(house)

	var wall_thickness: float = plan["wall_thickness"]
	var blocked := _door_clearances(rooms, doors)

	# Room rects in WORLD space (captured after mirroring), for callers that spawn entities
	# into rooms. Exposed via WorldGen.get_rooms(house).
	var rooms_world: Array = []

	for room in rooms:
		var rect: Rect2 = room["rect"]
		var room_name := (room["key"] as String).capitalize()
		WallFactory.spawn(rect, wall_thickness, _openings_for(rect, doors), room_name, house)

		var furniture := Node2D.new()
		furniture.name = room_name + " Furniture"
		house.add_child(furniture)
		var interior := rect.grow(-(wall_thickness * 0.5 + INTERIOR_MARGIN))
		RoomFurnisher.furnish(room["type"], interior, blocked, rng, furniture)

		rooms_world.append({
			"key": room["key"], "type": room["type"],
			"rect": Rect2(house.position + rect.position, rect.size),
		})

	house.set_meta("rooms", rooms_world)
	return house


## Author-error checks (warnings only): overlapping rooms, a door not on a shared
## wall, and rooms unreachable from the front door.
static func _validate(rooms: Array, doors: Array, plan_key: String) -> void:
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var a: Rect2 = rooms[i]["rect"]
			var b: Rect2 = rooms[j]["rect"]
			if a.grow(-1.0).intersects(b.grow(-1.0)):
				push_warning("House %s: rooms %s and %s overlap" % [plan_key, rooms[i]["key"], rooms[j]["key"]])

	var adj: Array = []
	for i in range(rooms.size()):
		adj.append([])
	var front_idx := -1
	for door in doors:
		var touching: Array = []
		for i in range(rooms.size()):
			if not _openings_for(rooms[i]["rect"], [door]).is_empty():
				touching.append(i)
		if door.get("front", false):
			if touching.size() != 1:
				push_warning("House %s: front door at %s is not on exactly one room wall" % [plan_key, door["pos"]])
			elif front_idx == -1:
				front_idx = touching[0]
		elif touching.size() < 2:
			push_warning("House %s: interior door at %s is not on a shared wall" % [plan_key, door["pos"]])
		else:
			for a in touching:
				for b in touching:
					if a != b:
						adj[a].append(b)

	if front_idx < 0:
		return
	var seen := { front_idx: true }
	var stack := [front_idx]
	while not stack.is_empty():
		var n: int = stack.pop_back()
		for m in adj[n]:
			if not seen.has(m):
				seen[m] = true
				stack.append(m)
	for i in range(rooms.size()):
		if not seen.has(i):
			push_warning("House %s: room %s is unreachable from the front door" % [plan_key, rooms[i]["key"]])


## Flip the floorplan left-to-right for extra layout variety.
static func _mirror_x(rooms: Array, doors: Array) -> void:
	var width := 0.0
	for room in rooms:
		width = maxf(width, (room["rect"] as Rect2).end.x)
	for room in rooms:
		var r: Rect2 = room["rect"]
		room["rect"] = Rect2(width - r.end.x, r.position.y, r.size.x, r.size.y)
	for door in doors:
		var p: Vector2 = door["pos"]
		door["pos"] = Vector2(width - p.x, p.y)


## Openings (Wall.Side format) for every door lying on one of `rect`'s walls.
static func _openings_for(rect: Rect2, doors: Array) -> Array:
	var openings: Array = []
	for door in doors:
		var p: Vector2 = door["pos"]
		var width: float = door["width"]
		var within_x := p.x > rect.position.x and p.x < rect.end.x
		var within_y := p.y > rect.position.y and p.y < rect.end.y
		if within_x and is_equal_approx(p.y, rect.position.y):
			openings.append({ "side": Wall.Side.TOP, "offset": p.x - rect.position.x, "width": width })
		elif within_x and is_equal_approx(p.y, rect.end.y):
			openings.append({ "side": Wall.Side.BOTTOM, "offset": p.x - rect.position.x, "width": width })
		elif within_y and is_equal_approx(p.x, rect.position.x):
			openings.append({ "side": Wall.Side.LEFT, "offset": p.y - rect.position.y, "width": width })
		elif within_y and is_equal_approx(p.x, rect.end.x):
			openings.append({ "side": Wall.Side.RIGHT, "offset": p.y - rect.position.y, "width": width })
	return openings


## A box straddling each doorway that furniture must stay out of.
static func _door_clearances(rooms: Array, doors: Array) -> Array:
	var blocked: Array = []
	for door in doors:
		var p: Vector2 = door["pos"]
		var width: float = door["width"]
		var on_horizontal_wall := rooms.any(func(room: Dictionary) -> bool:
			var r: Rect2 = room["rect"]
			var on_edge := is_equal_approx(p.y, r.position.y) or is_equal_approx(p.y, r.end.y)
			return on_edge and p.x > r.position.x and p.x < r.end.x)
		if on_horizontal_wall:
			blocked.append(Rect2(p.x - width * 0.5, p.y - DOOR_CLEARANCE, width, DOOR_CLEARANCE * 2.0))
		else:
			blocked.append(Rect2(p.x - DOOR_CLEARANCE, p.y - width * 0.5, DOOR_CLEARANCE * 2.0, width))
	return blocked
