extends GameTest

## A leg pressing a light piece shoves it at the foot or knee, not at its centre (issue #50). Two crouched puppets walk
## slowly south toward the north side of a bench lying east-west, one near its east end and one near its west end. A
## crouch stands the feet ahead of the pelvis with the knees leading (standing, a stride reaches only ~1.5 px past the
## body circle), so the legs reach the bench well before the body and, at this pace, keep it ahead of the body: the leg
## press alone must turn the bench the way the pressed end is driven (east end: clockwise, a positive rotation; west end:
## counter-clockwise). Only what happens before the body first touches the bench is judged, so the walking push plays no
## part.

## A bench is 80 x 30; its long axis lies east-west.
const HALF_LENGTH := 40.0
const HALF_DEPTH := 15.0
## How far from the bench's centre each walker walks along it: 12 px in from an end.
const END_OFFSET := 28.0
const BODY_RADIUS := 14.0
## Px between a walker's body and the bench's north side at the start.
const START_GAP := 30.0
## A slow walk (a fraction of the crouched pace): the legs still stride, and the bench, shoved by them, keeps ahead of the body.
const WALK_INPUT := 0.3
const WALK_TIME := 3.0
## Time for the body to fold into its crouch before walking (s).
const CROUCH_TIME := 1.0
const EAST_BENCH := Vector2(250, 200)
const WEST_BENCH := Vector2(550, 200)
## A noticeable turn (degrees).
const MIN_TURN := 5.0


func describe() -> Dictionary:
	return {
		"name": "Leg press near one end turns a bench",
		"description": "Crouched puppets walk slowly at a bench near its east and its west end; the legs press it before the body touches it and turn it the way the pressed end is driven.",
		"tags": ["legs", "walk", "crouch", "pushable", "physics", "pivot"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	var walker_y := EAST_BENCH.y - HALF_DEPTH - BODY_RADIUS - START_GAP
	s.object(&"east_bench", "bench", EAST_BENCH)
	s.actor(&"east_walker", &"puppet", Vector2(EAST_BENCH.x + END_OFFSET, walker_y), { "start_slot": 1 })
	s.object(&"west_bench", "bench", WEST_BENCH)
	s.actor(&"west_walker", &"puppet", Vector2(WEST_BENCH.x - END_OFFSET, walker_y), { "start_slot": 1 })


func run(t: TestContext) -> void:
	var cases := [[&"east_walker", &"east_bench", 1.0], [&"west_walker", &"west_bench", -1.0]]
	var start := {}
	var angle := {}
	# Per bench: how far it had moved and turned (deg) on the last frame before the body touched it.
	var moved := {}
	var turn := {}
	var touched := {}
	for c in cases:
		var bench: Node2D = t.object(c[1])
		start[c[1]] = bench.global_position
		angle[c[1]] = bench.global_rotation
		moved[c[1]] = Vector2.ZERO
		turn[c[1]] = 0.0
		touched[c[1]] = false
		t.puppet(c[0]).aim_at(t.actor(c[0]).global_position + Vector2(0, 1000))
		t.puppet(c[0]).set_posture(&"crouch")
	await t.seconds(CROUCH_TIME)
	for c in cases:
		t.puppet(c[0]).walk(Vector2.DOWN * WALK_INPUT)
	var elapsed := 0.0
	while elapsed < WALK_TIME:
		await t.frames(1)
		elapsed += 1.0 / 60.0
		for c in cases:
			var bench: Node2D = t.object(c[1])
			var gap := _body_gap(t.actor(c[0]), bench)
			t.trace("%s_gap" % c[1], gap)
			t.trace("%s_turn_deg" % c[1], rad_to_deg(angle_difference(angle[c[1]], bench.global_rotation)))
			if touched[c[1]]:
				continue
			if gap <= 0.5:
				touched[c[1]] = true
				continue
			moved[c[1]] = bench.global_position - start[c[1]]
			turn[c[1]] = rad_to_deg(angle_difference(angle[c[1]], bench.global_rotation))
	for c in cases:
		var shoved: Vector2 = moved[c[1]]
		if not t.require(shoved.y > 2.0, "a foot pressed %s south before the body touched it (dy %.1f)" % [c[1], shoved.y]):
			return
		t.check(turn[c[1]] * c[2] > MIN_TURN, "the leg press turned %s %s before the body touched it (turned %.1f deg, want %s %.0f)" % [
			c[1], "clockwise" if c[2] > 0.0 else "counter-clockwise", turn[c[1]], ">" if c[2] > 0.0 else "<", MIN_TURN * c[2]])


## Px between `walker`'s body circle and `bench`'s rectangle (0 or less: touching).
func _body_gap(walker: Node2D, bench: Node2D) -> float:
	var local := bench.to_local(walker.global_position)
	var nearest := Vector2(clampf(local.x, -HALF_LENGTH, HALF_LENGTH), clampf(local.y, -HALF_DEPTH, HALF_DEPTH))
	return local.distance_to(nearest) - BODY_RADIUS
