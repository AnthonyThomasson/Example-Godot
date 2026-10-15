extends GameTest

## G17 as amended by issue #51 R13, the mechanism for an NPC outside a wall: with no clear lob from where it stands (the house wall is in the
## way) and a doorway a short walk away, GRENADE is offered through a throw spot at the doorway, not in place, and the throw leaves from there,
## within range. The Terrace house, bare; an invader with a stun outside the back door sees a household puppet in the kitchen through it.
##
## Premise (it stands for a peek-and-cover duck, or a retreat, after the sighting, before a decision lands: the way the case arises in
## matches): scripted Von answers slowly (30 physics frames a level); the invader's first question is asked in sight, and while it is in flight
## the invader is moved 140 px north, behind the kitchen's east wall, where the wall stops a lob to the puppet's spot (still in throw range), and
## Von is down for that question (`DecisionStub.fail`, set only until it has failed), so no order made in sight is carried out. The first
## decision the invader acts on is made behind the wall, with the contact still fresh: it must offer GRENADE through a throw spot at the back
## doorway, and the throw must leave from that spot, within range, and burst in the kitchen on the puppet. Case (b) of R13 has no real-Von
## scenario: a hostile the NPC knows of is one it saw a moment ago, and the lob to where it saw it is the clear sight line it saw it along, so
## the case needs the NPC to have moved since, which a real-Von test cannot steer.
##
## Other premises: the puppet cannot be killed and never shoots; the invader is armed at the start of `run`, the way Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Spot := preload("res://tests/_ai/throw_spot_probe.gd")
const I_AT := Vector2(960, 190)
const BEHIND := Vector2(900, 50)
const H_AT := Vector2(660, 120)


func describe() -> Dictionary:
	return {
		"name": "An NPC outside a wall throws from the doorway",
		"description": "An invader that saw a householder through the back door and is then behind the wall, with no lob from there, is offered GRENADE through a throw spot at the doorway and throws from it.",
		"tags": ["ai", "grenade", "combat", "throw_spot", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "stun" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }], 30)
	s.set_static(DecisionStub, "fail", false)  # Registered so the runner restores it: `run` sets it for the in-sight question only (the premise).
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", I_AT, { "facing": (H_AT - I_AT).normalized() })
	Probe.hostile(s, &"h", H_AT, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 0)
	if not t.require(Probe.count(inv, Probe.STUN) == 1, "the invader carries a stun (item_count(7) = %d)" % Probe.count(inv, Probe.STUN)):
		return
	if not t.require(Probe.line_clear(t, I_AT, H_AT) and not Spot.lob_clear(t, BEHIND, H_AT) and BEHIND.distance_to(H_AT) <= Probe.MAX_RANGE,
			"set-up: the householder is in sight through the doorway from the start; from behind the wall there is no lob to it, in range"):
		return
	var brain := t.controller(&"i", &"debug_zones")
	if not t.require(await t.until(func(): return brain.debug_state().get("decision", {}).get("pending", false), 10.0), "the invader asked its first question, in sight"):
		return
	# The walk in flight was started in sight: only the walks started after the move count as made behind the wall. Von is down for it.
	var state := { "count": int(brain.debug_state().get("decisions", 0)), "logged": true }
	DecisionStub.fail = true
	inv.global_position = BEHIND
	inv.velocity = Vector2.ZERO
	var failed := await t.until(func(): return not brain.debug_state().get("decision", {}).get("pending", false), 5.0)
	DecisionStub.fail = false
	if not t.require(failed and t.von_requests().size() == 1 and str(t.von_requests()[0]["pick"]) == "",
			"set-up: the question asked in sight failed, so no order made in sight was carried out (requests %s)" % str(t.von_requests().map(func(r): return r["pick"]))):
		return
	var walks: Array = []
	var behind := {}
	var zones: Array = []
	var decided_behind := func() -> bool:
		Spot.note(t, brain, inv, state, walks)
		if behind.is_empty():
			for w in walks:
				if not w["combat"].is_empty() and (w["pos"] as Vector2).distance_to(BEHIND) <= 12.0:
					behind.merge(w)
					zones.assign(Spot.throws(brain))
					break
		return not behind.is_empty() and t.happened(&"throw", func(d): return d.get("attacker") == inv)
	await t.until(decided_behind, 20.0)
	if not t.require(not behind.is_empty(), "the invader made a COMBAT decision from behind the wall (walks %s; acts %s)" % [str(Spot.describe(walks)), Probe.acts(t, &"i")]):
		return
	t.check(behind["combat"].has("grenade"), "from behind the wall, GRENADE was offered (offered %s)" % str(behind["combat"]))
	var near := zones.filter(func(z): return (z["point"] as Vector2).distance_to(H_AT) < 60.0 and Spot.from_of(z) != Vector2.INF)
	if not t.check(not near.is_empty(), "through a throw spot (debug_zones grenade `from`; zones %s)" % str(zones)):
		return
	var from := Spot.from_of(near[0])
	var point: Vector2 = near[0]["point"]
	var way := Spot.walk(t, BEHIND, from)
	t.check(from.distance_to(BEHIND) >= 40.0, "not in place (%s)" % str(from.round()))
	t.check(from.distance_to(Maps.DOOR_BACK) <= 160.0 and from.x > Maps.DOOR_BACK.x, "at the back doorway, outside (%s, %.0f px from it)" % [str(from.round()), from.distance_to(Maps.DOOR_BACK)])
	t.check(Spot.lob_clear(t, from, point) and from.distance_to(point) <= Spot.THROW_RANGE, "with a clear lob in range of the householder's spot (%.0f px)" % from.distance_to(point))
	t.check(way["reaches"] and float(way["len"]) <= Spot.SHORT_WALK, "a short walk from behind the wall (%.0f px, reaches %s)" % [way["len"], str(way["reaches"])])
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if t.check(not throws.is_empty(), "the invader threw (acts %s)" % Probe.acts(t, &"i")):
		var at: Vector2 = throws[0]["data"]["position"]
		t.check(at.distance_to(from) <= 30.0 and at.distance_to(H_AT) <= Spot.THROW_RANGE, "from the throw spot, within range (thrown at %s, the spot %s, %.0f px from the householder)" % [str(at.round()), str(from.round()), at.distance_to(H_AT)])
		if t.check(await Probe.wait_boom(t, &"stun", 4.0), "the stun went off"):
			var boom: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
			t.check(Maps.HOUSE_KITCHEN.has_point(boom) and boom.distance_to(H_AT) < 110.0, "in the kitchen on the householder's spot (%s)" % str(boom.round()))
