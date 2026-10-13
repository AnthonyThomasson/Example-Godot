extends GameTest

## G9: grenades hurt and stun everyone, the thrower and its allies included. A frag thrown at a spot 150 px away wounds
## the thrower and a teammate beside the burst; a stun thrown at the same spot stuns both.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(200, 250)
const AIM := Vector2(350, 250)


func describe() -> Dictionary:
	return {
		"name": "Grenades hurt and stun the thrower and its allies",
		"description": "A frag and then a stun are thrown 150 px from the thrower, with a teammate 100 px from the burst: both are wounded by the frag and stunned by the stun.",
		"tags": ["grenade", "friendly fire", "frag", "stun"],
		"timeout": 18.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.actor(&"thrower", &"puppet", FROM, { "faction": &"invader", "max_health": 1000.0 })
	s.actor(&"mate", &"puppet", AIM + Vector2(0, 100), { "faction": &"invader", "max_health": 1000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var mate := t.actor(&"mate")
	Probe.arm(thrower, 1, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1 and Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun and a frag"):
		return
	t.puppet(&"mate").aim_at(AIM)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag goes off"):
		return
	await t.seconds(0.4)
	t.check(not Probe.blast_hits(t, thrower).is_empty() and thrower.health < thrower.max_health, "the thrower is wounded by its own frag (%.0f / %.0f)" % [thrower.health, thrower.max_health])
	t.check(not Probe.blast_hits(t, mate).is_empty() and mate.health < mate.max_health, "so is its teammate (%.0f / %.0f)" % [mate.health, mate.max_health])

	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await Probe.wait_boom(t, &"stun", 5.0), "the stun goes off"):
		return
	await t.frames(3)
	var self_stun := Probe.stuns(t, thrower)
	var mate_stun := Probe.stuns(t, mate)
	t.check(not self_stun.is_empty() and (float(self_stun[0]["data"].get("deaf", 0.0)) > 0.0 or float(self_stun[0]["data"].get("blind", 0.0)) > 0.0), "the thrower is stunned by its own grenade")
	t.check(not mate_stun.is_empty() and float(mate_stun[0]["data"].get("deaf", 0.0)) > 0.0, "so is its teammate")
	t.check(Probe.deaf(thrower) and Probe.deaf(mate), "both are deaf (is_deaf)")
