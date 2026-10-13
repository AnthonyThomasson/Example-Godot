extends GameTest

## G2 (and G6, G1's count): a grenade held and clicked is thrown after a 0.3 s wind-up in the `throw` stance, leaves
## the hand toward the aim point, lands within about 40 px of it and goes off 3.0 s after release (frag). One grenade
## is spent per throw (2 -> 1) and the throw posts `&"throw"`.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AIM := Vector2(400, 300)
## How far (px) the landing may be from the aim point (the plan's "about 40 px").
const SCATTER := 45.0


func describe() -> Dictionary:
	return {
		"name": "A thrown grenade lands at the aim point",
		"description": "A puppet with two frag grenades winds up for 0.3 s, throws at a point 300 px away: one grenade is spent, the throw is announced, the grenade lands within 45 px of the aim point and bursts 3 s after release.",
		"tags": ["grenade", "throw", "frag", "item"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.actor(&"thrower", &"puppet", Vector2(100, 300), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 2)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 2, "the thrower carries two frag grenades in slot 8 (Character.item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	await Probe.ready(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(thrower.current_slot() == Probe.FRAG, "selecting slot 8 holds the frag grenade"):
		return
	var clicked := t.time
	t.puppet(&"thrower").shoot()
	await t.frames(6)
	t.check(thrower.current_item().hand_stance(0) == &"throw", "during the wind-up the hand is drawn back in the throw stance")
	if not t.require(await t.until(func(): return t.happened(&"throw"), 1.5), "the grenade leaves the hand and a throw event is posted"):
		return
	var thrown: Dictionary = Probe.raw(t, &"throw")[0]
	t.check(absf(float(thrown["time"]) - clicked - Probe.WINDUP) < 0.1, "it leaves 0.3 s after the click (%.2f s)" % (float(thrown["time"]) - clicked))
	t.expect_eq(thrown["data"].get("kind"), &"frag", "the throw names the kind")
	t.check(thrown["data"].get("attacker") == thrower, "and the thrower")
	t.check((thrown["data"].get("position", Vector2.INF) as Vector2).distance_to(thrower.global_position) < 40.0, "it leaves from the thrower's hand")
	t.expect_eq(Probe.count(thrower, Probe.FRAG), 1, "one grenade is spent per throw (2 -> 1)")
	t.expect_eq(Probe.live(t).size(), 1, "the grenade in the air is one live grenade")
	await t.frames(20)
	t.check(thrower.current_item().hand_stance(0) != &"throw", "the wind-up is over once it has left the hand")

	if not t.require(await Probe.wait_boom(t, &"frag", 5.0), "the frag grenade goes off"):
		return
	var boom: Dictionary = Probe.booms(t, &"frag")[0]
	t.check(absf(float(boom["time"]) - float(thrown["time"]) - Probe.FUSE_FRAG) < 0.2, "the fuse runs 3.0 s from release (%.2f s)" % (float(boom["time"]) - float(thrown["time"])))
	var landed: Vector2 = boom["data"]["position"]
	t.check(landed.distance_to(AIM) <= SCATTER, "it lies within %.0f px of the aim point when it goes off (%.0f px)" % [SCATTER, landed.distance_to(AIM)])
