extends GameTest

## Every generated house is walkable and logical: within each room all of its doorways reach one another on the
## baked nav map, each doorway can be passed through, and every room is reachable from outside the
## front entrance; and LayoutRules.check finds nothing illogical in it (front door in a living space on the south
## wall, legal exits and doors, bathrooms are dead ends, no pass-through rooms) and it has at most one exit. The
## layout (rooms, doorways, exits) depends only on the plan and the seed's mirror draw, never on the furnishing,
## so these checks share the houses this test builds anyway.

const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
const AGENT_RADIUS := 14.0
const FAR_AWAY := Vector2(5000, 5000)  ## Keeps each house clear of the test arena's own nav region.
const STEP_IN := 30.0  ## How far inside a room a doorway's probe point sits.
const REACH_TOLERANCE := 6.0


func describe() -> Dictionary:
	return {
		"name": "Every doorway in a generated house is reachable",
		"description": "For every floorplan and several seeds: LayoutRules finds the layout logical, all doorways of a room are mutually reachable, each doorway can be walked through, and every room is reachable from the front entrance.",
		"tags": ["worldgen", "navigation", "house", "doorway", "layout"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## True when the nav map has a path from `a` to (near) `b`.
func _reachable(map: RID, a: Vector2, b: Vector2) -> bool:
	var path := NavigationServer2D.map_get_path(map, a, b, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(b) <= REACH_TOLERANCE


## The point just inside room `rect` from the doorway at `pos`.
func _inside(pos: Vector2, rect: Rect2) -> Vector2:
	var p := pos
	if absf(pos.y - rect.position.y) < 1.0:
		p.y += STEP_IN
	elif absf(pos.y - rect.end.y) < 1.0:
		p.y -= STEP_IN
	elif absf(pos.x - rect.position.x) < 1.0:
		p.x += STEP_IN
	else:
		p.x -= STEP_IN
	return p


## The point just outside the house from the front doorway at `pos` (the nearest room's side).
func _outside(pos: Vector2, rect: Rect2) -> Vector2:
	var inner := _inside(pos, rect)
	return pos + (pos - inner)


func _check_house(t: TestContext, plan: String, house_seed: int) -> void:
	var label := "%s seed %d" % [plan, house_seed]
	var house := WorldGen.generate(house_seed, plan, FAR_AWAY, t.world)
	var rooms := WorldGen.get_rooms(house)
	var openings := WorldGen.get_openings(house)

	# The layout is logical: no LayoutRules violation and at most one exit.
	var problems := LayoutRules.check(rooms, openings)
	t.check(problems.is_empty(), "%s is illogical: %s" % [label, "; ".join(problems)])
	var exits := openings.filter(func(o: Dictionary) -> bool: return o["exit"])
	t.check(exits.size() <= 1, "%s has %d exits" % [label, exits.size()])

	var region := NavBuilder.build(house, rooms, t.world, AGENT_RADIUS)
	await t.frames(3)  # the bake is applied a frame or two after the build
	var map := t.world.get_world_2d().navigation_map

	var rect_of := {}
	for room in rooms:
		rect_of[room["key"]] = room["rect"]

	# Per room: every pair of its doorways connects.
	for room in rooms:
		var rect: Rect2 = room["rect"]
		var points: Array = []
		for opening in openings:
			if room["key"] in opening["rooms"]:
				points.append(_inside(opening["pos"], rect))
		for i in points.size():
			for j in range(i + 1, points.size()):
				t.check(_reachable(map, points[i], points[j]),
					"%s: doorways %s and %s in %s cannot reach each other" % [label, points[i], points[j], room["key"]])

	# Each doorway is passable from either side.
	for opening in openings:
		var keys: Array = opening["rooms"]
		var a: Vector2
		var b: Vector2
		if keys.size() == 2:
			a = _inside(opening["pos"], rect_of[keys[0]])
			b = _inside(opening["pos"], rect_of[keys[1]])
		else:
			a = _inside(opening["pos"], rect_of[keys[0]])
			b = _outside(opening["pos"], rect_of[keys[0]])
		t.check(_reachable(map, a, b) and _reachable(map, b, a),
			"%s: doorway at %s (%s) cannot be passed through" % [label, opening["pos"], keys])

	# Every doorway (so every room) is reachable from outside the front entrance.
	for front in openings:
		if not front["front"]:
			continue
		var start := _outside(front["pos"], rect_of[front["rooms"][0]])
		for opening in openings:
			for key in opening["rooms"]:
				var target := _inside(opening["pos"], rect_of[key])
				t.check(_reachable(map, start, target),
					"%s: doorway at %s into %s is not reachable from the front entrance" % [label, opening["pos"], key])

	region.queue_free()
	house.queue_free()
	await t.frames(2)


func run(t: TestContext) -> void:
	for plan in HouseDefinitions.get_all():
		for house_seed in SEEDS:
			await _check_house(t, plan, house_seed)
