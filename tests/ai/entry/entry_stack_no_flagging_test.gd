extends GameTest

## Desired (E12): nobody's gun line crosses a teammate. Three invaders stacked at the back door: a follower's muzzle is
## off the man in front of it (a gun line that passes within a body's radius of a teammate it could hit is a flag). Real
## Von: the three stand in the back garden and decide for themselves to stack on the back door.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const IDS := [&"a", &"b", &"c"]


func describe() -> Dictionary:
	return {
		"name": "Entry stack keeps its muzzles off teammates",
		"description": "Three invaders stacked at the back door never point their guns through the one in front.",
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
	var samples := await Entry.watch(t, IDS, door, 3.0)
	for id in IDS:
		var share := Entry.flagged_share(samples, id, IDS)
		t.check(share <= 0.1, "%s kept its muzzle off its teammates while stacked (on one %.0f%% of the time)" % [id, share * 100.0])
