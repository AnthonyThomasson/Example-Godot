extends GameTest

## G17: the GRENADE tactic is offered against a spot within throw range (550 px) of where the NPC stood when the snapshot was made. The NPC moves on
## while Von answers, so by the time the order is adopted it can stand a few px past the range. It must not give the throw up there and re-decide (the
## tactic then flaps in and out of the offer near the range); the thrower closes the last few px on the spot and throws. One mechanism, scripted Von
## that answers slowly (30 physics frames a level): the invader starts 540 px from a hostile hidden behind a desk and is moved 20 px back, to 560 px,
## while its first question is in flight. GRENADE is asked about and carried out once, and the grenade leaves the hand within range.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const START := Vector2(80, 150)
const DRIFTED := Vector2(60, 150)
const HOSTILE := Vector2(620, 150)


func describe() -> Dictionary:
	return {
		"name": "A thrower that drifted out of range closes in and throws",
		"description": "The invader is 540 px from a hidden hostile when GRENADE is offered and 560 px when the order is adopted: it closes the last few px and throws, with GRENADE picked once.",
		"tags": ["ai", "grenade", "combat", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "hall", "type": "living_room", "rect": Rect2(0, 0, 900, 300) }], [{ "pos": Vector2(880, 0), "width": 60.0 }])
	s.object(&"desk", "desk", Vector2(330, 150))
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }], 30)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"i", &"invader", START, { "facing": Vector2.RIGHT })
	Probe.hostile(s, &"h", HOSTILE, START)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 0, 1)
	if not t.require(Probe.count(inv, Probe.FRAG) == 1, "the invader carries a frag (item_count(8) = %d)" % Probe.count(inv, Probe.FRAG)):
		return
	t.check(START.distance_to(HOSTILE) <= Probe.MAX_RANGE and DRIFTED.distance_to(HOSTILE) > Probe.MAX_RANGE, "the set-up: in range at the snapshot, past it after the drift")
	var brain := t.controller(&"i", &"debug_state")
	if not t.require(await t.until(func(): return brain.debug_state().get("decision", {}).get("pending", false), 10.0), "the NPC asked Von (the snapshot is made)"):
		return
	inv.global_position = DRIFTED
	inv.velocity = Vector2.ZERO
	var seen: Array = []
	if not t.require(await Probe.wait_act(t, &"i", "grenade", 10.0, seen), "the AI took the GRENADE tactic (its acts: %s)" % str(seen)):
		return
	var thrown := await t.until(func(): return t.happened(&"throw", func(d): return d.get("attacker") == inv), 6.0)
	if not t.require(thrown, "the invader threw the frag after closing in (acting: %s, at %s)" % [Probe.acts(t, &"i"), str(inv.global_position)]):
		return
	var from: Vector2 = Probe.raw(t, &"throw")[0]["data"]["position"]
	t.check(from.distance_to(HOSTILE) <= Probe.MAX_RANGE, "it let go within throw range (%.0f px)" % from.distance_to(HOSTILE))
	var grenade_picks := t.von_requests().filter(func(r): return r["pick"] == "grenade").size()
	t.expect_eq(grenade_picks, 1, "GRENADE was picked once: the throw was not given up and re-decided")
