extends GameTest

## G2: a throw is capped at `max_range` 550 px. Aiming 900 px away the grenade comes down about 550 px out, no further
## (a little roll after the landing is allowed).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(60, 250)
const AIM := Vector2(960, 250)
## What a capped grenade may roll on past its first touch-down (px).
const ROLL := 100.0


func describe() -> Dictionary:
	return {
		"name": "A throw is capped at the throw range",
		"description": "Aiming 900 px away, the grenade first touches down within 550 px of the thrower (plus a short roll) and comes to rest short of the aim point.",
		"tags": ["grenade", "throw", "range", "item"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 500))
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun grenade in slot 7 (Character.item_count(7) = %d)" % Probe.count(thrower, Probe.STUN)):
		return
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	if not t.require(await t.until(func(): return t.happened(&"grenade"), 3.0), "the grenade touches down (a grenade event)"):
		return
	var first: Vector2 = Probe.raw(t, &"grenade")[0]["data"]["position"]
	var reach := first.distance_to(FROM)
	t.check(reach <= Probe.MAX_RANGE + 30.0, "it first lands no further than the range cap (%.0f px, cap %.0f)" % [reach, Probe.MAX_RANGE])
	t.check(reach >= Probe.MAX_RANGE - 120.0, "and it was thrown as far as the cap allows (%.0f px)" % reach)
	if not t.require(await Probe.wait_boom(t, &"stun", 4.0), "the grenade goes off"):
		return
	var at: Vector2 = Probe.booms(t, &"stun")[0]["data"]["position"]
	t.check(at.distance_to(FROM) <= Probe.MAX_RANGE + ROLL, "it comes to rest within the cap plus a short roll (%.0f px)" % at.distance_to(FROM))
	t.check(at.distance_to(AIM) > 200.0, "far short of the aim point 900 px out")
