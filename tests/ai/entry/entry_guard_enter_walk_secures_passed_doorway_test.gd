extends GameTest

## Desired (E15): the walk to a doorway's own stack passes other doors too. Ordered to ENTER room C from the corridor's west end,
## the invader goes past the open doors of rooms A and B on the way: it secures each once (a pass-by entry: stack beside the
## jamb, one side of the pie, nothing radioed), takes up its ENTER order again from the start, and stacks at C's door and goes in.
## A doorway it has secured is left alone while the order carries on, so each is secured exactly once. Scripted Von: SEARCH >
## ENTER > C's doorway.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## Seconds of gun through a doorway, from beside it, that count as having secured it.
const COVERED := 0.8
## A body's radius (px): abreast of a door means its centre is past the far jamb by this much.
const BODY := 14.0


func describe() -> Dictionary:
	return {
		"name": "The walk to a stack secures the doorways it passes",
		"description": "Ordered to ENTER room C down the corridor, the invader secures rooms A and B once each on the way, then stacks at C and goes in.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.spine(s, false)
	Entry.rules(s, Entry.SPINE_C)
	Entry.npc(s, &"inv", Vector2(60, 250))


func run(t: TestContext) -> void:
	var brain := Entry.brain(t, &"inv")
	var samples: Array = []
	var starts := {}
	var was := ""
	var end := t.time + 80.0
	while t.time < end and Entry.first_call_time(t, "going_in", &"inv", Entry.SPINE_C["id"]) == INF:
		samples.append({ "t": t.time, "pos": { &"inv": t.actor(&"inv").global_position }, "facing": { &"inv": t.actor(&"inv").facing } })
		var e := Entry.entry(brain)
		var key := "" if e.is_empty() else "%s|%s" % [e["opening"], e["secure"]]
		if key != "" and key != was:
			starts[key] = int(starts.get(key, 0)) + 1
		was = key
		await t.frames(1)
	if not t.require(Entry.asked(t, Entry.SPINE_C["id"]), "the order was ENTER for room C's doorway (act %s)" % brain.current_act()):
		return
	if not t.require(Entry.first_call_time(t, "going_in", &"inv", Entry.SPINE_C["id"]) < INF, "it stacked at room C's door and went in (act %s)" % brain.current_act()):
		return
	for door in [Entry.SPINE_A, Entry.SPINE_B]:
		var abreast := float(door["pos"].x) + float(door["width"]) * 0.5 + BODY
		var passed_at := INF
		for s in samples:
			if (s["pos"][&"inv"] as Vector2).x > abreast:
				passed_at = s["t"]
				break
		if not t.require(passed_at < INF, "%s was passed on the way" % door["id"]):
			return
		var before := samples.filter(func(s): return s["t"] <= passed_at)
		var covered := Entry.time_facing_through(before, &"inv", door, func(p: Vector2): return Entry.outward(door, p) > 0.0 and Entry.outward(door, p) < 90.0)
		t.check(covered >= COVERED, "%s was covered from beside its jamb before the invader was abreast of it (%.1f s)" % [door["id"], covered])
		t.expect_eq(int(starts.get("%s|true" % door["id"], 0)), 1, "%s was secured once, not again when the order carried on" % door["id"])
		t.check(Entry.first_call_time(t, "claim", &"inv", door["id"]) == INF, "%s was secured without a claim on the radio" % door["id"])
