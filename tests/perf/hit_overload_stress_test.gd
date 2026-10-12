extends GameTest

## Performance guard: hundreds of hits land on one chair and one character. Deformation, debris and blood
## each have a cap (`deform_max_impacts`, the Despawner, the per-body splatter cap); the caps hold and frame
## cost stays within budget while the hits land.

const Perf := preload("res://tests/_perf/perf_probe.gd")

const HITS_PER_FRAME := 4
const FRAMES := 150
# Baseline: avg ~17 / p95 ~30 / max ~35 ms per frame, N BloodSplat (re-measure). Time budgets ~4-5x; the pool limit is
# a count, so it is tight.
const AVG_MS := 80.0
const P95_MS := 130.0
const MAX_MS := 160.0
const BLOOD_SPLAT_LIMIT := 80  # BloodConfig.max_splats_per_body, plus slack for ones not yet freed


func describe() -> Dictionary:
	return {
		"name": "Hundreds of hits keep deformation, debris and blood capped",
		"description": "600 hits land on a chair and 600 on a sturdy character; recorded dents, tracked debris and blood splatters stay capped and frame cost stays within budget.",
		"tags": ["deformation", "debris", "blood"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"physics.debris", true)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(200, 200))
	s.actor(&"victim", &"puppet", Vector2(500, 200), { "max_health": 1000000.0 })


func _hit(at: Vector2, i: int, source: Node) -> HitInfo:
	var hit := HitInfo.new()
	hit.position = at + Vector2.from_angle(i * 0.9) * 10.0
	hit.normal = Vector2.from_angle(i * 0.9)
	hit.direction = -hit.normal
	hit.damage = 25.0
	hit.source = source
	return hit


func run(t: TestContext) -> void:
	var chair := t.object(&"chair")
	var victim := t.actor(&"victim")
	var deformable: Node = null
	for child in chair.get_children():
		if child is Deformable:
			deformable = child
	if not t.require(deformable != null, "the chair composes a Deformable"):
		return
	await t.frames(2)

	var land := func(frame: int):
		for k in HITS_PER_FRAME:
			var i := frame * HITS_PER_FRAME + k
			chair.take_hit(_hit(chair.global_position, i, null))
			victim.take_hit(_hit(victim.global_position, i, null))
	var stats := await Perf.frame_stats(t, FRAMES, land)
	Perf.within_frames(t, "hit overload", stats, AVG_MS, P95_MS, MAX_MS)

	t.check(deformable.impacts.size() <= PhysicsConfig.deform_max_impacts,
		"recorded dents stay capped (%d, cap %d)" % [deformable.impacts.size(), PhysicsConfig.deform_max_impacts])
	t.check(Despawner.count() <= Despawner.max_scene_objects, "the Despawner cap holds (%d tracked)" % Despawner.count())
	var live := t.world.find_children("BloodSplat*", "Node2D", true, false).size()
	GameLog.say("PERF hit overload live blood splats %d" % live)
	t.trace("live blood splats", live)
	t.check(live <= BLOOD_SPLAT_LIMIT, "live blood splats: %d, limit %d" % [live, BLOOD_SPLAT_LIMIT])
	t.check(not victim.is_dead, "the victim survived the hits")
