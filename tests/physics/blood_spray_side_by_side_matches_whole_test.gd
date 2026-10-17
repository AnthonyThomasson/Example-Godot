extends GameTest

## A hit's spray throws up to six splats (`BloodWound.record`). They are merged side by side: each splat is begun as it is
## thrown (`BloodSplat.begin`: its random shapes and wall rays here, its outlines merged on a worker thread) and all are finished
## before `record` returns, where the plain way builds each whole (`setup`) in turn. This throws the same seeded hits both ways,
## by furniture that clips the blood, and checks every splat is the same: where it lies, its outlines point for point, its
## wet highlight, its place in the blood field, and the random draws left after the spray.

const SEED := 4242
const HITS := 24


func describe() -> Dictionary:
	return {
		"name": "A spray merged side by side is the spray built whole",
		"description": "BloodWound.record's splats, begun and merged on worker threads, equal the splats built whole one after another from the same seeded hits.",
		"tags": ["blood", "splat", "threads"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"nav.rebake", false)
	s.set_static(BloodWound, &"spray_side_by_side", true)  # put back after the test, whatever it leaves
	s.object(&"sofa", "sofa", Vector2(300, 150))
	s.object(&"chair", "chair", Vector2(380, 230))
	s.actor(&"victim", &"puppet", Vector2(300, 220), { "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	await t.frames(2)
	var victim := t.actor(&"victim")
	var wound: BloodWound = victim._wound
	var differing: Array = []
	var splats := 0
	var unfinished := 0
	for k in HITS:
		var hit := HitInfo.new()
		hit.normal = Vector2.from_angle(k * 0.9)
		hit.direction = -hit.normal
		hit.position = victim.global_position + hit.normal * 10.0
		hit.damage = 40.0
		hit.has_exit = k % 2 == 0
		hit.exit_position = victim.global_position - hit.normal * 10.0
		var sides: Array = []
		for side_by_side in [true, false]:
			BloodWound.spray_side_by_side = side_by_side
			wound._drips = 0  # owing no drips, so each side draws the drip wait the same
			seed(SEED + k)
			var before := wound._splats.size()
			wound.record(hit)
			var made: Array = []
			for i in range(before, wound._splats.size()):
				var splat: Node2D = wound._splats[i]
				made.append([splat.global_position, splat.shapes.duplicate(), splat.get_node_or_null("Highlight") != null,
					BloodField._splats.has(splat.get_instance_id())])
				unfinished += 1 if splat._task >= 0 else 0
			made.append(randf())  # the random draws left after the spray
			sides.append(made)
			for i in range(wound._splats.size() - 1, before - 1, -1):
				wound._splats[i].free()
				wound._splats.remove_at(i)
		BloodWound.spray_side_by_side = true
		splats += sides[0].size() - 1
		if sides[0] != sides[1]:
			differing.append(k)
	t.check(splats >= HITS * 5, "the hits threw splats (%d)" % splats)
	t.check(unfinished == 0, "every begun splat was finished before record returned (%d not)" % unfinished)
	t.check(differing.is_empty(), "every spray merged side by side is the spray built whole (differing hits %s)" % str(differing))
