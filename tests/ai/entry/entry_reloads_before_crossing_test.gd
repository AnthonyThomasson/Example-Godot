extends GameTest

## E11: an entrant crosses with a topped-off gun. Its magazine is part spent (7 of 12, above the band Von
## calls low, so nothing but the entry itself has a reason to reload): the swap happens while it is stacked, the one
## lull, and never in the threshold. Real Von: the invader stands in the back garden and decides for itself how to get
## into the kitchen.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry reloads at the stack, never in the funnel",
		"description": "An invader with a part-spent magazine tops it off while stacked at the back door and crosses with a full gun.",
		"tags": ["ai", "entry", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"inv", &"invader", Vector2(960, 60), { "start_rounds": 7 })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var inv := t.actor(&"inv")
	var capacity: int = inv.ammo_capacity(inv.gun_slot())
	var going := func(): return Entry.first_call_time(t, "going_in", &"inv", door["id"]) < INF
	await Entry.watch(t, [&"inv"], door, 60.0, going)
	var act: String = str(Entry.brain(t, &"inv").current_act())
	if not t.require(Entry.first_call_time(t, "claim", &"inv", door["id"]) < INF, "the invader chose to enter by the back door (act %s)" % act):
		return
	if not t.require(going.call(), "it went in (act %s)" % act):
		return
	var ammo_at_cross: int = inv.ammo()
	var through := func(): return Entry.first_call_time(t, "in", &"inv", door["id"]) < INF
	await Entry.watch(t, [&"inv"], door, 8.0, through)
	var ready_at := Entry.first_call_time(t, "ready", &"inv", door["id"])
	var going_at := Entry.first_call_time(t, "going_in", &"inv", door["id"])
	var in_at := Entry.first_call_time(t, "in", &"inv", door["id"])
	var topped_off_at := INF
	var reloading_in_funnel := false
	for e in t.events:
		if e["topic"] != &"reload" or e["data"].get("character") != inv:
			continue
		var stage: StringName = e["data"].get("stage", &"")
		if stage == &"done" and e["time"] >= ready_at and e["time"] <= going_at and topped_off_at == INF:
			topped_off_at = e["time"]
		if stage == &"start" and e["time"] >= going_at and e["time"] <= in_at:
			reloading_in_funnel = true
	t.check(topped_off_at < INF, "it topped its gun off while stacked (ready %.1f s, going in %.1f s, no reload between)" % [ready_at, going_at])
	t.check(ammo_at_cross == capacity, "it crossed with a full magazine (%d of %d rounds)" % [ammo_at_cross, capacity])
	t.check(not reloading_in_funnel, "it did not start a reload while crossing the threshold")
