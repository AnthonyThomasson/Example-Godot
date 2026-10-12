extends GameTest

## Main drops defenders where they can stand: never inside a solid piece of furniture and never on top of
## another defender. World-gen puts a free-standing piece (a bed, an island, a table) at a room's dead centre
## first, so a defender dropped at the centre used to spawn inside it; the first physics step ejected the
## piece, which handed its momentum back and flung the defender across the map (seen most in endless runs).
## Runs the match spawner (the placement helper `main.gd` uses) on the test's own world.

const MatchSpawner := preload("res://scenes/match_spawner.gd")
## A seed whose bedroom has a solid piece over its centre (checked below, so a world-gen change that moves
## it fails loudly instead of quietly testing nothing).
const SEED := 1
const ROOM := "bedroom"
## The character's body radius: a spawn point closer than this to a footprint overlaps it.
const BODY_RADIUS := 14.0
## How far a defender holding still may drift in the first moments (a settling nudge, not a launch).
const MAX_DRIFT := 40.0


func describe() -> Dictionary:
	return {
		"name": "Defenders spawn clear of furniture and of each other",
		"description": "Two defenders dropped into a bedroom with a bed over its centre start outside the bed and apart, and stay where they started instead of being flung away.",
		"tags": ["setup", "match", "spawn", "endless"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)
	s.von_down()   # the NPCs hold steady, so any movement is physics alone
	s.switch(&"ai.hostile_on_trespass", false)


func run(t: TestContext) -> void:
	var room := {}
	for r in t.rooms:
		if r["key"] == ROOM:
			room = r
	if not t.require(not room.is_empty(), "the house has a %s" % ROOM):
		return
	var holes := NavBuilder.furniture_holes(t.world)
	var centre: Vector2 = (room["rect"] as Rect2).get_center()
	if not t.require(_hole_near(centre, holes, BODY_RADIUS) >= 0,
			"precondition: a solid piece covers the %s's centre (pick another SEED if world-gen changed)" % ROOM):
		return

	var spawner = MatchSpawner.new()
	spawner.world = t.world
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	spawner.spawn_defender([room], rng, 0)
	spawner.spawn_defender([room], rng, 1)
	var npcs: Array = spawner.combatants.duplicate()
	if not t.require(npcs.size() == 2, "two defenders spawned"):
		return
	var starts: Array = npcs.map(func(n): return (n as Node2D).global_position)
	for i in npcs.size():
		t.check(_hole_near(starts[i], holes, BODY_RADIUS) < 0, "defender %d starts clear of the furniture (%s)" % [i + 1, starts[i]])
	t.check(starts[0].distance_to(starts[1]) >= BODY_RADIUS * 2.0, "the two defenders start apart (%s, %s)" % [starts[0], starts[1]])

	var elapsed := 0.0
	while elapsed < 1.5:
		await t.seconds(0.1)
		elapsed += 0.1
		for i in npcs.size():
			t.trace("drift_%d" % (i + 1), (npcs[i] as Node2D).global_position.distance_to(starts[i]))
	for i in npcs.size():
		var drift: float = (npcs[i] as Node2D).global_position.distance_to(starts[i])
		t.check(drift <= MAX_DRIFT, "defender %d stays where it started (moved %.0f px)" % [i + 1, drift])


## The index of the first footprint in `holes` that `p` lies inside or within `clearance` of, else -1.
func _hole_near(p: Vector2, holes: Array, clearance: float) -> int:
	for h in holes.size():
		var poly: PackedVector2Array = holes[h]
		if Geometry2D.is_point_in_polygon(p, poly):
			return h
		for i in poly.size():
			if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p) < clearance:
				return h
	return -1
