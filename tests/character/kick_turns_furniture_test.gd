extends GameTest

## A kick shoves furniture at the foot, not at its centre (issue #50). Two puppets each kick south into the north side of
## a sofa lying east-west, near one end: the sofa kicked near its east end turns clockwise (a positive rotation, the
## struck end swinging south), the one kicked near its west end counter-clockwise. Both still slide away.

## A sofa is 120 x 50; its long axis lies east-west.
const HALF_DEPTH := 25.0
## How far from the sofa's centre each kicker stands along it: 20 px in from an end.
const END_OFFSET := 40.0
## Px between a kicker's centre and the sofa's north side (the kick tests' usual reach).
const REACH_GAP := 28.0
const EAST_SOFA := Vector2(250, 200)
const WEST_SOFA := Vector2(600, 200)
## A noticeable turn (degrees).
const MIN_TURN := 5.0


func describe() -> Dictionary:
	return {
		"name": "Kick near one end turns a sofa",
		"description": "Puppets kick sofas near the east and the west end; each sofa turns the way the struck end was driven.",
		"tags": ["kick", "melee", "pushable", "legs", "physics", "pivot"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 850, 500))
	s.switch(&"nav.rebake", false)
	var kicker_y := EAST_SOFA.y - HALF_DEPTH - REACH_GAP
	s.object(&"east_sofa", "sofa", EAST_SOFA)
	s.actor(&"east_kicker", &"puppet", Vector2(EAST_SOFA.x + END_OFFSET, kicker_y), { "start_slot": 3 })
	s.object(&"west_sofa", "sofa", WEST_SOFA)
	s.actor(&"west_kicker", &"puppet", Vector2(WEST_SOFA.x - END_OFFSET, kicker_y), { "start_slot": 3 })


func run(t: TestContext) -> void:
	var cases := [[&"east_kicker", &"east_sofa", 1.0], [&"west_kicker", &"west_sofa", -1.0]]
	var start := {}
	var angle := {}
	for c in cases:
		var sofa: Node2D = t.object(c[1])
		start[c[1]] = sofa.global_position
		angle[c[1]] = sofa.global_rotation
		t.puppet(c[0]).aim_at(t.actor(c[0]).global_position + Vector2(0, 1000))
	await t.seconds(0.3)
	for c in cases:
		t.puppet(c[0]).kick()
	for c in cases:
		var sofa: Node2D = t.object(c[1])
		var landed := func(d): return d["actor"] == c[0] and d["body"] == sofa and d["hand"] == 2
		if not t.require(await t.until(func(): return t.happened(&"hit_landed", landed), 1.5), "%s's kick lands on its sofa" % c[0]):
			return
	await t.seconds(1.0)
	for c in cases:
		var sofa: Node2D = t.object(c[1])
		var moved: Vector2 = sofa.global_position - start[c[1]]
		var turn := rad_to_deg(angle_difference(angle[c[1]], sofa.global_rotation))
		t.check(moved.y > 1.0, "%s was shoved away from its kicker (dy %.1f)" % [c[1], moved.y])
		t.check(turn * c[2] > MIN_TURN, "%s turned %s, the struck end swinging south (turned %.1f deg, want %s %.0f)" % [
			c[1], "clockwise" if c[2] > 0.0 else "counter-clockwise", turn, ">" if c[2] > 0.0 else "<", MIN_TURN * c[2]])
