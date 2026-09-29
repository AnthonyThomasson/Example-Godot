extends Node2D

## One blood pool that fills in and grows over time: colliderless world-space drops released a few
## per second from a wound. Each drop emerges at the wounded body's current position (so a moving
## character trails blood rather than leaving it all at the first contact point), creeps outward
## from there, slides around walls and furniture (never through them), and settles packed next to
## the blood already there. Each hit on the body calls `add_hit`, adding volume and widening the
## fill disc (`_spread`) toward BloodConfig.pool_radius_max, so a still victim bled repeatedly pools
## out wide while a lone wound stays small; the volume is capped at BloodConfig.max_pool_volume.
## Despawner-tracked. Drawing lives in blood_pool_visuals.gd; this control node owns the fill only.

## Physics layer the drops avoid — walls and furniture (the default world layer).
const COLLISION_MASK := 1
## Vertices in each drop's blob outline — enough to look round-ish while its lumps stay visible.
const BLOB_VERTS := 11

## Live drops, each a Dictionary: pos (local, px), origin (local, px — where it emerged), vel
## (px/s), target (px, distance from origin it settles at), radius (px), shape (PackedFloat32Array
## of per-vertex radius multipliers giving the blob its lumpy outline), settled (bool). The visuals
## child reads this while the pool fills. Public so the draw layer sees it.
var particles: Array[Dictionary] = []

## Collider RIDs the drop queries ignore — the wounded body, so its own collider never traps
## the blood spilling out of it.
var _exclude: Array = []
## Unit direction the pool leans toward (the wound's exit side).
var _aim := Vector2.RIGHT
## Drops this pool will release; grows with each hit up to BloodConfig.max_pool_volume.
var _count := 0
## Radius (px) of this pool's fill disc; grows with volume toward BloodConfig.pool_radius_max.
var _spread := 0.0
## The wounded body drops emerge from; sampled live so a moving body trails blood. May go invalid
## if the body despawns, after which drops fall back to emerging at the pool's own origin.
var _source: Node2D
## Drops released so far.
var _emitted := 0
## Fractional drop budget accrued at the emission rate; drops release as it passes whole numbers.
var _emit_budget := 0.0

## Reusable query shape (the small circle each drop sweeps with).
var _probe: CircleShape2D
## This pool's outline: a ring of random radius multipliers the fill radius is warped by (smoothly
## interpolated between them). A fresh random count and values per pool, so no two silhouettes match.
var _edge_profile: PackedFloat32Array = PackedFloat32Array()

@onready var _visuals := $BloodPoolVisuals  ## The draw layer child.


func _ready() -> void:
	_probe = CircleShape2D.new()
	_probe.radius = BloodConfig.query_radius


## This pool's current drop count — how much blood it holds. Read by BloodSpawner to enforce the
## per-character cap.
func blood_volume() -> int:
	return _count


## This pool's fill radius (px) — how far its puddle reaches. Read by BloodSpawner to tell whether a
## fresh wound lands on top of this pool (and so should grow it rather than start a new one).
func spread() -> float:
	return _spread


## Start the pool for a body wounded at exit side `direction`; `exclude` is the body's RID(s) and
## `source` the body itself, whose live position each drop emerges from. Adds the first hit's volume.
func seed(direction: Vector2, exclude: Array, source: Node2D) -> void:
	_exclude = exclude
	_aim = direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT
	_source = source
	_make_edge_profile()
	add_hit(direction)


## Add one wound's worth of blood: bump the volume (capped) and widen the fill disc from the volume
## above the first hit, then resume emitting. Called for the first hit by `seed` and for each later
## hit that lands on this pool, so a still victim's pool pools out wider with every hit.
func add_hit(direction: Vector2) -> void:
	if direction.length() > 0.001:
		_aim = direction.normalized()
	_count = mini(_count + BloodConfig.particle_count, BloodConfig.max_pool_volume)
	var growth := maxi(0, _count - BloodConfig.particle_count)
	_spread = clampf(BloodConfig.pool_radius_base + growth * BloodConfig.spread_per_volume,
		BloodConfig.pool_radius_base, BloodConfig.pool_radius_max)
	set_physics_process(true)


## Roll this pool's outline: a random number of random radius multipliers around the ring. Both the
## count and the values are fresh per pool, so the interpolated silhouette differs every time
## instead of being one fixed lobe pattern rotated.
func _make_edge_profile() -> void:
	_edge_profile = PackedFloat32Array()
	var count := randi_range(5, 12)
	for i in count:
		_edge_profile.append(randf_range(1.0 - BloodConfig.edge_irregularity, 1.0 + BloodConfig.edge_irregularity))


## Radius multiplier for a drop heading at `angle`: smoothstep-interpolated between the two nearest
## profile points, so the outline is a smooth but irregular closed curve. Floored so it never
## pinches to nothing.
func _edge_factor(angle: float) -> float:
	var count := _edge_profile.size()
	if count == 0:
		return 1.0
	var t := wrapf(angle, 0.0, TAU) / TAU * count
	var i := int(floor(t))
	var frac := t - i
	frac = frac * frac * (3.0 - 2.0 * frac)
	var a := _edge_profile[i % count]
	var b := _edge_profile[(i + 1) % count]
	return maxf(0.35, lerpf(a, b, frac))


## Build one drop's fixed blob outline: a ring of unit radius multipliers with per-vertex random
## lumps, lightly smoothed so the blob reads as an organic splat rather than a spiky or regular
## polygon. Stored on the drop and scaled by its live radius when drawn.
func _make_blob_shape() -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	for i in BLOB_VERTS:
		raw.append(1.0 + randf_range(-BloodConfig.blob_wobble, BloodConfig.blob_wobble))
	var shape := PackedFloat32Array()
	for i in BLOB_VERTS:
		# Average each vertex with its neighbors so lumps are rounded, not jagged spikes.
		var prev := raw[(i - 1 + BLOB_VERTS) % BLOB_VERTS]
		var next := raw[(i + 1) % BLOB_VERTS]
		shape.append((prev + raw[i] * 2.0 + next) / 4.0)
	return shape


func _physics_process(delta: float) -> void:
	_release_due(delta)

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


## Release drops at a steady rate (one base pool's worth over BloodConfig.spill_duration), up to the
## volume accrued so far. Rate-based so added hits keep feeding out smoothly as the pool grows.
func _release_due(delta: float) -> void:
	var rate := BloodConfig.particle_count / maxf(BloodConfig.spill_duration, 0.001)
	_emit_budget += rate * delta
	while _emitted < _count and _emitted < _emit_budget:
		_add_drop(_emitted)
		_emitted += 1


## Create the drop with the given fill index and send it creeping outward from the wound's current
## position. Targets fill the disc by area (radius ∝ √index), so early drops stay near the center
## and outer ones ring the edge — the drops end up packed next to each other rather than piled up.
func _add_drop(index: int) -> void:
	var frac := (index + 0.5) / float(maxi(_count, 1))
	var dir := Vector2.RIGHT.rotated(randf() * TAU).slerp(_aim, BloodConfig.directional_bias).normalized()
	# Warp the target distance by this pool's lobed outline so its silhouette is irregular.
	var target := _spread * sqrt(frac) * randf_range(BloodConfig.target_jitter_min, BloodConfig.target_jitter_max) * _edge_factor(dir.angle())
	var speed := randf_range(BloodConfig.speed_min, BloodConfig.speed_max)
	# Emerge at the wounded body's current spot (local to this pool), so a moving body trails blood
	# instead of piling it at the first contact point; fall back to the pool origin if it is gone.
	var origin := (_source.global_position - global_position) if is_instance_valid(_source) else Vector2.ZERO
	particles.append({
		"pos": origin,
		"origin": origin,
		"vel": dir * speed,
		"target": target,
		"radius": BloodConfig.drop_radius_min,
		"shape": _make_blob_shape(),
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

	# Reach is measured from where the drop emerged, so a drop that comes out far from the pool
	# origin (the body having moved) still spreads only its own target distance and settles.
	var reach: float = (p["pos"] as Vector2).distance_to(p["origin"])
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
