extends GameTest

## G7: the blast shoves what can be shoved, away from the burst, falling off with distance: furniture, living
## characters (as knockback) and the ragdolls of the dead.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(100, 400)
const AIM := Vector2(500, 400)
## How far (px) a body must end up further out from the burst than it began.
const SHOVE := 18.0


func describe() -> Dictionary:
	return {
		"name": "A frag blast shoves furniture, bodies and ragdolls away",
		"description": "A chair, a living puppet and a dead body lie about 110 px from where a frag goes off; each ends up further from the burst.",
		"tags": ["grenade", "frag", "blast", "knockback", "ragdoll", "physics"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 800))
	s.switch(&"nav.rebake", false)  # furniture is shoved into overlaps; the re-baker would log about them
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	s.actor(&"living", &"puppet", AIM + Vector2(110, 0), { "max_health": 100000.0 })
	s.actor(&"dead", &"puppet", AIM + Vector2(0, 110))
	s.object(&"chair", "chair", AIM + Vector2(0, -110))


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var living := t.actor(&"living")
	var dead := t.actor(&"dead")
	var chair := t.object(&"chair")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	dead.take_damage(1000.0)
	await t.seconds(2.0)
	if not t.require(dead.is_dead, "the body is dead and has settled"):
		return
	var chair_before: Vector2 = chair.global_position
	var living_before: Vector2 = living.global_position
	var dead_before: Vector2 = dead.blood_origin()
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag goes off"):
		return
	var blast: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	await t.seconds(1.5)
	for pair in [["chair", chair_before, chair.global_position], ["living character", living_before, living.global_position], ["dead body", dead_before, dead.blood_origin()]]:
		var before: Vector2 = pair[1]
		var after: Vector2 = pair[2]
		var out := (before - blast).normalized()
		t.check((after - before).dot(out) >= SHOVE, "the %s was shoved away from the burst (%.0f px along the way out, %.0f px from the burst before, %.0f after)" % [pair[0], (after - before).dot(out), before.distance_to(blast), after.distance_to(blast)])
