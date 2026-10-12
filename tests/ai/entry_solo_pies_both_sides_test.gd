extends GameTest

## Desired (E7): an invader with no ally in radio range slices the pie from one side of the back door and then the
## other before it goes in.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Solo entry pies both sides",
		"description": "Alone, the invader looks into the kitchen from both sides of the back door before crossing.",
		"tags": ["ai", "entry", "scripted", "gap"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var samples := await Entry.watch(t, [&"inv"], door, 35.0, func(): return not Entry.calls(t, "going_in", &"inv").is_empty())
	if not t.require(not Entry.calls(t, "going_in", &"inv").is_empty(), "the invader went in (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var e := Entry.entry(Entry.brain(t, &"inv"))
	t.check(bool(e.get("solo", false)), "it entered alone")
	t.expect_eq(int(e.get("pie_sides", 0)), 2, "it sliced the pie from both sides")
	var half := float(door["width"]) * 0.5
	var near := Entry.path_of(samples, &"inv").filter(func(p): return Entry.outward(door, p) > 0.0 and Entry.outward(door, p) < 160.0 and absf(Entry.lateral(door, p)) < 160.0)
	t.check(near.any(func(p): return Entry.lateral(door, p) > half), "it looked in from one side")
	t.check(near.any(func(p): return Entry.lateral(door, p) < -half), "and from the other")
