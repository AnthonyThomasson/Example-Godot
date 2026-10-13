extends GameTest

## Performance guard: a room packed with furniture is shoved all at once. Many rigid bodies collide, then
## settle and sleep; frame cost while they move and once they rest stays within budget, and no nodes are
## created or leaked. (Nav re-baking is covered by perf/bake_and_path_stress.)

const Perf := preload("res://tests/_perf/perf_probe.gd")

const COLUMNS := 12
const ROWS := 10
const KINDS := ["chair", "side_table", "armchair", "plant"]
const MOVING_FRAMES := 180
const RESTING_FRAMES := 60
# Frame budgets are the smooth-match standard (Perf.SMOOTH_*).


func describe() -> Dictionary:
	return {
		"name": "A shoved pile of furniture stays cheap",
		"description": "120 pieces of furniture are shoved at once; frame cost while they collide and after they settle stays within budget, with no node growth.",
		"tags": ["furniture", "rigid body"],
		"timeout": 30.0,
	}


func _id(i: int) -> StringName:
	return StringName("piece%d" % i)


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1300, 1100))
	s.switch(&"nav.rebake", false)  # shoved pieces overlap; re-baking holes that overlap logs a nav sync error
	for i in COLUMNS * ROWS:
		var at := Vector2(120 + (i % COLUMNS) * 90, 120 + (int(i / float(COLUMNS))) * 90)
		s.object(_id(i), KINDS[i % KINDS.size()], at)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var nodes_before := Perf.nodes()
	var count := COLUMNS * ROWS
	var starts: Array[Vector2] = []
	for i in count:
		var piece: Node = t.object(_id(i))
		starts.append(piece.global_position)
		piece.apply_impulse((Vector2(650, 550) - piece.global_position).normalized() * 1500.0)  # converge: a pile-up

	var moving := await Perf.frame_stats(t, MOVING_FRAMES)
	Perf.within_frames(t, "furniture pile moving", moving, Perf.SMOOTH_AVG_MS, Perf.SMOOTH_P95_MS, Perf.SMOOTH_MAX_MS)

	var travelled := 0.0
	for i in count:
		travelled += (t.object(_id(i)) as Node2D).global_position.distance_to(starts[i])
	t.check(travelled / count > 10.0, "the shove actually moved the pieces (avg %.1f px)" % (travelled / count))

	# Settle: until every piece is asleep (at most 6 s), so the resting cost below is measured on a pile at rest.
	var all_asleep := func() -> bool:
		for i in count:
			var body := t.object(_id(i)) as RigidBody2D
			if body != null and not body.sleeping:
				return false
		return true
	await t.until(all_asleep, 6.0)
	var resting := await Perf.frame_stats(t, RESTING_FRAMES)
	Perf.within(t, "furniture pile resting avg ms/frame", resting["avg_ms"], Perf.SMOOTH_AVG_MS)
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF furniture pile node growth %d" % grown)
	t.check(grown <= 2, "shoving furniture neither spawns nor leaks nodes (grew by %d)" % grown)
