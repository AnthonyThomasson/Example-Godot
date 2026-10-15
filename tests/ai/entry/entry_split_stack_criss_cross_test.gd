extends GameTest

## E19 (issue #51, R4): a split stack and the criss-cross. Two invaders come at the Terrace house's back door from opposite sides of
## the garden, one north of it and one south. A member that would have to cross the door's view to reach the stack side stacks on its
## own side instead (the claim carries the side), so each stands on its own side of the door and neither walks through its view before
## the entry. Each side's front man slices its own half of the pie; the point (the first claimer) crosses to the corner on the far
## side, and the other side's front man, after the point's `in`, to the opposite corner. Real Von: both invaders decide for
## themselves; a `require` that both claimed the back door comes first, so a different Von choice reads as a set-up finding.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const IDS := [&"north", &"south"]


func describe() -> Dictionary:
	return {
		"name": "Two invaders on opposite sides of a door stack on their own sides and criss-cross",
		"description": "Coming at the back door from north and south, each invader stacks on its own side without crossing the door's view, each slices its own half of the pie, then the point crosses to the far corner and the other to the opposite one.",
		"tags": ["ai", "entry", "stack", "door_view", "von"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"north", &"invader", Vector2(980, -40), { "facing": Vector2.LEFT })
	s.actor(&"south", &"invader", Vector2(980, 420), { "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	if not t.require(IDS.all(func(id): return not View.in_view(t, door, t.actor(id).global_position, 0.0)), "set-up: neither invader starts in the back door's view"):
		return
	var phases := { &"north": [], &"south": [] }
	var samples: Array = []
	var both_in := func(): return IDS.all(func(id): return Entry.first_call_time(t, "in", id, door["id"]) < INF)
	var end := t.time + 100.0
	while t.time < end and not both_in.call():
		var pos := {}
		var facing := {}
		for id in IDS:
			pos[id] = t.actor(id).global_position
			facing[id] = t.actor(id).facing
			phases[id].append([t.time, str(Entry.entry(Entry.brain(t, id)).get("phase", ""))])
		samples.append({ "t": t.time, "pos": pos, "facing": facing })
		await t.frames(1)
	var settle_end := t.time + 3.0
	while t.time < settle_end:
		var pos := {}
		var facing := {}
		for id in IDS:
			pos[id] = t.actor(id).global_position
			facing[id] = t.actor(id).facing
		samples.append({ "t": t.time, "pos": pos, "facing": facing })
		await t.frames(1)
	var claimed := IDS.all(func(id): return Entry.first_call_time(t, "claim", id, door["id"]) < INF)
	if not t.require(claimed, "both invaders claimed the back door (acts %s, %s)" % [Entry.brain(t, &"north").current_act(), Entry.brain(t, &"south").current_act()]):
		return

	# Each stacks on its own side: where it stood when it radioed ready, and the side its claim carries.
	var ready_at := {}
	for id in IDS:
		var readies := Entry.calls(t, "ready", id).filter(func(c): return String(c.get("opening", "")) == door["id"])
		ready_at[id] = readies[0]["position"] if not readies.is_empty() else Vector2.INF
	t.check(ready_at[&"north"] != Vector2.INF and Entry.lateral(door, ready_at[&"north"]) > 0.0, "the north invader stacked north of the door (ready at %s)" % str(ready_at[&"north"]))
	t.check(ready_at[&"south"] != Vector2.INF and Entry.lateral(door, ready_at[&"south"]) < 0.0, "the south invader stacked south of the door, on its own side (ready at %s)" % str(ready_at[&"south"]))
	var sides := IDS.map(func(id):
		var mine := Entry.calls(t, "claim", id).filter(func(c): return String(c.get("opening", "")) == door["id"])
		return mine.back().get("side", 0) if not mine.is_empty() else 0)
	t.check(sides[0] != sides[1], "their claims carry different sides (%s)" % str(sides))

	# Neither crossed the door's view before the entry: outside, each kept to its own side of the door's axis until it went in (its
	# own pie arc lies in the view on its side, so being in the view is not the test; walking across the axis through it is).
	for id in IDS:
		var own_side := signf(Entry.lateral(door, ready_at[id])) if ready_at[id] != Vector2.INF else (1.0 if id == &"north" else -1.0)
		var going := Entry.first_call_time(t, "going_in", id, door["id"])
		var crossed_at := INF
		for s in samples:
			if float(s["t"]) >= going:
				break
			var p: Vector2 = s["pos"][id]
			if Entry.outward(door, p) > 0.0 and View.in_view(t, door, p) and signf(Entry.lateral(door, p)) == -own_side and absf(Entry.lateral(door, p)) > 20.0:
				crossed_at = s["t"]
				break
		t.check(crossed_at == INF, "%s never crossed the back door's view to the other side before it went in (across at %.2f s, going_in at %.2f s)" % [id, crossed_at, going])
		t.check(phases[id].any(func(p): return p[1] == "pie"), "%s sliced its own half of the pie" % id)

	# The criss-cross: the point (first claimer) to the far side's corner, then the other side's front man to the opposite one.
	var point_id: StringName = &"north" if Entry.first_call_time(t, "claim", &"north", door["id"]) <= Entry.first_call_time(t, "claim", &"south", door["id"]) else &"south"
	var other_id: StringName = &"south" if point_id == &"north" else &"north"
	var point_going := Entry.first_call_time(t, "going_in", point_id, door["id"])
	var point_in := Entry.first_call_time(t, "in", point_id, door["id"])
	var other_going := Entry.first_call_time(t, "going_in", other_id, door["id"])
	t.check(point_going < INF and point_going <= other_going, "the point (%s, the first claimer) went in first" % point_id)
	t.check(other_going < INF and other_going >= point_in - 0.05, "the other side's front man went in after the point's in (going_in at %.2f s, in at %.2f s)" % [other_going, point_in])
	for id in IDS:
		var own_side := signf(Entry.lateral(door, ready_at[id])) if ready_at[id] != Vector2.INF else 0.0
		var corner := Entry.first_stop_in_room(samples, id, door)
		t.check(corner != Vector2.INF and own_side != 0.0 and signf(Entry.lateral(door, corner)) == -own_side, "%s crossed to the corner on the far side from its stack (stacked %s, stopped at %s)" % [id, "north" if own_side > 0.0 else "south", str(corner.round()) if corner != Vector2.INF else "nowhere"])
