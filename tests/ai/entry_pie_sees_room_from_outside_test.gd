extends GameTest

## Desired (E3): before it crosses, an invader slices the pie: it looks across the kitchen's back door in angle steps
## from outside and so sees at least half of the room (and both of its far corners) without setting foot inside. The
## corners it notes as still hidden are only ever on the door's own wall (a far corner is always in view of the pie).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry slices the pie from outside",
		"description": "Before going in, the invader sees half the kitchen and both far corners from outside the back door.",
		"tags": ["ai", "entry", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var samples := await Entry.watch(t, [&"inv"], door, 35.0, func(): return not Entry.calls(t, "going_in", &"inv").is_empty())
	if not t.require(not Entry.calls(t, "going_in", &"inv").is_empty(), "the invader radioed it was going in (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var e := Entry.entry(Entry.brain(t, &"inv"))
	t.check(Entry.path_of(samples, &"inv").all(func(p): return Entry.outward(door, p) > 0.0), "it stayed outside until then")
	t.check(float(e.get("seen_fraction", 0.0)) >= 0.5, "it saw at least half the room from outside (%.2f)" % float(e.get("seen_fraction", 0.0)))
	var corners := Entry.corners(door)
	var hidden: Array = e.get("hidden_corners", [])
	for c in corners["far"]:
		t.check(not hidden.any(func(h): return (h as Vector2).distance_to(c) < 60.0), "the far corner near %s was seen" % c)
	for h in hidden:
		t.check(corners["near"].any(func(c): return (h as Vector2).distance_to(c) < 60.0), "a corner noted as hidden (%s) is on the door's wall" % h)
