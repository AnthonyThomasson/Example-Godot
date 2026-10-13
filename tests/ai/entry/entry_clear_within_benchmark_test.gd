extends GameTest

## Desired (E10): a team clears an average room within the 5 to 6 second training target. Two invaders enter the
## furnished kitchen (an island, a counter, a fridge: corners to look round) by its back door: from the point's
## `going_in` to the `clear` call is 6 s at most. Real Von: the pair stand in
## the back garden and decide for themselves to enter.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const IDS := [&"a", &"b"]
## The training target (s) from the point crossing to the room called clear.
const BENCHMARK := 6.0


func describe() -> Dictionary:
	return {
		"name": "Entry clears the room within the benchmark",
		"description": "A pair entering the furnished kitchen call it clear within 6 s of the point going in.",
		"tags": ["ai", "entry", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(985, 110))


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var cleared := func(): return not Entry.calls(t, "clear").is_empty()
	await Entry.watch(t, IDS, door, 70.0, cleared)
	var acts := ", ".join(IDS.map(func(id): return Entry.brain(t, id).current_act()))
	if not t.require(IDS.all(func(id): return Entry.first_call_time(t, "claim", id, door["id"]) < INF), "both chose the back door (%s)" % acts):
		return
	if not t.require(cleared.call(), "the kitchen was called clear (%s)" % acts):
		return
	var going_at := INF
	var clear_at := INF
	for id in IDS:
		going_at = minf(going_at, Entry.first_call_time(t, "going_in", id, door["id"]))
		clear_at = minf(clear_at, Entry.first_call_time(t, "clear", id, door["id"]))
	if not t.require(going_at < INF, "the point radioed going in"):
		return
	t.check(clear_at - going_at <= BENCHMARK, "the room was clear within %.0f s of the point going in (took %.1f s)" % [BENCHMARK, clear_at - going_at])
