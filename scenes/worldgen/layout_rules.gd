class_name LayoutRules

## World Generation domain: what makes a floorplan logical, as tunable data plus a pure validator. A
## `class_name` holder of constants and statics — read as `LayoutRules.<name>`; no instance, no autoload.
##
## A layout is a set of rooms (`{ key, type, rect }`) joined by doorways (`{ pos, width, front, rooms }`, `rooms`
## = the keys of the rooms the doorway touches: one for an exterior door, two for an interior one). The rules:
##   ROOMS  per room TYPE: `front` (may carry the front door), `exit` (may carry a secondary exterior door),
##          `through` (may be the only route between two other rooms; a `through: false` room may still gate a
##          private dead end such as an en-suite bathroom), `max_doors` (most interior doors).
##   LINKS  which pairs of room types may share an interior door (symmetric).
## A type with no ROOMS entry gets DEFAULT_RULE; a type in no LINKS pair cannot share a door with anything, so
## a new room type has to be given its rules here before a plan can use it.
##
## `check` returns one readable string per violation (empty = a logical layout). HouseSpawner warns with them
## while building; tests/worldgen asserts every floorplan has none.

## The graph node standing for "outside the house" (a room with an exterior door is joined to it).
const OUTSIDE := "outside"

const DEFAULT_RULE := { "front": false, "exit": false, "through": true, "max_doors": 99 }

## `front` rooms are where a visitor first steps in; `exit` rooms may carry a back/side/garage door. Bedrooms,
## bathrooms and offices are never walked through to reach something else (an en-suite dead end hanging off
## them is fine); a bathroom is always a dead end with one door.
const ROOMS := {
	"studio": { "front": true },
	"living_room": { "front": true, "exit": true },
	"kitchen_living": { "front": true, "exit": true },
	"entry_hall": { "front": true },
	"hallway": { "front": true },
	"kitchen": { "exit": true },
	"dining_room": { "exit": true },
	"garage": { "exit": true, "max_doors": 2 },
	"laundry_room": { "exit": true, "max_doors": 2 },
	"bedroom": { "through": false },
	"kids_room": { "through": false },
	"home_office": { "through": false, "max_doors": 2 },
	"bathroom": { "through": false, "max_doors": 1 },
}

## Allowed interior-door pairs. Bathrooms open onto a hallway, a bedroom (en-suite) or a living space — never a
## kitchen, dining room, laundry or garage; bedrooms never open onto service rooms or another bedroom; a
## garage opens only onto the kitchen, laundry or a hallway.
const LINKS := [
	["hallway", "entry_hall"], ["hallway", "bedroom"], ["hallway", "kids_room"], ["hallway", "bathroom"],
	["hallway", "home_office"], ["hallway", "living_room"], ["hallway", "kitchen_living"], ["hallway", "kitchen"],
	["hallway", "dining_room"], ["hallway", "laundry_room"], ["hallway", "garage"],
	["entry_hall", "living_room"], ["entry_hall", "kitchen_living"], ["entry_hall", "dining_room"],
	["entry_hall", "home_office"],
	["living_room", "kitchen"], ["living_room", "dining_room"], ["living_room", "bedroom"],
	["living_room", "kids_room"], ["living_room", "bathroom"], ["living_room", "home_office"],
	["kitchen_living", "bedroom"], ["kitchen_living", "kids_room"], ["kitchen_living", "bathroom"],
	["kitchen_living", "home_office"], ["kitchen_living", "dining_room"], ["kitchen_living", "laundry_room"],
	["kitchen", "dining_room"], ["kitchen", "laundry_room"], ["kitchen", "garage"],
	["bedroom", "bathroom"], ["kids_room", "bathroom"],
	["studio", "bathroom"],
	["laundry_room", "garage"],
]


## The rules for a room type: DEFAULT_RULE overridden by its ROOMS entry.
static func rule(room_type: String) -> Dictionary:
	return DEFAULT_RULE.merged(ROOMS.get(room_type, {}), true)


## True if rooms of these two types may share an interior door.
static func linked(type_a: String, type_b: String) -> bool:
	for pair: Array in LINKS:
		if (pair[0] == type_a and pair[1] == type_b) or (pair[0] == type_b and pair[1] == type_a):
			return true
	return false


## Every violation in a layout, as readable strings (empty = logical). `rooms` are `{ key, type, rect }`,
## `openings` are `{ pos, front, rooms, … }` — in any one coordinate space (a plan's, or the world's).
static func check(rooms: Array, openings: Array) -> Array:
	var problems: Array = []
	var type_of := {}
	var graph := { OUTSIDE: [] }
	var bounds := Rect2()
	for i in range(rooms.size()):
		var room: Dictionary = rooms[i]
		type_of[room["key"]] = room["type"]
		graph[room["key"]] = []
		bounds = room["rect"] if i == 0 else bounds.merge(room["rect"])

	var fronts := 0
	var doors := {}  # room key -> interior doors it has
	for opening in openings:
		var keys: Array = opening["rooms"]
		var is_front: bool = opening.get("front", false)
		if is_front:
			fronts += 1
		if keys.size() == 1:
			var key: String = keys[0]
			if is_front:
				if not rule(type_of[key])["front"]:
					problems.append("the front door opens into %s" % _describe(key, type_of))
				if absf((opening["pos"] as Vector2).y - bounds.end.y) > 1.0:
					problems.append("the front door at %s is not on the house's south wall" % [opening["pos"]])
			elif not rule(type_of[key])["exit"]:
				problems.append("an exterior door opens into %s" % _describe(key, type_of))
			graph[key].append(OUTSIDE)
			graph[OUTSIDE].append(key)
		elif keys.size() == 2 and not is_front:
			var a: String = keys[0]
			var b: String = keys[1]
			if not linked(type_of[a], type_of[b]):
				problems.append("a door joins %s and %s" % [_describe(a, type_of), _describe(b, type_of)])
			graph[a].append(b)
			graph[b].append(a)
			doors[a] = doors.get(a, 0) + 1
			doors[b] = doors.get(b, 0) + 1
		else:
			problems.append("the doorway at %s joins %d rooms%s" % [opening["pos"], keys.size(), " (a front entrance)" if is_front else ""])
	if fronts != 1:
		problems.append("the house needs exactly one front door, not %d" % fronts)

	for key in type_of:
		var max_doors: int = rule(type_of[key])["max_doors"]
		if doors.get(key, 0) > max_doors:
			problems.append("%s has %d doors (at most %d)" % [_describe(key, type_of), doors[key], max_doors])

	var from_outside := _reached(graph, "")
	for key in type_of:
		if not from_outside.has(key):
			problems.append("%s cannot be reached from outside" % _describe(key, type_of))
	# A room that must not be walked through may only gate private dead ends hanging off it (an en-suite).
	for key in type_of:
		if rule(type_of[key])["through"] or not from_outside.has(key):
			continue
		var without := _reached(graph, key)
		for other in type_of:
			if other == key or not from_outside.has(other) or without.has(other):
				continue
			if rule(type_of[other])["through"] or _only_neighbour(graph, other) != key:
				problems.append("%s is a pass-through: reaching %s means walking through it" % [_describe(key, type_of), _describe(other, type_of)])
	return problems


## Every graph node reachable from OUTSIDE without entering `skip`.
static func _reached(graph: Dictionary, skip: String) -> Dictionary:
	var seen := { OUTSIDE: true }
	var stack: Array = [OUTSIDE]
	while not stack.is_empty():
		var n: String = stack.pop_back()
		for m: String in graph[n]:
			if m != skip and not seen.has(m):
				seen[m] = true
				stack.append(m)
	return seen


## The one node `key` is joined to, or "" if it has none or several (so it is not a dead end).
static func _only_neighbour(graph: Dictionary, key: String) -> String:
	var found := ""
	for m: String in graph[key]:
		if found != "" and m != found:
			return ""
		found = m
	return found


## "the <type>" (plus the room key when it differs), for violation messages.
static func _describe(key: String, type_of: Dictionary) -> String:
	var room_type: String = type_of[key]
	return "the %s" % room_type if key == room_type else "the %s (%s)" % [room_type, key]
