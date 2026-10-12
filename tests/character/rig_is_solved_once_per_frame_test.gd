extends GameTest

## `Character.rig()` solves the standing skeleton once per physics frame and hands every caller in that frame the same
## solve: repeated calls within a frame add no solve and return the same joints, a frame in which the body turned gives
## new joints, and a walking body costs one standing solve a frame however often its draw and footsteps ask.

const Rig = preload("res://scenes/character/body/character_rig.gd")
const FRAMES := 60


func describe() -> Dictionary:
	return {
		"name": "The rig is solved once per frame",
		"description": "Repeated rig() calls in a frame share one solve; a turn gives a new one; a walker costs one solve a frame.",
		"tags": ["rig", "pose"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"walker", &"puppet", Vector2(150, 250), { "start_slot": 1 })


func run(t: TestContext) -> void:
	var c = t.actor(&"walker")
	await t.frames(2)
	var before: int = Rig.solves
	var first = c.rig()
	var hand_a: Vector3 = first.point(Rig.HAND[0])
	for i in 5:
		c.rig()
	t.check(Rig.solves - before <= 1, "six rig() calls in one frame cost at most one solve (%d)" % (Rig.solves - before))
	t.check(c.rig() == first, "every call in the frame returns the same rig")

	t.puppet(&"walker").aim_at(Vector2(150, 0))
	await t.seconds(0.5)  # The body turns at its own rate.
	var hand_b: Vector3 = c.rig().point(Rig.HAND[0])
	t.check(hand_a.distance_to(hand_b) > 1.0, "once the body has turned, rig() gives new joints (moved %.1f px)" % hand_a.distance_to(hand_b))

	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.frames(2)
	var start: int = Rig.solves
	await t.frames(FRAMES)
	var solves: int = Rig.solves - start
	t.trace("solves", solves)
	t.check(solves <= FRAMES + 2, "a walking body is solved at most once a frame (%d in %d frames)" % [solves, FRAMES])
	t.check(solves >= FRAMES * 0.8, "and it is solved afresh most frames (%d in %d)" % [solves, FRAMES])
