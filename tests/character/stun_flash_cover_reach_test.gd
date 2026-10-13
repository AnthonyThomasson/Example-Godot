extends GameTest

## G11 (amended): a flash is stopped by a wall, and by a piece of furniture taller than the character only when the character is right
## against it (within `flash_cover_reach`, 30 px, of the piece on the burst's side). A crouched character hunched against a couch
## (coverage 45, over a crouch's 35) between it and the burst is not flashed; one crouched 120 px behind the same kind of couch, the couch
## still on the line from the burst, is: the light comes round and over a piece that is not at its face. The victims are stood round the
## grenade once it lies still, facing it, so the blind time is the formula's; one is 175 px from the burst and one 275 px.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(60, 350)
const AIM := Vector2(450, 350)
const COUCH_N := Vector2(450, 220)  ## spans y 195 to 245, x 390 to 510
const COUCH_S := Vector2(450, 480)  ## spans y 455 to 505
## Where the victims crouch: against the north couch's far face (20 px from it, a body's radius and a little), and 120 px behind the south one.
const AGAINST := Vector2(450, 175)
const BEHIND := Vector2(450, 625)
## Seconds of slack on a blind time.
const SLACK := 0.35


func describe() -> Dictionary:
	return {
		"name": "A couch shields from the flash only when the character is against it",
		"description": "A stun grenade lies still between two couches; a crouched victim right against the far face of one is not flashed, one crouched 120 px behind the other (the couch still on the line) is, for the formula's time.",
		"tags": ["grenade", "stun", "flash", "cover", "character"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.object(&"couch_n", "sofa", COUCH_N)
	s.object(&"couch_s", "sofa", COUCH_S)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	# Crouched in the corner until the grenade has landed, then stood in place.
	s.actor(&"against", &"puppet", Vector2(940, 60), { "max_health": 100000.0 })
	s.actor(&"behind", &"puppet", Vector2(940, 100), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun grenade (Character.item_count(7) = %d)" % Probe.count(thrower, Probe.STUN)):
		return
	for who in [&"against", &"behind"]:
		t.puppet(who).set_posture(&"crouch")
	var clicked: float = await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await Probe.wait_rest(t, 1.4), "the grenade comes to rest before it goes off"):
		return
	var burst := Probe.rest_point(t)
	Probe.place(t, &"against", AGAINST, burst)
	Probe.place(t, &"behind", BEHIND, burst)
	if not t.require(await Probe.wait_boom(t, &"stun", 1.2), "the stun grenade goes off (clicked at %.2f s)" % clicked):
		return
	var at: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
	await t.frames(2)
	var against := t.actor(&"against")
	var behind := t.actor(&"behind")
	t.check(against.posture() == &"crouch" and behind.posture() == &"crouch", "both victims were crouched (%s, %s)" % [against.posture(), behind.posture()])
	t.check(Probe.shielded(t, at, against) and Probe.shielded(t, at, behind), "set-up: a couch lies on the line from the burst to each, over a crouch's height")
	var a_events := Probe.stuns(t, against)
	if t.check(not a_events.is_empty(), "the victim against the couch is stunned (the bang reaches it)"):
		t.check(float(a_events[0]["data"].get("blind", 0.0)) == 0.0, "but not flashed: the couch at its face is between it and the burst (%.2f s)" % float(a_events[0]["data"].get("blind", 0.0)))
	t.check(not Probe.blind(against), "so it is not blind")
	var b_events := Probe.stuns(t, behind)
	if t.check(not b_events.is_empty(), "the victim 120 px behind the other couch is stunned"):
		var got := float(b_events[0]["data"].get("blind", -1.0))
		var want := Probe.expected_blind(behind.global_position, behind.facing, at)
		t.check(want > 0.5 and absf(got - want) <= SLACK, "and flashed, the couch not being at its face: %.2f s, the formula gives %.2f (%.0f px from the burst)" % [got, want, behind.global_position.distance_to(at)])
	t.check(Probe.blind(behind), "so it is blind")
