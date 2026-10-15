extends GameTest

## G17's throw spots, the mechanism: GRENADE is also offered against a hostile out of throw range from where the NPC stands, if a
## reachable throw spot exists (a point on the navmesh within the grenade's range of the hostile's spot, with a clear lob, a short walk away);
## the `throw` primitive walks there and throws from it, and the self-safety tag (`no_safe_spot`) is judged with the thrower at the throw spot.
## Scripted Von (COMBAT > GRENADE when offered, else ENGAGE ...), two closed rooms with a wall between, the same scene in each: an invader
## 640 px from a household puppet hidden from its line of fire by a coffee table (which a lob clears), in neither room in range from where it
## stands (550 px, the throw range).
##
## North: the invader carries a stun. GRENADE is offered through a throw spot (the controller's `debug_zones()`, category `grenade`, `from`)
## within range of the hostile's spot, with a clear lob, reached by a short walk; the invader walks there and throws from it, and the stun goes off
## on the hostile.
## South: the invader carries a frag whose row is retuned (a premise: blast radius 480 px, so its danger zone, 600 px, reaches past the throw
## range, and a 0.5 s fuse) so that every spot within throw range of the hostile is inside the zone with nowhere to get clear in time, while
## where the invader stands (640 px) is outside it. Judged from the throw spot the option is tagged `no_safe_spot` and GRENADE is not offered;
## judged from where it stands it would be offered.
##
## Premises: the hostiles are household puppets that cannot be killed and never shoot; each invader is armed at the start of `run`, the way
## Main arms a spawn; the frag row is retuned (above).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Spot := preload("res://tests/_ai/throw_spot_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const N_AT := Vector2(100, 150)
const N_H := Vector2(740, 150)
const S_AT := Vector2(100, 450)
const S_H := Vector2(740, 450)


func describe() -> Dictionary:
	return {
		"name": "A hostile out of throw range is grenaded from a throw spot",
		"description": "An invader 640 px from a hidden hostile is offered GRENADE through a throw spot a short walk away, within range and with a clear lob, walks there and throws; with a frag whose zone reaches past the throw range the option is tagged no_safe_spot (judged from the throw spot) and not offered.",
		"tags": ["ai", "grenade", "combat", "throw_spot", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	# Premise (south): a frag whose danger zone (blast radius + the 120 px evade margin) reaches past the throw range, with a short fuse.
	var rows: Dictionary = GrenadeConfig.grenades.duplicate(true)
	rows[&"frag"]["blast_radius"] = 480.0
	rows[&"frag"]["fuse"] = 0.5
	s.set_static(GrenadeConfig, "grenades", rows)
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 1000, 300) },
		{ "key": "south", "type": "kitchen", "rect": Rect2(0, 300, 1000, 300) },
	], [{ "pos": Vector2(980, 0), "width": 60.0 }, { "pos": Vector2(980, 600), "width": 60.0 }])
	s.object(&"table_n", "coffee_table", Vector2(600, 150))
	s.object(&"table_s", "coffee_table", Vector2(600, 450))
	Flank.rules(s, [{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "stun" }, { "pick": "frag" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	s.actor(&"n", &"invader", N_AT, { "facing": Vector2.RIGHT })
	s.actor(&"s", &"invader", S_AT, { "facing": Vector2.RIGHT })
	Probe.hostile(s, &"nh", N_H, N_AT)
	Probe.hostile(s, &"sh", S_H, S_AT)


func run(t: TestContext) -> void:
	var n := t.actor(&"n")
	var so := t.actor(&"s")
	Probe.arm(n, 1, 0)
	Probe.arm(so, 0, 1)
	if not t.require(Probe.count(n, Probe.STUN) == 1 and Probe.count(so, Probe.FRAG) == 1, "the north invader carries a stun and the south one a frag"):
		return
	var nb := t.controller(&"n", &"debug_zones")
	var sb := t.controller(&"s", &"debug_zones")
	var states := { &"n": {}, &"s": {} }
	var walks := { &"n": [], &"s": [] }
	# The grenade zones of each one's first COMBAT decision, read the frame that walk ended.
	var zones := { &"n": null, &"s": null }
	var thrown := func() -> bool:
		for pair in [[&"n", nb, n], [&"s", sb, so]]:
			Spot.note(t, pair[1], pair[2], states[pair[0]], walks[pair[0]])
			if zones[pair[0]] == null and walks[pair[0]].any(func(w): return not w["combat"].is_empty()):
				zones[pair[0]] = Spot.throws(pair[1])
		return t.happened(&"throw", func(d): return d.get("attacker") == n) and zones[&"s"] != null
	await t.until(thrown, 25.0)

	# North: out of range where it stands, offered through a throw spot, walks there and throws.
	var first: Array = walks[&"n"].filter(func(w): return not w["combat"].is_empty())
	if not t.require(not first.is_empty(), "the north invader made a COMBAT decision (walks %s)" % str(Spot.describe(walks[&"n"]))):
		return
	var w0: Dictionary = first[0]
	if not t.require((w0["pos"] as Vector2).distance_to(N_H) > Spot.THROW_RANGE, "set-up: it decided from out of throw range (%.0f px from the hostile)" % (w0["pos"] as Vector2).distance_to(N_H)):
		return
	t.check(w0["combat"].has("grenade"), "GRENADE was offered from out of range, through a throw spot (offered %s)" % str(w0["combat"]))
	var near: Array = (zones[&"n"] if zones[&"n"] != null else []).filter(func(z): return (z["point"] as Vector2).distance_to(N_H) < 60.0)
	if t.check(not near.is_empty() and Spot.from_of(near[0]) != Vector2.INF, "the throw it weighed names a throw spot (debug_zones grenade `from`; zones %s)" % str(zones[&"n"])):
		var z: Dictionary = near[0]
		var from := Spot.from_of(z)
		var point: Vector2 = z["point"]
		var way := Spot.walk(t, w0["pos"], from)
		t.check(from.distance_to(w0["pos"]) >= 40.0, "the throw spot is not where it stands (%s, it stood at %s)" % [str(from.round()), str((w0["pos"] as Vector2).round())])
		t.check(from.distance_to(point) <= Spot.THROW_RANGE, "the throw spot is within throw range of the hostile's spot (%.0f px)" % from.distance_to(point))
		t.check(Spot.lob_clear(t, from, point), "with a clear lob from it to the hostile's spot")
		t.check(way["reaches"] and float(way["len"]) <= Spot.SHORT_WALK, "reached by a short walk (%.0f px, reaches %s)" % [way["len"], str(way["reaches"])])
		t.check(not z["tags"].get("no_safe_spot", false), "and it is safe to throw from (no_safe_spot %s)" % str(z["tags"].get("no_safe_spot")))
		var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == n)
		if t.check(not throws.is_empty(), "the north invader threw (walks %s)" % str(Spot.describe(walks[&"n"]))):
			var at: Vector2 = throws[0]["data"]["position"]
			t.check(at.distance_to(from) <= 30.0, "from the throw spot (thrown at %s, the spot %s)" % [str(at.round()), str(from.round())])
			t.check(at.distance_to(N_H) <= Spot.THROW_RANGE, "within throw range of the hostile (%.0f px)" % at.distance_to(N_H))
			if t.check(await Probe.wait_boom(t, &"stun", 4.0), "the stun went off"):
				var boom: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
				t.check(boom.distance_to(N_H) < 110.0, "on the hostile's spot (%.0f px from it)" % boom.distance_to(N_H))

	# South: the self-safety tag is judged from the throw spot.
	var south: Array = walks[&"s"].filter(func(w): return not w["combat"].is_empty())
	if not t.require(not south.is_empty() and (south[0]["pos"] as Vector2).distance_to(S_H) > Spot.THROW_RANGE, "set-up: the south invader decided from out of throw range and out of the frag's zone (walks %s)" % str(Spot.describe(walks[&"s"]))):
		return
	var s_near: Array = (zones[&"s"] if zones[&"s"] != null else []).filter(func(z): return (z["point"] as Vector2).distance_to(S_H) < 60.0 and Spot.from_of(z) != Vector2.INF)
	if t.check(not s_near.is_empty(), "a throw spot was weighed against the south hostile too (zones %s)" % str(zones[&"s"])):
		t.check(Spot.from_of(s_near[0]).distance_to(S_H) <= Spot.THROW_RANGE, "within throw range, so inside the frag's zone")
		t.check(s_near[0]["tags"].get("no_safe_spot", false), "and, judged from the throw spot, it is tagged no_safe_spot (tags %s)" % str(s_near[0]["tags"]))
	t.check(not south[0]["combat"].has("grenade"), "so GRENADE is not offered to the south invader (offered %s)" % str(south[0]["combat"]))
