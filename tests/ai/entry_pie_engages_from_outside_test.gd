extends GameTest

## Desired (E3): a defender inside the kitchen, out of sight of the stack but in view of the pie, is seen while the
## invader slices the pie and engaged from outside: the invader's first shot leaves from outside the wall, after it
## reached its slot.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry engages what the pie reveals from outside",
		"description": "A defender seen through the back door during the pie is shot at from outside the kitchen.",
		"tags": ["ai", "entry", "scripted", "gap", "combat"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))
	# Hidden from the north stack slot and the walk down the wall, in view from the pie arc.
	Entry.target(s, &"defender", Vector2(560, 215), Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var inv := t.actor(&"inv")
	var shot_by_inv := func(d): return d.get("attacker") == inv
	await Entry.watch(t, [&"inv"], door, 35.0, func(): return t.happened(&"shot", shot_by_inv))
	var first := {}
	for e in t.events:
		if e["topic"] == &"shot" and shot_by_inv.call(e["data"]):
			first = e
			break
	if not t.require(not first.is_empty(), "the invader fired at the defender (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var ready_at := Entry.first_call_time(t, "ready", &"inv")
	t.check(ready_at <= float(first["time"]), "it had reached its slot before it saw and shot (ready %.1f s, shot %.1f s)" % [ready_at, first["time"]])
	var muzzle: Vector2 = first["data"].get("position", Vector2.ZERO)
	t.check(Entry.outward(door, muzzle) > 0.0, "the shot left from outside the wall (%s)" % muzzle.round())
