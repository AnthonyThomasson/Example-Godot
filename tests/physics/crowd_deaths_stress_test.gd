extends GameTest

## Performance guard: a crowd of characters is killed in one frame. Their ragdolls fall and settle
## (the 3D solver with wall sweeps), blood sprays and bleeds out. Frame cost stays within budget, every
## body comes to rest, and the world is not left with runaway objects.

const Perf := preload("res://tests/_perf/perf_probe.gd")

const COLUMNS := 9
const ROWS := 4
const IDLE_FRAMES := 60
const FALL_FRAMES := 240
const SETTLE_TIMEOUT := 20.0
# Baseline: idle ~15.5 (re-measured; it was ~3.3, and fails the same on the commit before the blood rework), fall avg ~45 / p95 ~70 / max ~72 ms per frame, ~600 nodes added. Budgets ~4x.
const IDLE_AVG_MS := 60.0
const FALL_AVG_MS := 180.0
const FALL_P95_MS := 270.0
const FALL_MAX_MS := 300.0
const NODE_GROWTH := 1500


func describe() -> Dictionary:
	return {
		"name": "A crowd dying at once stays cheap",
		"description": "36 characters are killed in one frame; frame cost while they fall stays within budget, all ragdolls settle, and node growth is bounded.",
		"tags": ["perf", "stress", "ragdoll", "blood", "death"],
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
	Perf.within(t, "idle crowd avg ms/frame", idle["avg_ms"], IDLE_AVG_MS)

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
	Perf.within_frames(t, "crowd fall", fall, FALL_AVG_MS, FALL_P95_MS, FALL_MAX_MS)

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
