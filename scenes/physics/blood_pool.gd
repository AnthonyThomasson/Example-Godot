extends Node2D

## One blood pool that fills in over time: colliderless world-space drops released from a wound
## a few at a time across BloodConfig.spill_duration. Each drop creeps outward to its spot in a
## growing disc, slides around walls and furniture (never through them), and settles packed next
## to the blood already there. Seeded by BloodSpawner, Despawner-tracked. Drawing lives in
## blood_pool_visuals.gd; this control node owns the fill simulation only.

## Physics layer the drops avoid — walls and furniture (the default world layer).
const COLLISION_MASK := 1

## Live drops, each a Dictionary: pos (local, px), vel (px/s), target (px, distance from center
## it settles at), radius (px), settled (bool). The visuals child reads this while the pool
## fills. Public so the draw layer sees it.
var particles: Array[Dictionary] = []

## Collider RIDs the drop queries ignore — the wounded body, so its own collider never traps
## the blood spilling out of it.
var _exclude: Array = []
## Unit direction the pool leans toward (the wound's exit side).
var _aim := Vector2.RIGHT
## Total drops this pool will release.
var _count := 0
## Drops released so far (emission runs across spill_duration).
var _emitted := 0
## Seconds elapsed since seeding, driving the emission schedule.
var _elapsed := 0.0

## Reusable query shape (the small circle each drop sweeps with).
var _probe: CircleShape2D

@onready var _visuals := $BloodPoolVisuals  ## The draw layer child.


func _ready() -> void:
	_probe = CircleShape2D.new()
	_probe.radius = BloodConfig.query_radius


## Begin a pool of `count` drops leaning along `direction` (the wound's exit side); `exclude` is
## the wounded body's RID(s). Drops are not created here — they are released over time in
## _physics_process so the pool fills in across BloodConfig.spill_duration.
func seed(direction: Vector2, count: int, exclude: Array) -> void:
	_exclude = exclude
	_aim = direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT
	_count = count
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_release_due()

	var space := get_world_2d().direct_space_state
	var any_active := false
	for p in particles:
		if p["settled"]:
			continue
		_advance(p, delta, space)
		if not p["settled"]:
			any_active = true

	_visuals.queue_redraw()
	# Stop simulating once every drop is out and at rest; the set pool then just persists.
	if _emitted >= _count and not any_active:
		set_physics_process(false)


## Release however many drops the elapsed time now calls for, spreading emission evenly across
## BloodConfig.spill_duration so the pool grows for the whole window.
func _release_due() -> void:
	var due := _count
	if BloodConfig.spill_duration > 0.0:
		due = ceili(_count * clampf(_elapsed / BloodConfig.spill_duration, 0.0, 1.0))
	while _emitted < due:
		_add_drop(_emitted)
		_emitted += 1


## Create the drop with the given fill index and send it creeping toward its spot. Targets fill
## the disc by area (radius ∝ √index), so early drops stay near the center and outer ones ring
## the edge — the drops end up packed next to each other rather than piled up.
func _add_drop(index: int) -> void:
	var frac := (index + 0.5) / float(maxi(_count, 1))
	var target := BloodConfig.pool_radius * sqrt(frac) * randf_range(BloodConfig.target_jitter_min, BloodConfig.target_jitter_max)
	var dir := Vector2.RIGHT.rotated(randf() * TAU).slerp(_aim, BloodConfig.directional_bias).normalized()
	var speed := randf_range(BloodConfig.speed_min, BloodConfig.speed_max)
	particles.append({
		"pos": Vector2.ZERO,
		"vel": dir * speed,
		"target": target,
		"radius": BloodConfig.drop_radius_min,
		"settled": false,
	})


## Move one drop for this frame: sweep its motion, slide off any obstacle it meets, grow its
## blob as it nears its spot, and settle it once it reaches its target distance (or gets wedged
## against geometry and can no longer make progress).
func _advance(p: Dictionary, delta: float, space: PhysicsDirectSpaceState2D) -> void:
	var before: Vector2 = p["pos"]
	var motion: Vector2 = p["vel"] * delta
	if motion.length_squared() > 0.0000001:
		var from: Vector2 = global_position + p["pos"]
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = _probe
		params.collision_mask = COLLISION_MASK
		params.exclude = _exclude
		params.transform = Transform2D(0.0, from)
		params.motion = motion

		var safe: float = space.cast_motion(params)[0]
		if safe >= 1.0:
			p["pos"] += motion
		else:
			# Blocked: advance up to the surface, then slide the leftover motion along it so the
			# blood hugs the obstacle and keeps flowing sideways (mirrors character_hands slide).
			p["pos"] += motion * safe
			var to: Vector2 = from + motion
			var ray := PhysicsRayQueryParameters2D.create(from, to, COLLISION_MASK)
			ray.exclude = _exclude
			var hit := space.intersect_ray(ray)
			var normal: Vector2 = hit.normal if hit and hit.normal.length() > 0.001 else -motion.normalized()
			var slide := (motion * (1.0 - safe)).slide(normal)
			params.transform = Transform2D(0.0, global_position + p["pos"])
			params.motion = slide
			p["pos"] += slide * space.cast_motion(params)[0]
			# Drop the into-surface component so its velocity now runs along the obstacle.
			p["vel"] = (p["vel"] as Vector2).slide(normal)

	var reach: float = (p["pos"] as Vector2).length()
	var target: float = p["target"]
	# Grow the blob toward full size as the drop closes on its spot.
	var progress := reach / target if target > 0.001 else 1.0
	p["radius"] = lerpf(BloodConfig.drop_radius_min, BloodConfig.drop_radius_max, clampf(progress, 0.0, 1.0))

	# Settle at the target ring, or when wedged against geometry with nowhere left to go.
	var stuck := motion.length_squared() > 0.0001 and (p["pos"] as Vector2).distance_squared_to(before) < 0.0001
	if reach >= target or stuck:
		p["settled"] = true
		p["vel"] = Vector2.ZERO
		p["radius"] = BloodConfig.drop_radius_max
