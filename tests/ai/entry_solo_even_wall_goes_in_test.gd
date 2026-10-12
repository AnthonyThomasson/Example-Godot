extends GameTest

## Desired (E7): a lone invader at a door with as much wall on either side (the Terrace house's front door into the
## hall) slices the pie from both sides and goes in. Crossing in front of the door to its second side must not make
## it start over from the other side's stack (it once looped there for good).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Solo entry at an even wall goes in",
		"description": "Alone at the front door, which has the same wall either side, the invader pies both sides and crosses.",
		"tags": ["ai", "entry", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.FRONT)
	Entry.npc(s, &"inv", Vector2(-130, 300))


func run(t: TestContext) -> void:
	await Entry.watch(t, [&"inv"], Entry.FRONT, 35.0, func(): return not Entry.calls(t, "in", &"inv").is_empty())
	t.check(not Entry.calls(t, "going_in", &"inv").is_empty(), "it went in (act %s, phase %s)" % [Entry.brain(t, &"inv").current_act(),
		Entry.entry(Entry.brain(t, &"inv")).get("phase", "")])
