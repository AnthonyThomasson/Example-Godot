extends GameTest

## Desired (E15): a plain walk down a corridor goes past the open doors of rooms A and B. The guard secures each one before the
## invader is abreast of it, without entering: it stacks beside the jamb on the side it comes from, slices one side of the pie
## with its gun on the doorway, and walks on. Nothing is radioed for it (no claim, no going in). Scripted Von: an investigation
## of gunfire in the far room, heard before the invader's first decision, so the order is not an ENTER.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## Seconds of gun through a doorway, from beside it, that count as having secured it.
const COVERED := 0.8
## A body's radius (px): abreast of a door means its centre is past the far jamb by this much.
const BODY := 14.0


func describe() -> Dictionary:
	return {
		"name": "The entry guard secures a doorway passed in a corridor",
		"description": "Sent down the corridor by an investigation order, the invader covers rooms A and B from beside their jambs before it walks past their doors, without entering or radioing.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.spine(s, false)
	Entry.guard_rules(s, ["investigate"])
	Entry.npc(s, &"inv", Vector2(60, 250))


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	Probe.gunfire(Vector2(750, 100))
	var past_b := func(): return inv.global_position.x > 560.0
	var samples := await Entry.watch(t, [&"inv"], Entry.SPINE_C, 50.0, past_b)
	var act: String = str(Entry.brain(t, &"inv").current_act())
	if not t.require(Entry.asked(t, "investigate"), "the order was a plain investigation, not ENTER (act %s)" % act):
		return
	if not t.require(past_b.call(), "the invader walked past both doors (act %s)" % act):
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
		t.check(Entry.first_call_time(t, "going_in", &"inv", door["id"]) == INF, "%s was secured, not entered" % door["id"])
		t.check(Entry.first_call_time(t, "claim", &"inv", door["id"]) == INF, "%s was secured without a claim on the radio" % door["id"])
