extends GameTest

## Desired (E12): while the stack waits at the door, the last man faces back the way the team came and holds the
## approach (the point, meanwhile, is slicing the pie). Real Von: three invaders in the back garden decide for themselves
## to stack on the back door.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const IDS := [&"a", &"b", &"c"]


func describe() -> Dictionary:
	return {
		"name": "Entry stack's last man covers the rear",
		"description": "Of three invaders stacked at the back door, the last faces back along the wall, not the door.",
		"tags": ["ai", "entry", "gap", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", Vector2(960, 40))
	s.actor(&"b", &"invader", Vector2(985, 100))
	s.actor(&"c", &"invader", Vector2(990, 280))


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var all_ready := func(): return IDS.all(func(id): return Entry.first_call_time(t, "ready", id, door["id"]) < INF)
	await Entry.watch(t, IDS, door, 55.0, all_ready)
	var acts := ", ".join(IDS.map(func(id): return Entry.brain(t, id).current_act()))
	if not t.require(IDS.all(func(id): return Entry.first_call_time(t, "claim", id, door["id"]) < INF), "all three chose the back door (%s)" % acts):
		return
	if not t.require(all_ready.call(), "all three reached their slots (%s)" % acts):
		return
	var by_slot := {}
	for id in IDS:
		by_slot[int(Entry.entry(Entry.brain(t, id)).get("slot", 0))] = id
	if not t.require(by_slot.has(1) and by_slot.has(2) and by_slot.has(3), "slots 1, 2 and 3 are taken once each (%s)" % str(by_slot)):
		return
	var samples := await Entry.watch(t, IDS, door, 3.0)
	var away_from_door := func(id: StringName) -> float:
		return Entry.share_facing(samples, id, func(p: Vector2, f: Vector2): return f.dot(((door["pos"] as Vector2) - p).normalized()) <= 0.0)
	t.check(away_from_door.call(by_slot[3]) >= 0.6, "the last man (%s) faces back along the wall, away from the door (%.0f%% of the time)" % [by_slot[3], away_from_door.call(by_slot[3]) * 100.0])
