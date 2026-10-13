extends GameTest

## G7, cover (amended: "frag out, take cover"): besides walls, a piece of furniture between the blast and a character blocks the blast when
## its `coverage` is above the character's posture height (crouched 35, standing 60). Behind a couch (coverage 45) a crouched character is
## shielded and a standing one is not. Two dummies stand behind a row of three couches, one crouched and one standing; a frag goes off on the
## other side. (Fragments already behave so: they fly at a height; this test reads the blast hits only.)

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(100, 400)
const AIM := Vector2(500, 400)
const ROW_Y := 470.0       ## the couches, 70 px south of the aim point (three across, 360 px wide)
const BEHIND_Y := 545.0    ## the dummies, just behind them, about 145 px from the aim point
## Slack on the damage formula: the body has a radius and the blast point is the grenade's rest point, not the aim point.
const SLACK := 8.0


func describe() -> Dictionary:
	return {
		"name": "A crouched character behind a couch is shielded from a frag blast, a standing one is not",
		"description": "A row of couches 70 px from where a frag goes off; behind it a crouched dummy takes no blast hit and a standing one at the same distance takes the blast.",
		"tags": ["grenade", "frag", "blast", "cover", "posture"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 800))
	s.switch(&"nav.rebake", false)
	for i in 3:
		s.object(StringName("couch_%d" % i), "sofa", Vector2(AIM.x - 120.0 + 120.0 * i, ROW_Y))
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	s.actor(&"crouched", &"puppet", Vector2(AIM.x - 60.0, BEHIND_Y), { "max_health": 100000.0 })
	s.actor(&"standing", &"puppet", Vector2(AIM.x + 60.0, BEHIND_Y), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var crouched := t.actor(&"crouched")
	var standing := t.actor(&"standing")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	t.puppet(&"crouched").set_posture(&"crouch")
	t.puppet(&"standing").set_posture(&"stand")
	await t.seconds(0.6)
	t.require(crouched.posture() == &"crouch" and standing.posture() == &"stand", "set-up: one dummy crouches and the other stands")
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag goes off"):
		return
	var blast: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	await t.frames(3)
	var d_standing: float = standing.global_position.distance_to(blast)
	var d_crouched: float = crouched.global_position.distance_to(blast)
	t.require(blast.y < ROW_Y - 30.0 and d_crouched < Probe.BLAST_RADIUS and d_standing < Probe.BLAST_RADIUS,
		"set-up: the frag went off on the near side of the couches (%s), both dummies inside the blast radius (%.0f and %.0f px)" % [str(blast.round()), d_crouched, d_standing])
	t.check(Probe.shielded(t, blast, crouched) and not Probe.shielded(t, blast, standing), "the couches shield the crouched dummy's body and not the standing one's (coverage 45 against 35 and 60)")

	var hits := Probe.blast_hits(t, standing)
	if t.check(not hits.is_empty(), "the standing dummy %.0f px from the blast takes a blast hit" % d_standing):
		var want := Probe.blast_damage(d_standing)
		t.check(absf(float(hits[0]["data"]["damage"]) - want) <= SLACK, "of the usual damage (%.1f, expected about %.1f)" % [hits[0]["data"]["damage"], want])
	t.check(Probe.blast_hits(t, crouched).is_empty(), "the crouched dummy %.0f px from the blast, behind the same couches, takes none" % d_crouched)
