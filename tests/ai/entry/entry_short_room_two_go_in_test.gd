extends GameTest

## Desired (E13): a room too small for the team is entered by two; the rest hold outside. Three invaders in a corridor
## with one small room off it (140 px square, barely three bodies across): two go in and take its corners, the third
## stays on the stack side as security and never steps into the doorway. Real Von: the three decide for themselves to
## enter the one room their corridor leads to.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const IDS := [&"a", &"b", &"c"]


func describe() -> Dictionary:
	return {
		"name": "Entry into a short room takes two, the rest hold outside",
		"description": "Three invaders at a small room's door: only two enter, the third holds the corridor side.",
		"tags": ["ai", "entry", "gap", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.box_room(s)
	s.actor(&"a", &"invader", Vector2(70, 250))
	s.actor(&"b", &"invader", Vector2(110, 250))
	s.actor(&"c", &"invader", Vector2(150, 250))


func run(t: TestContext) -> void:
	var door := Entry.BOX
	var cleared := func(): return _clear_time(t) < INF
	var samples := await Entry.watch(t, IDS, door, 80.0, func(): return cleared.call() and t.time - _clear_time(t) > 2.0)
	var acts := ", ".join(IDS.map(func(id): return Entry.brain(t, id).current_act()))
	if not t.require(IDS.all(func(id): return Entry.first_call_time(t, "claim", id, door["id"]) < INF), "all three chose to enter the box room (%s)" % acts):
		return
	if not t.require(cleared.call(), "the room was called clear (%s)" % acts):
		return
	var inside := IDS.filter(func(id): return Entry.first_call_time(t, "in", id, door["id"]) < INF)
	t.check(inside.size() <= 2, "no more than two went into the short room (%s did)" % ", ".join(inside))
	for id in IDS:
		if inside.has(id):
			continue
		t.expect_eq(Entry.funnel_entries(samples, id, door), 0, "%s, holding outside, never stepped into the doorway" % id)
		t.check(Entry.outward(door, t.actor(id).global_position) > 0.0, "%s is still on the corridor side once the room is clear" % id)


## Sim time of the first `clear` callout about the box room (INF before one).
func _clear_time(t: TestContext) -> float:
	for e in t.events:
		if e["topic"] == &"callout" and String(e["data"].get("entry_step", "")) == "clear" and String(e["data"].get("opening", "")) == Entry.BOX["id"]:
			return e["time"]
	return INF
