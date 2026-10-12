extends GameTest

## Desired (E4): once it commits to crossing, an invader keeps moving until it is through the back door and off its
## axis: it never stands still in the funnel.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry never stops in the funnel",
		"description": "Crossing the back door the invader never stands still in the doorway.",
		"tags": ["ai", "entry", "scripted"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var inside_for := [0.0]
	var samples := await Entry.watch(t, [&"inv"], door, 40.0, func():
		inside_for[0] = inside_for[0] + 1.0 / 60.0 if Entry.in_room(door, t.actor(&"inv").global_position) else 0.0
		return inside_for[0] >= 1.5)
	if not t.require(Entry.path_of(samples, &"inv").any(func(p): return Entry.in_room(door, p)), "the invader went into the kitchen (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var pause := Entry.longest_pause_in_funnel(samples, &"inv", door)
	t.check(pause < 0.1, "it never stood still in the doorway (longest pause %.2f s)" % pause)
