extends GameTest

## E18 (issue #51, R1): a walk outside the house keeps out of the view of an open doorway into a room that is not clear for
## passing, when a way round is no longer than 2 x the plain route + 300 px. A one-room house with its front door in the south
## wall; the invader stands west of it and gunfire is heard east of it, outside. The plain way there runs along the south wall,
## through the view out of the front door (every point of the outdoor strip south of the house is in it); the way round the north
## side is about 1.2 x as long, so it is the one walked. Real Von: the invader hears the shots and decides for itself; a `require`
## that it went to the far side without going into the house comes first, so a different Von choice reads as a set-up finding.
##
## Premise: the gunfire is one shot heard east of the house (a `hit` event nobody known fired, as tests/_ai/investigate_probe.gd
## posts it), first thing in `run`, the frame the invader spawns in, so it is in its first decision.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const ROOM := Rect2(0, 0, 600, 300)
const FRONT := { "id": "door_300_300", "pos": Vector2(300, 300), "width": 80.0, "out": Vector2.DOWN, "room": ROOM, "room_key": "front_room" }
const START := Vector2(-100, 200)
const GUNFIRE := Vector2(700, 200)


func describe() -> Dictionary:
	return {
		"name": "A walk outside goes round the house, out of the front door's view",
		"description": "Drawn by gunfire to the far side of a one-room house, the invader walks round the north side instead of along the south wall past the open front door.",
		"tags": ["ai", "entry", "door_view", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "front_room", "type": "living_room", "rect": ROOM }], [{ "pos": FRONT["pos"], "width": FRONT["width"] }])
	s.actor(&"inv", &"invader", START, { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	Probe.gunfire(GUNFIRE)
	# The premise: the plain route runs through the front door's view, and the way round is within the cap.
	var plain := NavBuilder.route(t.world.get_world_2d().navigation_map, START, GUNFIRE)
	var plain_len := NavBuilder.path_length(plain)
	var crosses := false
	for i in range(1, plain.size()):
		for k in 20:
			crosses = crosses or View.in_view(t, FRONT, plain[i - 1].lerp(plain[i], k / 20.0))
	if not t.require(crosses, "set-up: the plain route to the gunfire runs through the front door's view (%d waypoints, %.0f px)" % [plain.size(), plain_len]):
		return
	var inv := t.actor(&"inv")
	var far_side := func(): return inv.global_position.x > ROOM.end.x + 20.0
	var samples := await Entry.watch(t, [&"inv"], FRONT, 75.0, far_side)
	var act := str(Entry.brain(t, &"inv").current_act())
	var went_in := Entry.path_of(samples, &"inv").any(func(p: Vector2): return ROOM.has_point(p))
	if not t.require(far_side.call() and not went_in, "the invader went to the gunfire on the far side of the house without going in (act %s, at %s)" % [act, inv.global_position.round()]):
		return
	var seen_at := View.first_in_view(t, samples, &"inv", FRONT)
	t.check(seen_at == INF, "it never stood in the front door's view (first at %.2f s, %.1f s in it)" % [seen_at, View.time_in_view(t, samples, &"inv", FRONT)])
	var north := Entry.path_of(samples, &"inv").any(func(p: Vector2): return p.y < ROOM.position.y)
	t.check(north, "it went round by the north side of the house (plain route %.0f px)" % plain_len)
