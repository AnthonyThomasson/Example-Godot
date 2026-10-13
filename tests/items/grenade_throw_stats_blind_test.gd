extends GameTest

## G1: a stun's throw stats include `max_blind`, the longest (s) it blinds anyone: the number the AI reckons a hostile it flashed is blind for, read off the
## grenade (`Character.throw_stats(slot)`, and a live one's `throw_stats()`) and not copied. A frag blinds nobody: 0.

const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A stun tells how long it can blind",
		"description": "A carrier reads a stun's longest blindness (5 s) off the item and a frag's 0; the live stun answers the same.",
		"tags": ["grenade", "item", "stats"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"c", &"puppet", Vector2(100, 250), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var c := t.actor(&"c")
	Probe.arm(c, 1, 1)
	t.expect_near(float(c.throw_stats(Probe.STUN).get("max_blind", -1.0)), Probe.MAX_BLIND, 0.01, "a stun reports its longest blindness")
	t.expect_near(float(c.throw_stats(Probe.FRAG).get("max_blind", -1.0)), 0.0, 0.01, "a frag blinds nobody")
	await Probe.throw_at(t, &"c", Probe.STUN, Vector2(400, 250))
	if not t.require(await t.until(func(): return not Probe.live(t).is_empty(), 2.0), "the stun leaves the hand"):
		return
	t.expect_near(float(Probe.live(t)[0].throw_stats().get("max_blind", -1.0)), Probe.MAX_BLIND, 0.01, "and the live one answers the same")
