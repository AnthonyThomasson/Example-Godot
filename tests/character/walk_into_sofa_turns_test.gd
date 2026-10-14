extends GameTest

## Walking into furniture pushes it at the point of contact (issue #50). A puppet walks south into the north side of a
## sofa lying east-west, near its east end: the sofa slides and turns noticeably, the pushed (east) end swinging south
## (clockwise on screen, a positive rotation), about a point nearer its far (west) end than the end that was pushed.
## A second puppet walks into the middle of an identical sofa's side: that one just slides, turning by less than 3 degrees.

## How long each puppet walks (s): long enough to shove the 45 kg sofa well along at the pushing pace.
const WALK_TIME := 3.5
## A sofa is 120 x 50; its long axis lies east-west.
const HALF_LENGTH := 60.0
const HALF_DEPTH := 25.0
## Px between a walker's body and the sofa's north side at the start.
const START_GAP := 40.0
## How far east of the sofa's centre the end walker walks: 20 px in from the east end.
const END_OFFSET := 40.0
const BODY_RADIUS := 14.0
const END_SOFA := Vector2(300, 200)
const MIDDLE_SOFA := Vector2(900, 200)
## A noticeable turn (degrees) for the end push; the middle push must stay under the plan's 3 degrees.
const MIN_END_TURN := 10.0
const MAX_MIDDLE_TURN := 3.0


func describe() -> Dictionary:
	return {
		"name": "Walking into a sofa's end turns it",
		"description": "A puppet walking into one end of a sofa slides it and turns it about a point nearer the far end; one walking into the middle of a side just slides it.",
		"tags": ["walk", "pushable", "physics", "pivot"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 800))
	s.switch(&"nav.rebake", false)
	var walker_y := END_SOFA.y - HALF_DEPTH - BODY_RADIUS - START_GAP
	s.object(&"end_sofa", "sofa", END_SOFA)
	s.actor(&"end_walker", &"puppet", Vector2(END_SOFA.x + END_OFFSET, walker_y), { "start_slot": 1 })
	s.object(&"middle_sofa", "sofa", MIDDLE_SOFA)
	s.actor(&"middle_walker", &"puppet", Vector2(MIDDLE_SOFA.x, walker_y), { "start_slot": 1 })


func run(t: TestContext) -> void:
	var end_sofa: Node2D = t.object(&"end_sofa")
	var middle_sofa: Node2D = t.object(&"middle_sofa")
	var end_start := end_sofa.global_position
	var end_angle := end_sofa.global_rotation
	var middle_start := middle_sofa.global_position
	var middle_angle := middle_sofa.global_rotation
	for id in [&"end_walker", &"middle_walker"]:
		t.puppet(id).aim_at(t.actor(id).global_position + Vector2(0, 1000))
		t.puppet(id).walk(Vector2.DOWN)
	var elapsed := 0.0
	while elapsed < WALK_TIME:
		await t.frames(1)
		elapsed += 1.0 / 60.0
		t.trace("end_turn_deg", rad_to_deg(angle_difference(end_angle, end_sofa.global_rotation)))
		t.trace("middle_turn_deg", rad_to_deg(angle_difference(middle_angle, middle_sofa.global_rotation)))
	for id in [&"end_walker", &"middle_walker"]:
		t.puppet(id).stop()
	await t.seconds(0.5)

	var end_moved := end_sofa.global_position - end_start
	var end_turn := angle_difference(end_angle, end_sofa.global_rotation)
	if not t.require(end_moved.y > 10.0, "the end walker shoved its sofa south (dy %.1f)" % end_moved.y):
		return
	t.check(rad_to_deg(end_turn) > MIN_END_TURN,
		"pushing the east end turns the sofa clockwise, the pushed end swinging south (turned %.1f deg, want > %.0f)" % [rad_to_deg(end_turn), MIN_END_TURN])
	if absf(end_turn) > deg_to_rad(1.0):
		var pivot := _pivot(end_start, end_angle, end_sofa.global_position, end_sofa.global_rotation)
		t.check(pivot.x < 0.0 and pivot.x > -HALF_LENGTH * 1.5,
			"the sofa turned about a point nearer its far (west) end, along its length (pivot at %.1f px along it, its ends at -60 and +60)" % pivot.x)

	var middle_moved := middle_sofa.global_position - middle_start
	var middle_turn := rad_to_deg(angle_difference(middle_angle, middle_sofa.global_rotation))
	t.check(middle_moved.y > 10.0, "the middle walker slid its sofa south (dy %.1f)" % middle_moved.y)
	t.check(absf(middle_turn) < MAX_MIDDLE_TURN, "pushing the middle of a side barely turns the sofa (turned %.1f deg)" % middle_turn)


## The point (in the sofa's starting frame, px from its centre; x along its length) that the move from (`p0`, `a0`) to
## (`p1`, `a1`) leaves where it was: the centre the sofa turned about.
func _pivot(p0: Vector2, a0: float, p1: Vector2, a1: float) -> Vector2:
	var turn := a1 - a0
	var c := cos(turn)
	var s := sin(turn)
	# Solve (I - R) x = p1 - R p0 for the fixed world point x.
	var b := p1 - p0.rotated(turn)
	var det := (1.0 - c) * (1.0 - c) + s * s
	var fixed := Vector2((1.0 - c) * b.x - s * b.y, s * b.x + (1.0 - c) * b.y) / det
	return (fixed - p0).rotated(-a0)
