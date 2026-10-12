extends GameTest

## Desired (E1): an invader standing in the garden straight out from the front door does not walk down the line that
## looks through it. It steps off the door's axis while still well out, then arrives along the wall to its staging
## point beside the door.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(-130, 415)   # straight out from the front door, 130 px off the wall
## Close to the wall: within this distance (px) the axis is the line a shooter inside looks down.
const NEAR := 100.0


func describe() -> Dictionary:
	return {
		"name": "Entry approach stays off the door axis",
		"description": "Starting on the front door axis, the invader leaves the axis before it is within 100 px of the wall and comes in along the wall.",
		"tags": ["ai", "entry", "scripted", "gap"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.FRONT)
	Entry.npc(s, &"inv", START)


func run(t: TestContext) -> void:
	var door := Entry.FRONT
	var samples := await Entry.watch(t, [&"inv"], door, 20.0, func(): return not Entry.calls(t, "ready", &"inv").is_empty())
	var ready_at := Entry.first_call_time(t, "ready", &"inv")
	if not t.require(ready_at < INF, "the invader reached a stack slot and radioed ready (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var on_axis := Entry.path_of(samples, &"inv").filter(func(p): return _near_axis(door, p))
	t.check(on_axis.is_empty(), "it never walks the door's axis close to the wall (%d samples, first %s)" % [on_axis.size(), on_axis[0].round() if not on_axis.is_empty() else ""])
	var at := Entry.pos_at(samples, &"inv", ready_at)
	t.check(Entry.beside_door(door, at), "it ends beside the door (%s)" % at.round())


## Whether `p` is on the door's axis (within its width plus a body) and close to the wall, on the outside.
func _near_axis(door: Dictionary, p: Vector2) -> bool:
	var o := Entry.outward(door, p)
	return o > 0.0 and o <= NEAR and absf(Entry.lateral(door, p)) < float(door["width"]) * 0.5 + 10.0
