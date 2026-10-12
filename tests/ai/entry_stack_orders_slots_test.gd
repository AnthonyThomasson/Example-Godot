extends GameTest

## Desired (E2): three invaders heading for the kitchen's back door take one slot each over the radio (1, 2, 3) and
## queue in single file on one side of the door, against the wall, slot 1 nearest the door and each a body's width
## behind the one in front; none stands in the doorway's line of sight.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry stack orders the slots",
		"description": "Three invaders stack on one side of the back door in slot order, a body apart, out of its line of sight.",
		"tags": ["ai", "entry", "scripted", "gap", "callout"],
		"timeout": 35.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 40), 0.4, { "entry_ready_timeout": 30.0 })
	Entry.npc(s, &"b", Vector2(985, 100), 0.55, { "entry_ready_timeout": 30.0 })
	Entry.npc(s, &"c", Vector2(990, 280), 0.7, { "entry_ready_timeout": 30.0 })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var ids := [&"a", &"b", &"c"]
	var all_ready := func(): return ids.all(func(id): return not Entry.calls(t, "ready", id).is_empty())
	await Entry.watch(t, ids, door, 30.0, all_ready)
	if not t.require(all_ready.call(), "all three reached their slots (%s)" % ", ".join(ids.map(func(id): return Entry.brain(t, id).current_act()))):
		return
	var by_slot := {}
	for id in ids:
		var e := Entry.entry(Entry.brain(t, id))
		by_slot[int(e.get("slot", 0))] = { "id": id, "point": e.get("stack_point", Vector2.INF) }
	if not t.require(by_slot.keys().size() == 3 and by_slot.has(1) and by_slot.has(2) and by_slot.has(3), "slots 1, 2 and 3 are taken once each (%s)" % str(by_slot.keys())):
		return
	var side := signf(Entry.lateral(door, by_slot[1]["point"]))
	for slot in [1, 2, 3]:
		var p: Vector2 = by_slot[slot]["point"]
		t.check(Entry.beside_door(door, p), "slot %d is against the wall beside the door (%s)" % [slot, p.round()])
		t.check(signf(Entry.lateral(door, p)) == side, "slot %d is on the same side as slot 1" % slot)
	for slot in [2, 3]:
		var front: Vector2 = by_slot[slot - 1]["point"]
		var back: Vector2 = by_slot[slot]["point"]
		t.check(absf(Entry.lateral(door, back)) > absf(Entry.lateral(door, front)), "slot %d is behind slot %d" % [slot, slot - 1])
		t.check(back.distance_to(front) >= 28.0, "slot %d is a body's width behind slot %d (%.0f px)" % [slot, slot - 1, back.distance_to(front)])
		var stood: Vector2 = t.actor(by_slot[slot]["id"]).global_position
		t.check(stood.distance_to(back) <= 24.0, "the slot %d invader stands in its slot (%.0f px off)" % [slot, stood.distance_to(back)])
