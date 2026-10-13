extends GameTest

## Desired (E15): a hostile seen through the door is fought from outside, and nobody crosses while it stands in view.
## A defender in the kitchen, out of sight of the stack but in view of the pie, is seen and shot at from outside; it
## cannot be killed and does not move, so the invader must never go in: not by the entry, and not by whatever fight Von
## chooses once it has engaged. Real Von: the invader stands in the back garden and decides for itself.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry holds outside while a hostile is in view",
		"description": "An invader that sees a defender through the back door engages it from outside and does not cross while it stands.",
		"tags": ["ai", "entry", "gap", "von"],
		"requires_von": true,
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"inv", &"invader", Vector2(960, 60))
	# Hidden from the north stack slot and the walk down the wall, in view from the pie arc.
	Entry.target(s, &"defender", Vector2(560, 215), Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var inv := t.actor(&"inv")
	var shot_by_inv := func(d): return d.get("attacker") == inv
	var going := func(): return Entry.first_call_time(t, "going_in", &"inv", door["id"]) < INF
	var samples := await Entry.watch(t, [&"inv"], door, 45.0, func(): return going.call() or Entry.funnel_entries([], &"inv", door) > 0)
	var act: String = str(Entry.brain(t, &"inv").current_act())
	if not t.require(Entry.first_call_time(t, "claim", &"inv", door["id"]) < INF, "the invader chose to enter by the back door (act %s)" % act):
		return
	if not t.require(t.happened(&"shot", shot_by_inv), "it saw the defender and fired at it (act %s)" % act):
		return
	t.check(not going.call(), "it never committed to the crossing with the defender standing in view (act %s)" % act)
	t.expect_eq(Entry.funnel_entries(samples, &"inv", door), 0, "it never stepped into the doorway")
	t.check(not Entry.in_room(door, inv.global_position), "it is still outside the kitchen (%s)" % inv.global_position.round())
