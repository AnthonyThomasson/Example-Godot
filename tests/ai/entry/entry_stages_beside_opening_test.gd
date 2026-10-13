extends GameTest

## Desired (E1): heading for the kitchen's back door from the garden, an invader goes to a staging point beside the
## opening, against the outside of the wall and clear of the doorway's view into the room, and radios that it is
## ready there. It never sets foot in the doorway or the room on the way.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(960, 60)


func describe() -> Dictionary:
	return {
		"name": "Entry stages beside the opening",
		"description": "From the garden the invader stops against the wall beside the back door, out of its line of sight, before going in.",
		"tags": ["ai", "entry", "scripted"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", START)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var samples := await Entry.watch(t, [&"inv"], door, 20.0, func(): return not Entry.calls(t, "ready", &"inv").is_empty())
	var ready_at := Entry.first_call_time(t, "ready", &"inv")
	if not t.require(ready_at < INF, "the invader reached a stack slot and radioed ready (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var at := Entry.pos_at(samples, &"inv", ready_at)
	t.check(Entry.beside_door(door, at), "it stages against the wall beside the door, out of its view (%s: out %.0f, along %.0f)" % [at.round(), Entry.outward(door, at), Entry.lateral(door, at)])
	t.check(not Entry.path_of(samples, &"inv").any(func(p): return Entry.in_room(door, p) or Entry.in_funnel(door, p)),
		"it never set foot in the doorway or the room on the way")
