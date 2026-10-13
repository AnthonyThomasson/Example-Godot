extends GameTest

## G17, the `throw` primitive (amended: "frag out, take cover"): the leaf selects the grenade, aims at the spot, throws, radios `frag out` / `bang
## out`, then takes whichever safety is nearer and holds it until the detonation, switches back to the gun and re-decides. One mechanism, scripted Von
## picks GRENADE, in two walled rooms:
## - an invader with a frag and a pistol, a hostile hidden behind a desk 420 px off (outside the blast's reach: nothing to take cover from);
## - an invader with a frag, a hostile hidden behind a couch 200 px off (inside a frag's zone) and the couch at its elbow: it must crouch behind it
##   from the throw to the bang, take no blast, and then be on its pistol.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const FAR_N := Vector2(100, 150)
const FAR_H := Vector2(520, 150)
const NEAR_N := Vector2(500, 450)
const NEAR_H := Vector2(700, 450)


func describe() -> Dictionary:
	return {
		"name": "The throw primitive throws, calls it, takes cover and returns to the gun",
		"description": "Von picks GRENADE twice: the invader 420 px off throws, radios frag out and is on its pistol after the bang; the one 200 px off throws, crouches behind its couch until the bang, takes no blast and is on its pistol after it. Both ask Von again.",
		"tags": ["ai", "grenade", "combat", "cover", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 900, 300) },
		{ "key": "south", "type": "kitchen", "rect": Rect2(0, 300, 900, 300) },
	], [{ "pos": Vector2(880, 0), "width": 60.0 }, { "pos": Vector2(880, 600), "width": 60.0 }])
	s.object(&"desk", "desk", Vector2(330, 150))
	s.object(&"couch", "sofa", Vector2(600, 450))
	Flank.rules(s, [{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	Flank.npc(s, &"far", FAR_N, {}, &"invader", FAR_H)
	Probe.hostile(s, &"far_h", FAR_H, FAR_N)
	Flank.npc(s, &"near", NEAR_N, {}, &"invader", NEAR_H)
	Probe.hostile(s, &"near_h", NEAR_H, NEAR_N)


func run(t: TestContext) -> void:
	var far := t.actor(&"far")
	var near := t.actor(&"near")
	Probe.arm(far, 0, 1)
	Probe.arm(near, 0, 1)
	if not t.require(Probe.count(far, Probe.FRAG) == 1 and Probe.count(near, Probe.FRAG) == 1 and far.current_slot() == Probe.PISTOL, "both invaders carry a frag and hold their pistol (item_count(8) = %d, %d)" % [Probe.count(far, Probe.FRAG), Probe.count(near, Probe.FRAG)]):
		return
	var far_brain := t.controller(&"far", &"current_act")
	var near_brain := t.controller(&"near", &"current_act")
	var chose := await t.until(func(): return str(far_brain.current_act()).contains("grenade") and str(near_brain.current_act()).contains("grenade"), 10.0)
	if not t.require(chose, "Von's GRENADE pick became both running orders (acting: %s / %s)" % [str(far_brain.current_act()), str(near_brain.current_act())]):
		return
	var held := { &"far": false, &"near": false }
	var posture := []  # the near invader's posture each frame from its throw to the bang
	var thrown := await t.until(func():
		for id in held:
			held[id] = held[id] or t.actor(id).current_slot() == Probe.FRAG
		return t.happened(&"throw", func(d): return d.get("attacker") == near) and t.happened(&"throw", func(d): return d.get("attacker") == far), 8.0)
	if not t.require(thrown, "both invaders threw their grenade"):
		return
	t.check(held[&"far"] and held[&"near"], "each took the grenade in hand to throw it")
	for id in [&"far", &"near"]:
		var who: Node = t.actor(id)
		t.check(Probe.raw(t, &"throw", func(d): return d.get("attacker") == who)[0]["data"].get("kind") == &"frag", "%s threw its frag" % id)
		t.check(not Probe.callouts(t, &"frag_out", id).is_empty(), "and radioed frag out")
	var end := t.time + 8.0
	while Probe.booms(t, &"frag").size() < 2 and t.time < end:
		posture.append({ "t": t.time, "posture": near.posture() })
		await t.frames(1)
	if not t.require(Probe.booms(t, &"frag").size() >= 2, "both frags went off"):
		return
	var booms := Probe.booms(t, &"frag")
	var near_boom: Dictionary = booms[0] if (booms[0]["data"]["position"] as Vector2).distance_to(NEAR_H) < (booms[1]["data"]["position"] as Vector2).distance_to(NEAR_H) else booms[1]
	var far_boom: Dictionary = booms[1] if near_boom == booms[0] else booms[0]
	t.check((near_boom["data"]["position"] as Vector2).distance_to(NEAR_H) < 110.0 and (far_boom["data"]["position"] as Vector2).distance_to(FAR_H) < 110.0, "each onto its hostile's spot")

	# The one inside the zone crouched behind its cover from the throw to the bang and was not touched.
	var last: Array = posture.filter(func(s): return float(s["t"]) >= float(near_boom["time"]) - 1.0 and float(s["t"]) <= float(near_boom["time"]))
	t.check(not last.is_empty() and last.all(func(s): return s["posture"] == &"crouch"), "the invader 200 px from its hostile was crouched for the last second before the bang")
	t.check(Probe.shielded(t, near_boom["data"]["position"], near), "behind the couch, which shields a crouched body from the blast")
	t.check(Probe.blast_hits(t, near).is_empty() and near.health >= near.max_health - 0.01, "and it was unhurt (%.0f / %.0f)" % [near.health, near.max_health])
	t.check(Probe.blast_hits(t, far).is_empty(), "the one 420 px off was never in it")

	# Both end up on their pistol, and Von is asked again.
	var asked := t.von_requests().size()
	await t.seconds(2.0)
	t.expect_eq(far.current_slot(), Probe.PISTOL, "the far invader is on its pistol after the bang")
	t.expect_eq(near.current_slot(), Probe.PISTOL, "so is the near one")
	t.expect_eq([Probe.count(far, Probe.FRAG), Probe.count(near, Probe.FRAG)], [0, 0], "their grenades are spent")
	t.check(t.von_requests().size() > asked, "and they re-decided: Von was asked again after the bang")
