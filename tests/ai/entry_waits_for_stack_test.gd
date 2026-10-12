extends GameTest

## Desired (E6): the point does not cross until every invader that claimed a slot holds it. A far, slow teammate
## arrives seconds after the point; the point's "going in" comes only after the teammate radioed ready.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry waits for the stack",
		"description": "The point holds at the back door until a slow teammate has reached its slot, then goes in.",
		"tags": ["ai", "entry", "scripted", "gap", "callout"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": 30.0 })
	Entry.npc(s, &"b", Vector2(990, 600), 0.55, { "entry_ready_timeout": 30.0 }, { "speed": 60.0 })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var gone := func(): return not Entry.calls(t, "going_in").is_empty()
	await Entry.watch(t, [&"a", &"b"], door, 55.0, gone)
	if not t.require(gone.call(), "someone went in (%s / %s)" % [Entry.brain(t, &"a").current_act(), Entry.brain(t, &"b").current_act()]):
		return
	var going_at := INF
	for e in t.events:
		if e["topic"] == &"callout" and String(e["data"].get("entry_step", "")) == "going_in":
			going_at = e["time"]
			break
	var ra := Entry.first_call_time(t, "ready", &"a")
	var rb := Entry.first_call_time(t, "ready", &"b")
	t.check(ra < INF and rb < INF, "both reached their slots (ready at %.1f / %.1f s)" % [ra, rb])
	t.check(going_at >= maxf(ra, rb), "the point went in only once both were ready (going in %.1f s)" % going_at)
	t.check(going_at - minf(ra, rb) >= 1.0, "the first to arrive waited for the other (%.1f s)" % (going_at - minf(ra, rb)))
