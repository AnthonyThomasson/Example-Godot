extends GameTest

## E15 as amended (issue #51, R2): with no way round a doorway's view within 2 x the plain route + 300 px, a walk that has to cross
## it first covers the doorway from beside the jamb, then crosses the view in one go without stopping; it never goes in. Now for a
## walk outside the house past an exterior door too. The invader stands in the garden west of the Terrace house's living room and
## gunfire is heard in the garden south-west of the hall; the only short way there runs down the west side, across the view out of
## the front door; round the house's east side is more than twice as far, past the cap. Real Von: the invader hears the shots and
## decides for itself; a `require` that it went to the gunfire without going in comes first.
##
## Premise: the gunfire is one shot heard in the south-west garden (a `hit` event nobody known fired, as
## tests/_ai/investigate_probe.gd posts it), first thing in `run`, the frame the invader spawns in, so it is in its first decision.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const START := Vector2(-100, 150)
const GUNFIRE := Vector2(-100, 600)
## Seconds of gun through the doorway, from beside its jamb, that count as having secured it (as E15's tests).
const COVERED := 0.8
## The longest stop (s) in the view that still counts as crossing it in one go.
const NO_STOP := 0.3


func describe() -> Dictionary:
	return {
		"name": "A walk past the front door covers it from the jamb, then crosses its view",
		"description": "Drawn down the west side of the Terrace house by gunfire, with no way round within the cap, the invader covers the open front door from beside the jamb, then crosses its view without stopping and never goes in.",
		"tags": ["ai", "entry", "door_view", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"inv", &"invader", START, { "facing": Vector2.DOWN })


func run(t: TestContext) -> void:
	Probe.gunfire(GUNFIRE)
	var door := Entry.FRONT
	var map := t.world.get_world_2d().navigation_map
	var plain := NavBuilder.route(map, START, GUNFIRE)
	var plain_len := NavBuilder.path_length(plain)
	# Round the east side of the house, the only other way: well past 2 x the plain route + 300 px.
	var round_len := NavBuilder.path_length(NavBuilder.route(map, START, Vector2(900, -100))) + NavBuilder.path_length(NavBuilder.route(map, Vector2(900, -100), Vector2(900, 600))) + NavBuilder.path_length(NavBuilder.route(map, Vector2(900, 600), GUNFIRE))
	if not t.require(round_len > View.AVOID_RATIO * plain_len + View.AVOID_SLACK, "set-up: no way round within the cap (plain %.0f px, round the house %.0f px)" % [plain_len, round_len]):
		return
	var inv := t.actor(&"inv")
	var there := func(): return inv.global_position.y > Maps.HOUSE_BOUNDS.end.y + 30.0
	var samples := await Entry.watch(t, [&"inv"], door, 75.0, there)
	var act := str(Entry.brain(t, &"inv").current_act())
	var went_in := Entry.path_of(samples, &"inv").any(func(p: Vector2): return Entry.in_room(door, p))
	if not t.require(there.call() and not went_in, "the invader went to the gunfire past the front door without going in (act %s, at %s)" % [act, inv.global_position.round()]):
		return
	var from_side := signf(Entry.lateral(door, START))
	var crossed := View.axis_crossed_at(samples, &"inv", door, from_side)
	if not t.require(crossed < INF, "set-up: the walk crossed the doorway's line of sight"):
		return
	var covered := View.time_covering(samples, &"inv", door, crossed)
	t.check(covered >= COVERED, "it covered the doorway from beside the jamb before it crossed its view (%.1f s, across at %.2f s)" % [covered, crossed])
	var span := View.crossing_span(t, samples, &"inv", door, crossed)
	var paused := View.longest_pause_in_view(t, samples, &"inv", door, 20.0, span[0], span[1])
	t.check(paused < NO_STOP, "it crossed the view without stopping (longest stop %.2f s, in the view %.2f to %.2f s)" % [paused, span[0], span[1]])
	var back := View.axis_crossed_at(samples.filter(func(s): return float(s["t"]) > span[1]), &"inv", door, -from_side)
	t.check(back == INF, "it crossed in one go, never back (back across at %.2f s)" % back)
	t.check(Entry.first_call_time(t, "claim", &"inv", door["id"]) == INF and Entry.first_call_time(t, "going_in", &"inv", door["id"]) == INF, "it secured the door without a claim or a crossing on the radio")
