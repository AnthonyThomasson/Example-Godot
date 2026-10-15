extends GameTest

## E18 (issue #51, R1): inside the house, a walk keeps out of the view of an open doorway into a room that is not clear for
## passing, when a way round is no longer than 2 x the plain route + 300 px. A big hall with a long, narrow store room off its north
## wall, whose doorway's view is a band down the hall that ends 165 px short of the south wall: the hall's east end is reachable two
## ways from its west end, straight through the band or round its far end, about 1.3 x as long. Gunfire is heard at the east end; the
## invader gets there the way round, never through the store room's view. (`entry_pass_far_out_secured` is the same hall with the
## band reaching the south wall: no way round, so the doorway is secured and the band crossed.) Real Von: the invader hears the shots
## and decides for itself; a `require` that it got to the east end without going into the store room comes first.
##
## Premise: the gunfire is one shot heard at the hall's east end (a `hit` event nobody known fired, as tests/_ai/investigate_probe.gd
## posts it), first thing in `run`, the frame the invader spawns in, so it is in its first decision.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const HALL := Rect2(0, 300, 1000, 600)
const STORE := Rect2(450, 0, 100, 300)
const STORE_DOOR := { "id": "door_500_300", "pos": Vector2(500, 300), "width": 60.0, "out": Vector2.DOWN, "room": STORE, "room_key": "store" }
const START := Vector2(100, 450)
const GUNFIRE := Vector2(900, 450)
## The way round the far end of the view, below it.
const ROUND := [Vector2(340, 820), Vector2(660, 820)]


func describe() -> Dictionary:
	return {
		"name": "A walk in the house goes round a doorway's view",
		"description": "Drawn across a big hall by gunfire, the invader goes round the far end of the view out of a store room's doorway rather than straight through it.",
		"tags": ["ai", "entry", "door_view", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "entry_hall", "rect": HALL },
		{ "key": "store", "type": "bedroom", "rect": STORE },
	], [
		{ "pos": STORE_DOOR["pos"], "width": STORE_DOOR["width"] },
		{ "pos": Vector2(0, 600), "width": 80.0 },  # the hall's door to the garden
	])
	s.actor(&"inv", &"invader", START, { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	Probe.gunfire(GUNFIRE)
	var map := t.world.get_world_2d().navigation_map
	var plain := NavBuilder.route(map, START, GUNFIRE)
	var plain_len := NavBuilder.path_length(plain)
	var crosses := false
	for i in range(1, plain.size()):
		for k in 20:
			crosses = crosses or View.in_view(t, STORE_DOOR, plain[i - 1].lerp(plain[i], k / 20.0))
	if not t.require(crosses, "set-up: the plain route to the gunfire crosses the store room doorway's view (%.0f px)" % plain_len):
		return
	var round_len := NavBuilder.path_length(NavBuilder.route(map, START, ROUND[0])) + ROUND[0].distance_to(ROUND[1]) + NavBuilder.path_length(NavBuilder.route(map, ROUND[1], GUNFIRE))
	if not t.require(round_len <= View.AVOID_RATIO * plain_len + View.AVOID_SLACK, "set-up: the way round the view is within the cap (%.0f px against %.0f px plain)" % [round_len, plain_len]):
		return
	if not t.require(not View.in_view(t, STORE_DOOR, ROUND[0], 0.0) and not View.in_view(t, STORE_DOOR, ROUND[1], 0.0), "set-up: the way round passes below the view's far end"):
		return
	var inv := t.actor(&"inv")
	var there := func(): return inv.global_position.x > 750.0
	var samples := await Entry.watch(t, [&"inv"], STORE_DOOR, 75.0, there)
	var act := str(Entry.brain(t, &"inv").current_act())
	var went_in := Entry.path_of(samples, &"inv").any(func(p: Vector2): return STORE.has_point(p))
	if not t.require(there.call() and not went_in, "the invader got to the gunfire at the hall's east end without going into the store room (act %s, at %s)" % [act, inv.global_position.round()]):
		return
	var seen_at := View.first_in_view(t, samples, &"inv", STORE_DOOR)
	t.check(seen_at == INF, "it never stood in the store room doorway's view (first at %.2f s, %.1f s in it)" % [seen_at, View.time_in_view(t, samples, &"inv", STORE_DOOR)])
	var below := Entry.path_of(samples, &"inv").any(func(p: Vector2): return p.y > View.polygon(STORE_DOOR)[1].y and absf(p.x - STORE_DOOR["pos"].x) < 60.0)
	t.check(below, "it went round the far end of the view")
