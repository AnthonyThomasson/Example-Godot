extends GameTest

## Desired (E1 to E5): an invader entering a room never runs, from the moment it heads for the door until it is in
## its corner. A running character cannot shoot (`Character.shoot()` is ignored while running), so a sprint to the
## stack or through the doorway is a lowered gun at the worst moment. It starts far from the kitchen's back door,
## well past the distance from which a run would start.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(990, 600)   # far south-east in the garden; the stack forms north of the door


func describe() -> Dictionary:
	return {
		"name": "Entry never runs",
		"description": "From far out in the garden, the invader walks to the back door's stack and through it without ever running.",
		"tags": ["ai", "entry", "scripted"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", START)


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var ran := [0.0]
	var done := func():
		if inv.is_running():
			ran[0] += 1.0 / 60.0
		t.trace("running", 1.0 if inv.is_running() else 0.0)
		var at := Entry.first_call_time(t, "in", &"inv")
		return at < INF and t.time - at > 2.0
	if not t.require(await t.until(done, 40.0), "the invader went in and reached its corner (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(ran[0] == 0.0, "it never ran on the way in (ran for %.2f s)" % ran[0])
