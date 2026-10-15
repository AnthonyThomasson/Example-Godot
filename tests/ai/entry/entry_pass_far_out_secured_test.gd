extends GameTest

## E15 as amended (issue #51, R2): a doorway's view is secured however far out from its wall the walk crosses it, not only within
## 150 px. A big hall with a long, narrow store room off its north wall: the view out of the store room's doorway is a band down the
## hall, reaching to within a body's width of the south wall, so there is no way round it. Gunfire is heard at the hall's east end;
## the invader at its west end walks there across the band 300 px out from the doorway: it first covers the doorway from beside the
## jamb, then crosses the band in one go, and never goes in. Real Von: the invader hears the shots and decides for itself; a
## `require` that it went to the gunfire without going into the store room comes first.
##
## Premise: the gunfire is one shot heard at the hall's east end (a `hit` event nobody known fired, as tests/_ai/investigate_probe.gd
## posts it), first thing in `run`, the frame the invader spawns in, so it is in its first decision.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const HALL := Rect2(0, 300, 1000, 450)
const STORE := Rect2(450, 0, 100, 300)
const DOOR := { "id": "door_500_300", "pos": Vector2(500, 300), "width": 60.0, "out": Vector2.DOWN, "room": STORE, "room_key": "store" }
const START := Vector2(100, 600)
const GUNFIRE := Vector2(900, 600)
## Seconds of gun through the doorway, from beside its jamb, that count as having secured it (as E15's tests).
const COVERED := 0.8
## The longest stop (s) in the view that still counts as crossing it in one go.
const NO_STOP := 0.3


func describe() -> Dictionary:
	return {
		"name": "A doorway's view crossed far out from its wall is secured first",
		"description": "Drawn across a big hall by gunfire, through the view out of a store room's doorway 300 px out from its wall, the invader covers the doorway from beside the jamb, then crosses the view without stopping and never goes in.",
		"tags": ["ai", "entry", "door_view", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "entry_hall", "rect": HALL },
		{ "key": "store", "type": "bedroom", "rect": STORE },
	], [
		{ "pos": DOOR["pos"], "width": DOOR["width"] },
		{ "pos": Vector2(0, 520), "width": 80.0 },  # the hall's door to the garden
	])
	s.actor(&"inv", &"invader", START, { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	Probe.gunfire(GUNFIRE)
	# The premise: the view bars the hall from the store room's wall to within a body of the south wall, so no way round it.
	var gap := HALL.end.y - View.polygon(DOOR)[1].y
	if not t.require(gap < 28.0, "set-up: the view reaches to within a body of the hall's south wall (%.0f px left)" % gap):
		return
	var plain := NavBuilder.route(t.world.get_world_2d().navigation_map, START, GUNFIRE)
	var out_at := -1.0
	for i in range(1, plain.size()):
		for k in 20:
			var p := plain[i - 1].lerp(plain[i], k / 20.0)
			if out_at < 0.0 and View.in_view(t, DOOR, p):
				out_at = Entry.outward(DOOR, p)
	if not t.require(out_at > 150.0, "set-up: the plain route crosses the view more than 150 px out from the wall (%.0f px)" % out_at):
		return
	var inv := t.actor(&"inv")
	var there := func(): return inv.global_position.x > 700.0
	var samples := await Entry.watch(t, [&"inv"], DOOR, 75.0, there)
	var act := str(Entry.brain(t, &"inv").current_act())
	var went_in := Entry.path_of(samples, &"inv").any(func(p: Vector2): return STORE.has_point(p))
	if not t.require(there.call() and not went_in, "the invader went to the gunfire across the hall without going into the store room (act %s, at %s)" % [act, inv.global_position.round()]):
		return
	var from_side := signf(Entry.lateral(DOOR, START))
	var crossed := View.axis_crossed_at(samples, &"inv", DOOR, from_side)
	if not t.require(crossed < INF, "set-up: the walk crossed the doorway's line of sight"):
		return
	var covered := View.time_covering(samples, &"inv", DOOR, crossed)
	t.check(covered >= COVERED, "it covered the doorway from beside the jamb before it crossed its view (%.1f s, across at %.2f s)" % [covered, crossed])
	var span := View.crossing_span(t, samples, &"inv", DOOR, crossed)
	var paused := View.longest_pause_in_view(t, samples, &"inv", DOOR, 20.0, span[0], span[1])
	t.check(paused < NO_STOP, "it crossed the view without stopping (longest stop %.2f s, in the view %.2f to %.2f s)" % [paused, span[0], span[1]])
	var back := View.axis_crossed_at(samples.filter(func(s): return float(s["t"]) > span[1]), &"inv", DOOR, -from_side)
	t.check(back == INF, "it crossed in one go, never back (back across at %.2f s)" % back)
