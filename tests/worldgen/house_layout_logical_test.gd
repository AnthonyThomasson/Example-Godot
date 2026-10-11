extends GameTest

## Every floorplan is a logical layout: the front door opens into a living space on the south wall (never a
## bathroom or bedroom), exits sit on rooms that can have one, doors join room types that may share one,
## bathrooms are dead ends, nothing is a pass-through and every room is reachable from outside. Also pins
## the validator itself (LayoutRules.check) against deliberately illogical layouts.

const SEEDS := [1, 2, 3, 4, 5, 6]  ## Both mirror states of every plan.
const FAR_AWAY := Vector2(5000, 5000)


func describe() -> Dictionary:
	return {
		"name": "Every floorplan is a logical layout",
		"description": "For every floorplan and several seeds LayoutRules.check finds nothing (front door in a living space on the south wall, legal exits and doors, bathrooms are dead ends, no pass-through rooms); and the rules reject illogical layouts.",
		"tags": ["worldgen", "house", "layout", "doorway"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(WorldGenConfig, "fill_enabled", false)  # furnishing is not under test: keep it fast


## A room dict as WorldGen.get_rooms returns it.
func _room(key: String, type: String, rect: Rect2) -> Dictionary:
	return { "key": key, "type": type, "rect": rect }


## A doorway dict as WorldGen.get_openings returns it.
func _door(pos: Vector2, rooms: Array, front := false, exit := false) -> Dictionary:
	return { "pos": pos, "width": 100.0, "front": front, "exit": exit, "rooms": rooms }


## True if some reported problem contains `fragment`.
func _reports(problems: Array, fragment: String) -> bool:
	return problems.any(func(p: String) -> bool: return p.contains(fragment))


## Every floorplan, over both mirror states, has no LayoutRules violation and at most one exit.
func _check_plans(t: TestContext) -> void:
	for plan in HouseDefinitions.get_all():
		for house_seed in SEEDS:
			var house := WorldGen.generate(house_seed, plan, FAR_AWAY, t.world)
			var problems := LayoutRules.check(WorldGen.get_rooms(house), WorldGen.get_openings(house))
			t.check(problems.is_empty(), "%s seed %d is illogical: %s" % [plan, house_seed, "; ".join(problems)])
			var exits := WorldGen.get_openings(house).filter(func(o: Dictionary) -> bool: return o["exit"])
			t.check(exits.size() <= 1, "%s seed %d has %d exits" % [plan, house_seed, exits.size()])
			house.free()


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


func run(t: TestContext) -> void:
	_check_validator(t)
	_check_plans(t)
	await t.frames(1)
