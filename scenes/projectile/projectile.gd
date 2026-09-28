extends Node2D

## Projectile CONTROL layer. A bullet fired by a gun: each physics frame it sweeps
## forward along `direction` with a raycast (robust at high speed — an overlap
## check would tunnel through walls between frames). On hitting a collider it does
## not simply stop: it resolves the hit against the struck object's `coverage` /
## `penetration` (see scenes/objects/environment_object.gd; walls fall back to
## Config.wall_*), so the bullet may fly over low cover, ricochet off hard material
## on a glancing angle, or penetrate — dealing damage and bleeding speed — and keep
## travelling. It frees itself once its speed drops below Config.projectile_min_speed
## or it passes `max_distance`. Drawing lives in projectile_visuals.gd. Spawned at
## runtime by ProjectileSpawner into the world (Main), not under the player.

## Travel speed in px/s. Set on the projectile itself; ProjectileSpawner seeds it
## from Config.projectile_speed, and it can be overridden per-instance.
@export var speed: float = 1600.0
## Max distance before the bullet gives up and frees itself (px).
@export var max_distance: float = 2000.0
## The projectile's own base damage. ProjectileSpawner adds the firing item's damage
## on top at spawn; the value dealt on impact is further scaled by how square the hit is.
@export var damage: float = 10.0
## Physics layers the bullet can hit (walls + solid furniture default to layer 1).
@export_flags_2d_physics var collision_mask: int = 1
## Streak color (read by projectile_visuals.gd).
@export var color: Color = Color(1.0, 0.9, 0.4)
## Streak length in px (read by projectile_visuals.gd).
@export var length: float = 12.0

## Unit travel vector, set by the spawner before add_child. Mutated on ricochet /
## penetration deflection as the bullet travels.
var direction := Vector2.RIGHT
## Body to skip in the sweep (the shooter) — everything is on layer 1.
var ignore: Node
## Distance travelled so far.
var _traveled := 0.0
## Colliders already flown over or penetrated: excluded from further sweeps so the
## bullet doesn't re-hit the same body. (Ricochets are NOT added — a bounced bullet
## may legitimately strike the same surface again.) Seeded with the shooter.
var _exclude: Array[RID] = []

## Emitted on each damaging interaction (penetration or ricochet), just before the
## bullet moves on or frees itself. `damage` is the value actually dealt (base + item,
## scaled by how square the impact was, and further reduced for a ricochet). A bullet
## may emit this more than once now; a fly-over emits nothing.
signal hit(body: Node, damage: float)


func _ready() -> void:
	# The player is never rotated, so `direction` is already a world-space unit
	# vector; orient the streak along it.
	rotation = direction.angle()
	if ignore is CollisionObject2D:
		_exclude.append(ignore.get_rid())


func _physics_process(delta: float) -> void:
	# Consume this frame's travel distance, resolving each collider crossed. The
	# bullet can change direction/speed mid-frame (ricochet/deflection), so we loop
	# rather than casting once. A guard caps iterations against a pathological
	# bounce loop.
	var remaining := speed * delta
	var guard := 0
	while remaining > 0.0:
		guard += 1
		if guard > 16:
			return

		var target := position + direction * remaining
		var result := _sweep(target)
		if result.is_empty():
			position = target
			_traveled += remaining
			remaining = 0.0
		else:
			var advanced := position.distance_to(result.position)
			position = result.position  # Snap to the contact point.
			_traveled += advanced
			remaining = maxf(remaining - advanced, 0.0)
			_resolve(result)
			# Nudge just past the contact (along the possibly-new direction) so the
			# next sweep starts clear of this surface.
			position += direction * 0.5
			if speed < Config.projectile_min_speed:
				queue_free()
				return

		if _traveled >= max_distance:
			queue_free()
			return


## Raycast from the current position to `to`, skipping already-handled colliders.
func _sweep(to: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(position, to, collision_mask)
	query.hit_from_inside = true  # Register even a point-blank shot against a wall.
	query.exclude = _exclude
	return space.intersect_ray(query)


## Resolve one hit against the struck object's coverage/penetration, mutating
## direction / speed / _exclude and emitting `hit` for damaging outcomes.
func _resolve(result: Dictionary) -> void:
	var body: Node = result.collider
	var rid: RID = result.rid
	# Squareness: alignment of travel with the surface normal (both unit vectors),
	# 1 = head-on. A zero-length normal (point-blank hit_from_inside) counts as square.
	var n: Vector2 = result.normal
	var squareness := 1.0 if n.length() < 0.001 else absf(direction.dot(n))

	var ratings := _ratings_for(body)
	var coverage: float = ratings.x
	var penetration: float = ratings.y

	# 1. Fly over (probabilistic, coverage-driven): no damage, no effect; skip this
	# body from here on and keep flying. Walls (coverage 100) never fly over.
	var flyover_chance := clampf((1.0 - coverage / 100.0) * Config.cover_flyover_scale, 0.0, 1.0)
	if randf() < flyover_chance:
		_exclude.append(rid)
		print("Shot flew over %s" % body.name)
		return

	# 2. Ricochet (hard material + glancing angle): reduced damage, reflect and keep
	# going at reduced speed. Not excluded — a bounced bullet can hit things again.
	if penetration >= Config.penetration_bounce_min and squareness < Config.bounce_square_max:
		var bounce_dmg := damage * squareness * Config.bounce_damage_retention
		direction = direction.bounce(n).normalized()
		rotation = direction.angle()
		speed *= Config.bounce_speed_retention
		print("Shot ricocheted off %s for %.0f damage (%.0f%% square)" % [body.name, bounce_dmg, squareness * 100.0])
		hit.emit(body, bounce_dmg)
		return

	# 3. Penetrate (everything else): deal squareness-scaled damage, bleed speed
	# (more when glancing or when the material is hard) and deflect slightly.
	var dealt := damage * squareness
	# Too slow to punch through: the object blocks the bullet — it takes the impact
	# and then stops (embeds). Speed is zeroed so the physics loop frees it.
	if speed < Config.penetration_min_speed:
		print("Shot blocked by %s for %.0f damage (%.0f%% square)" % [body.name, dealt, squareness * 100.0])
		speed = 0.0
		hit.emit(body, dealt)
		return
	var loss := clampf((penetration / 100.0) * Config.penetrate_loss_scale * (2.0 - squareness), 0.0, 1.0)
	speed *= (1.0 - loss)
	var j := deg_to_rad(Config.penetrate_deflect_max_deg * penetration / 100.0)
	direction = direction.rotated(randf_range(-j, j))
	rotation = direction.angle()
	_exclude.append(rid)
	print("Shot penetrated %s for %.0f damage (%.0f%% square)" % [body.name, dealt, squareness * 100.0])
	hit.emit(body, dealt)


## (coverage, penetration) for a struck collider: from the object if it exposes them
## (environment_object.gd), else the Config.wall_* fallback (room walls, etc.).
func _ratings_for(body: Node) -> Vector2:
	var cov: Variant = body.get("coverage")
	var pen: Variant = body.get("penetration")
	if cov == null or pen == null:
		return Vector2(Config.wall_coverage, Config.wall_penetration)
	return Vector2(cov, pen)
