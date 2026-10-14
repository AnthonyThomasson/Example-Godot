extends GameTest

## A punch shoves furniture at the fist, not at its centre (issue #50). Two fists puppets each punch south into the north
## side of a bench lying east-west, near one end: the bench punched near its east end turns clockwise (a positive
## rotation, the struck end swinging south), the one punched near its west end counter-clockwise. Both still slide away.

## A bench is 80 x 30; its long axis lies east-west.
const HALF_DEPTH := 15.0
## How far from the bench's centre each boxer stands along it: 12 px in from an end.
const END_OFFSET := 28.0
## Px between a boxer's centre and the bench's north side (the punch tests' usual reach).
const REACH_GAP := 28.0
const EAST_BENCH := Vector2(250, 200)
const WEST_BENCH := Vector2(550, 200)
## A noticeable turn (degrees).
const MIN_TURN := 5.0


func describe() -> Dictionary:
	return {
		"name": "Punch near one end turns a bench",
		"description": "Fists puppets punch benches near the east and the west end; each bench turns the way the struck end was driven.",
		"tags": ["punch", "melee", "pushable", "fists", "physics", "pivot"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	var boxer_y := EAST_BENCH.y - HALF_DEPTH - REACH_GAP
	s.object(&"east_bench", "bench", EAST_BENCH)
	s.actor(&"east_boxer", &"puppet", Vector2(EAST_BENCH.x + END_OFFSET, boxer_y), { "start_slot": 2 })
	s.object(&"west_bench", "bench", WEST_BENCH)
	s.actor(&"west_boxer", &"puppet", Vector2(WEST_BENCH.x - END_OFFSET, boxer_y), { "start_slot": 2 })


func run(t: TestContext) -> void:
	var cases := [[&"east_boxer", &"east_bench", 1.0], [&"west_boxer", &"west_bench", -1.0]]
	var start := {}
	var angle := {}
	for c in cases:
		var bench: Node2D = t.object(c[1])
		start[c[1]] = bench.global_position
		angle[c[1]] = bench.global_rotation
		t.puppet(c[0]).aim_at(t.actor(c[0]).global_position + Vector2(0, 1000))
	await t.seconds(0.3)
	for c in cases:
		t.puppet(c[0]).punch()
	for c in cases:
		var bench: Node2D = t.object(c[1])
		var landed := func(d): return d["actor"] == c[0] and d["body"] == bench and d["hand"] >= 0
		if not t.require(await t.until(func(): return t.happened(&"hit_landed", landed), 1.5), "%s's punch lands on its bench" % c[0]):
			return
	await t.seconds(1.0)
	for c in cases:
		var bench: Node2D = t.object(c[1])
		var moved: Vector2 = bench.global_position - start[c[1]]
		var turn := rad_to_deg(angle_difference(angle[c[1]], bench.global_rotation))
		t.check(moved.y > 1.0, "%s was shoved away from its boxer (dy %.1f)" % [c[1], moved.y])
		t.check(turn * c[2] > MIN_TURN, "%s turned %s, the struck end swinging south (turned %.1f deg, want %s %.0f)" % [
			c[1], "clockwise" if c[2] > 0.0 else "counter-clockwise", turn, ">" if c[2] > 0.0 else "<", MIN_TURN * c[2]])
