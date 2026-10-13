extends GameTest

## Desired (E16): a doorway passed in a corridor is searched or secured before the NPC is abreast of it. Gunfire is
## heard from the far room of the corridor spine; whatever Von sends the invader there for, the way runs past the open
## doors of rooms A and B, and each is entered, or at least covered from beside its jamb, before the invader walks
## past it. Real Von: the invader hears the shots and decides for itself.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
## Seconds of gun through a doorway, from beside it, that count as having secured it.
const COVERED := 0.8
## A body's radius (px): abreast of a door means its centre is past the far jamb by this much.
const BODY := 14.0


func describe() -> Dictionary:
	return {
		"name": "Entry secures the doorways it passes in a corridor",
		"description": "Drawn down the corridor by gunfire in the far room, the invader enters or covers rooms A and B before walking past their doors.",
		"tags": ["ai", "entry", "gap", "von"],
		"requires_von": true,
		"timeout": 100.0,
	}


func configure(s: TestSetup) -> void:
	Maps.spine(s, false)
	s.actor(&"inv", &"invader", Vector2(60, 250))


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	await t.seconds(1.0)
	Probe.gunfire(Vector2(750, 100))
	var in_c := func(): return Maps.SPINE_ROOM_C.grow(-30).has_point(inv.global_position)
	var samples := await Entry.watch(t, [&"inv"], Entry.SPINE_C, 90.0, in_c)
	var act: String = str(Entry.brain(t, &"inv").current_act())
	var far_jamb := float(Entry.SPINE_A["pos"].x) + float(Entry.SPINE_A["width"]) * 0.5 + BODY
	var passed_a := Entry.path_of(samples, &"inv").any(func(p: Vector2): return p.x > far_jamb)
	if not t.require(passed_a, "the gunfire drew the invader down the corridor past room A's door (act %s)" % act):
		return
	for door in [Entry.SPINE_A, Entry.SPINE_B]:
		var abreast := float(door["pos"].x) + float(door["width"]) * 0.5 + BODY
		var passed_at := INF
		for s in samples:
			if s["pos"].has(&"inv") and (s["pos"][&"inv"] as Vector2).x > abreast:
				passed_at = s["t"]
				break
		if passed_at == INF:
			continue  # Never walked past it: nothing was left behind.
		var before := samples.filter(func(s): return s["t"] <= passed_at)
		var entered := Entry.first_call_time(t, "going_in", &"inv", door["id"]) <= passed_at
		var covered := Entry.time_facing_through(before, &"inv", door, func(p: Vector2): return Entry.outward(door, p) > 0.0 and Entry.outward(door, p) < 90.0)
		t.check(entered or covered >= COVERED, "%s was searched or secured before the invader walked past it (entered: %s, gun through it from beside: %.1f s)" % [door["id"], entered, covered])
