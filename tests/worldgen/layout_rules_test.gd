extends GameTest

## The layout validator (LayoutRules.check) accepts a logical layout and reports each kind of illogical one: a
## bathroom or bedroom front door, a front door off the south wall, a bathroom with two doors or joined to the
## kitchen, a pass-through bedroom, a room nothing reaches, an exit in a bathroom; and it knows ticket #61's room types
## (R11): a front door into a security vestibule is logical, one into a netrunner den is not, and a den walked through
## to reach another room is a pass-through. That every generated floorplan passes it (and has at most one exit) is
## checked per house in house_doorways_connected.


func describe() -> Dictionary:
	return {
		"name": "The layout rules reject illogical layouts",
		"description": "LayoutRules.check finds nothing in a logical layout and reports each kind of illogical one (front door in a bathroom or bedroom or off the south wall, bathrooms that are not dead ends, pass-through rooms, unreachable rooms, a bathroom exit), and applies the new room types' rules (vestibule front door, den a private dead end).",
		"tags": ["worldgen", "house", "layout", "doorway"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## A room dict as WorldGen.get_rooms returns it.
func _room(key: String, type: String, rect: Rect2) -> Dictionary:
	return { "key": key, "type": type, "rect": rect }


## A doorway dict as WorldGen.get_openings returns it.
func _door(pos: Vector2, rooms: Array, front := false, exit := false) -> Dictionary:
	return { "pos": pos, "width": 100.0, "front": front, "exit": exit, "rooms": rooms }


## True if some reported problem contains `fragment`.
func _reports(problems: Array, fragment: String) -> bool:
	return problems.any(func(p: String) -> bool: return p.contains(fragment))


## A small valid house to start the bad ones from: living (front) with a bedroom off it and an en-suite.
func _good_rooms() -> Array:
	return [
		_room("living", "living_room", Rect2(0, 300, 400, 300)),
		_room("bedroom", "bedroom", Rect2(0, 0, 400, 300)),
		_room("bathroom", "bathroom", Rect2(400, 0, 200, 300)),
	]


## The doors of `_good_rooms`: the front door into the living room, living <-> bedroom, bedroom <-> bathroom.
func _good_doors() -> Array:
	return [
		_door(Vector2(200, 600), ["living"], true),
		_door(Vector2(200, 300), ["living", "bedroom"]),
		_door(Vector2(400, 150), ["bedroom", "bathroom"]),
	]


## LayoutRules accepts a logical layout and reports each kind of illogical one.
func _check_validator(t: TestContext) -> void:
	t.check(LayoutRules.check(_good_rooms(), _good_doors()).is_empty(), "a living room + bedroom + en-suite is logical")

	var rooms := _good_rooms()
	rooms[0]["type"] = "bathroom"
	t.check(_reports(LayoutRules.check(rooms, _good_doors()), "front door opens into"), "a bathroom front door is reported")

	rooms = _good_rooms()
	rooms[0]["type"] = "bedroom"
	rooms[1]["type"] = "living_room"
	t.check(_reports(LayoutRules.check(rooms, _good_doors()), "front door opens into"), "a bedroom front door is reported")

	var doors := _good_doors()
	doors[0]["pos"] = Vector2(200, 300)
	t.check(_reports(LayoutRules.check(_good_rooms(), doors), "south wall"), "a front door off the south wall is reported")

	rooms = _good_rooms()
	rooms.append(_room("kitchen", "kitchen", Rect2(400, 300, 200, 300)))
	doors = _good_doors()
	doors.append(_door(Vector2(500, 300), ["bathroom", "kitchen"]))
	var problems := LayoutRules.check(rooms, doors)
	t.check(_reports(problems, "joins the bathroom"), "a kitchen <-> bathroom door is reported")
	t.check(_reports(problems, "has 2 doors"), "a bathroom with two doors is reported")

	rooms = _good_rooms()
	rooms.append(_room("great", "kitchen_living", Rect2(-400, 0, 400, 300)))
	doors = _good_doors()
	doors.append(_door(Vector2(0, 150), ["bedroom", "great"]))
	t.check(_reports(LayoutRules.check(rooms, doors), "pass-through"), "a bedroom you must cross to reach another room is reported")

	rooms = _good_rooms()
	rooms.append(_room("study", "home_office", Rect2(400, 300, 200, 300)))
	t.check(_reports(LayoutRules.check(rooms, _good_doors()), "cannot be reached"), "a room with no door is reported")

	doors = _good_doors()
	doors.append(_door(Vector2(600, 150), ["bathroom"], false, true))
	t.check(_reports(LayoutRules.check(_good_rooms(), doors), "exterior door opens into"), "an exit in a bathroom is reported")

	rooms = _good_rooms()
	rooms.append(_room("kitchen", "kitchen", Rect2(400, 300, 200, 300)))
	doors = _good_doors()
	doors.append(_door(Vector2(400, 450), ["living", "kitchen"]))
	doors.append(_door(Vector2(600, 450), ["kitchen"], false, true))
	t.check(LayoutRules.check(rooms, doors).is_empty(), "a kitchen with a back door is logical")


## The new room types' rules (R11): a security vestibule may carry the front door; a netrunner den may not, and is a
## private dead end that is never walked through.
func _check_new_room_types(t: TestContext) -> void:
	var vestibule := [_room("vestibule", "security_vestibule", Rect2(0, 0, 200, 200))]
	var problems := LayoutRules.check(vestibule, [_door(Vector2(100, 200), ["vestibule"], true)])
	t.check(problems.is_empty(), "a front door into a security vestibule is logical (%s)" % "; ".join(problems))

	var den := [_room("den", "netrunner_den", Rect2(0, 0, 300, 300))]
	t.check(_reports(LayoutRules.check(den, [_door(Vector2(150, 300), ["den"], true)]), "front door opens into"), "a netrunner den front door is reported")

	var rooms := [
		_room("living", "living_room", Rect2(0, 300, 400, 300)),
		_room("den", "netrunner_den", Rect2(0, 0, 400, 300)),
		_room("kitchen", "kitchen", Rect2(400, 0, 200, 300)),
	]
	var doors := [
		_door(Vector2(200, 600), ["living"], true),
		_door(Vector2(200, 300), ["living", "den"]),
		_door(Vector2(400, 150), ["den", "kitchen"]),
	]
	t.check(_reports(LayoutRules.check(rooms, doors), "pass-through"), "a netrunner den you must cross to reach another room is reported")


func run(t: TestContext) -> void:
	_check_validator(t)
	_check_new_room_types(t)
	await t.frames(1)
