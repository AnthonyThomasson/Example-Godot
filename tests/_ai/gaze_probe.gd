extends RefCounted

## Shared helpers for the gaze-and-fire tests (tests/ai/gaze/ and friends; not a test itself). The behaviour they
## assert is `docs/gaze-and-fire.md`: an NPC is always either looking at (and, when it can, shooting) a threat, or
## watching doors, never a wall and never with its back to a known threat. The geometry here is the test's own
## (door points, a ray along the facing), not read back from the code under test.


## The angle (degrees) between where actor `a` faces and the direction to world point `p`.
static func off(a: Node, p: Vector2) -> float:
	return rad_to_deg(absf((a.facing as Vector2).angle_to(p - a.global_position)))



## Whether a wall or solid piece stands within `reach` px dead ahead of actor `a` (along its facing), or of `from` along
## `facing` when those are given (a sampled frame rather than now).
static func wall_ahead(a: Node, reach := 70.0, from := Vector2.INF, facing := Vector2.INF) -> bool:
	var space: PhysicsDirectSpaceState2D = a.get_world_2d().direct_space_state
	var origin: Vector2 = a.global_position if from == Vector2.INF else from
	var dir: Vector2 = a.facing if facing == Vector2.INF else facing
	var q := PhysicsRayQueryParameters2D.create(origin, origin + dir * reach, PhysicsLayers.SOLID, [a.get_rid()])
	return not space.intersect_ray(q).is_empty()


## Sample the actors `ids` every physics frame for `duration` s (or until `stop` returns true): one
## `{ t, pos: { id: Vector2 }, facing: { id: Vector2 }, speed: { id: float } }` per frame.
static func watch(t: TestContext, ids: Array, duration: float, stop := Callable()) -> Array:
	var samples: Array = []
	var end := t.time + duration
	while t.time < end:
		var pos := {}
		var facing := {}
		var speed := {}
		for id in ids:
			var a := t.actor(id)
			if a == null:
				continue
			pos[id] = a.global_position
			facing[id] = a.facing
			speed[id] = (a.get_real_velocity() as Vector2).length()
		samples.append({ "t": t.time, "pos": pos, "facing": facing, "speed": speed })
		if stop.is_valid() and stop.call():
			break
		await t.frames(1)
	return samples


## Fraction of `samples` (from time `from` on) in which actor `id` faces within `degrees` of any of `points`.
static func share_facing(samples: Array, id: StringName, points: Array, degrees: float, from := 0.0) -> float:
	var total := 0
	var hits := 0
	for s in samples:
		if s["t"] < from or not s["pos"].has(id):
			continue
		total += 1
		var best := 360.0
		for p in points:
			best = minf(best, rad_to_deg(absf((s["facing"][id] as Vector2).angle_to((p as Vector2) - (s["pos"][id] as Vector2)))))
		if best <= degrees:
			hits += 1
	return float(hits) / float(maxi(total, 1))


## Which of `points` actor `id` faced (within `degrees`) at some sample from time `from` on, as indices into `points`.
static func points_faced(samples: Array, id: StringName, points: Array, degrees: float, from := 0.0) -> Array:
	var faced: Array = []
	for s in samples:
		if s["t"] < from or not s["pos"].has(id):
			continue
		for i in points.size():
			var d := rad_to_deg(absf((s["facing"][id] as Vector2).angle_to((points[i] as Vector2) - (s["pos"][id] as Vector2))))
			if d <= degrees and not faced.has(i):
				faced.append(i)
	return faced
