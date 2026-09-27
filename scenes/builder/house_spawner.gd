class_name HouseSpawner

## Builds a house from a HouseDefinitions floorplan: walls per room (via RoomSpawner,
## with every door cut into each wall it lies on) and furniture per room (via
## RoomFurnisher). The house is positioned so its front door lands on a given point.

const Room = preload("res://scenes/room/room.gd")

const DOOR_CLEARANCE := 70.0   ## Kept free of furniture on each side of a doorway.
const INTERIOR_MARGIN := 6.0   ## Gap between wall faces and furniture.


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

	var house := Node2D.new()
	house.name = "House"
	house.position = front_door_world - (front[0]["pos"] as Vector2)
	parent.add_child(house)

	var wall_thickness: float = plan["wall_thickness"]
	var blocked := _door_clearances(rooms, doors)

	for room in rooms:
		var rect: Rect2 = room["rect"]
		var room_name := (room["key"] as String).capitalize()
		RoomSpawner.spawn_from({
			"position": rect.position,
			"size": rect.size,
			"wall_thickness": wall_thickness,
			"openings": _openings_for(rect, doors),
		}, room_name, house)

		var furniture := Node2D.new()
		furniture.name = room_name + " Furniture"
		house.add_child(furniture)
		var interior := rect.grow(-(wall_thickness * 0.5 + INTERIOR_MARGIN))
		RoomFurnisher.furnish(room["type"], interior, blocked, rng, furniture)

	return house


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


## Openings (room.gd format) for every door lying on one of `rect`'s walls.
static func _openings_for(rect: Rect2, doors: Array) -> Array:
	var openings: Array = []
	for door in doors:
		var p: Vector2 = door["pos"]
		var width: float = door["width"]
		var within_x := p.x > rect.position.x and p.x < rect.end.x
		var within_y := p.y > rect.position.y and p.y < rect.end.y
		if within_x and is_equal_approx(p.y, rect.position.y):
			openings.append({ "side": Room.Side.TOP, "offset": p.x - rect.position.x, "width": width })
		elif within_x and is_equal_approx(p.y, rect.end.y):
			openings.append({ "side": Room.Side.BOTTOM, "offset": p.x - rect.position.x, "width": width })
		elif within_y and is_equal_approx(p.x, rect.position.x):
			openings.append({ "side": Room.Side.LEFT, "offset": p.y - rect.position.y, "width": width })
		elif within_y and is_equal_approx(p.x, rect.end.x):
			openings.append({ "side": Room.Side.RIGHT, "offset": p.y - rect.position.y, "width": width })
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
