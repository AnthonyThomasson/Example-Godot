extends GameTest

## Performance guard: a whole 5v5 match (ten characters) is killed in one frame, the worst thing that can happen to
## the frame time of a match. Their ragdolls fall and settle (the 3D solver with wall sweeps), blood sprays and bleeds
## out. Frame cost stays within the smooth-match standard, every body comes to rest, and the world is not left with
## runaway objects.

const Perf := preload("res://tests/_perf/perf_probe.gd")

const COLUMNS := 5
const ROWS := 2
const IDLE_FRAMES := 60
const FALL_FRAMES := 240
const SETTLE_TIMEOUT := 20.0
# Frame budgets are the smooth-match standard (Perf.SMOOTH_*), idle and while the bodies fall (the frame the deaths are
# dealt in is not measured). The crowd was 36 bodies (idle ~3.5 ms, falling avg ~57 / p95 ~90 / max ~92 ms before the
# performance work, ~45 / 65 / 67 after); that is nearly four matches' worth, so it is now one match's: falling avg ~13 /
# p95 ~18 / max ~21 ms, about 170 nodes added.
const NODE_GROWTH := 600


func describe() -> Dictionary:
	return {
		"name": "A crowd dying at once stays cheap",
		"description": "Ten characters (a whole 5v5) are killed in one frame; frame cost while they fall stays within budget, all ragdolls settle, and node growth is bounded.",
		"tags": ["ragdoll", "blood", "death"],
		"timeout": 40.0,
	}


func _id(i: int) -> StringName:
	return StringName("body%d" % i)


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 600))
	s.switch(&"physics.blood", true)
	for i in COLUMNS * ROWS:
		var at := Vector2(80 + (i % COLUMNS) * 100, 80 + (int(i / float(COLUMNS))) * 130)
		s.actor(_id(i), &"puppet", at, { "max_health": 1.0 })


func run(t: TestContext) -> void:
	var count := COLUMNS * ROWS
	var idle := await Perf.frame_stats(t, IDLE_FRAMES)
	Perf.within(t, "idle crowd avg ms/frame", idle["avg_ms"], Perf.SMOOTH_AVG_MS)

	var nodes_before := Perf.nodes()
	for i in count:
		var victim := t.actor(_id(i))
		var hit := HitInfo.new()
		hit.position = victim.global_position
		hit.normal = Vector2.LEFT
		hit.direction = Vector2.from_angle(i * 0.7)
		hit.damage = 10.0
		victim.take_hit(hit)
	t.check(t.actor(_id(0)).is_dead and t.actor(_id(count - 1)).is_dead, "the crowd is dead")

	var fall := await Perf.frame_stats(t, FALL_FRAMES)
	Perf.within_frames(t, "crowd fall", fall, Perf.SMOOTH_AVG_MS, Perf.SMOOTH_P95_MS, Perf.SMOOTH_MAX_MS)

	var settled := func():
		for i in count:
			if not t.actor(_id(i)).ragdoll.is_settled():
				return false
		return true
	t.check(await t.until(settled, SETTLE_TIMEOUT), "every ragdoll comes to rest")
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF crowd death node growth %d" % grown)
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "the deaths added %d nodes, budget %d" % [grown, NODE_GROWTH])
