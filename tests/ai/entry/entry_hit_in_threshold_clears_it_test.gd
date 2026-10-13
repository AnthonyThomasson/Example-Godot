extends GameTest

## Desired (E4): an invader hit while crossing the back door finishes the crossing: it carries on into the kitchen
## and off the door's axis rather than stopping or backing out, and only then turns to the fight. The defender fires
## once the invader is past the wall plane, still in the doorway.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry hit in the funnel finishes the crossing",
		"description": "A defender hidden in a door-wall corner shoots the invader in the doorway; it carries on into the room.",
		"tags": ["ai", "entry", "scripted", "combat"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))
	# Tucked against the east wall south of the door: unseen from the stack, the pie and the walk there (the jamb is
	# in the way from every spot outside), but with a line along the wall to the inside of the threshold.
	Entry.target(s, &"defender", Vector2(818, 330), Maps.DOOR_BACK, { "start_slot": 3 })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var inv := t.actor(&"inv")
	var gunman := t.puppet(&"defender")
	gunman.aim_at(inv)
	var hit_inv := func(d): return d.get("victim") == inv
	var last_shot := [-1.0]
	var samples := await Entry.watch(t, [&"inv"], door, 40.0, func():
		var p: Vector2 = inv.global_position
		if not t.happened(&"hit", hit_inv) and Entry.in_funnel(door, p) and Entry.outward(door, p) < 0.0 and t.time - last_shot[0] >= 0.15:
			gunman.shoot()
			last_shot[0] = t.time
		var landed := _hit_times(t, hit_inv)
		return not landed.is_empty() and t.time - landed[0] >= 3.0)
	var hits := _hit_times(t, hit_inv)
	if not t.require(not hits.is_empty(), "the defender hit the invader in the doorway (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	var at := Entry.pos_at(samples, &"inv", hits[0])
	t.check(Entry.in_funnel(door, at) or Entry.outward(door, at) < 0.0, "the hit landed as it crossed (%s)" % at.round())
	var after := samples.filter(func(s): return s["t"] >= hits[0])
	t.check(after.all(func(s): return Entry.outward(door, s["pos"][&"inv"]) <= Entry.FUNNEL_DEPTH), "it never backed out of the doorway")
	var through := after.filter(func(s): return s["t"] <= hits[0] + 3.0 and Entry.in_room(door, s["pos"][&"inv"]) and not Entry.in_funnel(door, s["pos"][&"inv"]))
	t.check(not through.is_empty(), "within 3 s it was through, in the room and off the doorway")


## The sim times of the hits on the invader, in order.
func _hit_times(t: TestContext, hit_inv: Callable) -> Array:
	var out: Array = []
	for e in t.events:
		if e["topic"] == &"hit" and hit_inv.call(e["data"]):
			out.append(e["time"])
	return out
