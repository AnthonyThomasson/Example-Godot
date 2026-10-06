extends Node2D

## A bullet: the control layer of the Projectile System. Each physics frame it sweeps
## forward along `direction` with a raycast and resolves every collider it crosses against
## that object's surface, so it may fly over cover, ricochet, penetrate, or embed. It frees
## itself once spent or past `max_distance`. Drawing lives in projectile_visuals.gd.

## Travel speed in px/s.
@export var speed: float = 1600.0
## Distance the bullet may travel before freeing itself (px).
@export var max_distance: float = 2000.0
## Base damage, before the firing item's damage and the per-hit squareness/speed scaling.
@export var damage: float = 10.0
## Physics layers the bullet can hit.
@export_flags_2d_physics var collision_mask: int = 1
## Streak color.
@export var color: Color = Color(1.0, 0.9, 0.4)
## Streak length in px.
@export var length: float = 7.0

## Unit travel vector; reassigned on ricochet / penetration deflection.
var direction := Vector2.RIGHT
## Body to skip in the sweep (the shooter).
var ignore: Node
## Distance travelled so far.
var _traveled := 0.0
## Colliders excluded from further sweeps (flown over or penetrated), so the bullet does not
## re-hit them. Ricochets are not added — a bounced bullet may strike the same surface again.
var _exclude: Array[RID] = []

## Emitted for each damaging interaction with the dealt damage. A fly-over emits nothing.
signal hit(body: Node, damage: float)


func _ready() -> void:
	rotation = direction.angle()
	if ignore is CollisionObject2D:
		_exclude.append(ignore.get_rid())


## Advance one frame's travel, resolving each collider crossed. Loops rather than casting
## once because a hit can change direction/speed mid-frame; the guard caps a bounce loop.
func _physics_process(delta: float) -> void:
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
			if speed < BallisticsConfig.projectile_min_speed:
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


## Pick one outcome for a hit and, when it deals damage, hand the object a HitInfo (the
## object owns the shove/deform/debris). Mutates direction/speed/_exclude and re-emits `hit`.
func _resolve(result: Dictionary) -> void:
	var body: Node = result.collider
	var rid: RID = result.rid
	# Squareness: |travel · normal|, 1 = head-on. A degenerate normal counts as square.
	var n: Vector2 = result.normal
	var squareness := 1.0 if n.length() < 0.001 else absf(direction.dot(n))
	# Incoming speed relative to muzzle speed: a fast shot hits harder.
	var speed_factor := speed / BallisticsConfig.projectile_speed if BallisticsConfig.projectile_speed > 0.0 else 1.0
	# Captured before the ricochet branch reassigns `direction`; the shove follows the shot in.
	var incoming := direction

	var surface := _surface_for(body)
	var coverage: float = surface["coverage"]
	var penetration: float = surface["penetration"]

	# 1. Fly over cover: no damage, exclude the body, keep flying.
	var flyover_chance := clampf((1.0 - coverage / 100.0) * BallisticsConfig.cover_flyover_scale, 0.0, 1.0)
	if randf() < flyover_chance:
		_exclude.append(rid)
		print("Shot flew over %s" % body.name)
		return

	# 2. Ricochet off hard material at a glancing angle: reflect at reduced speed/damage.
	# Not excluded — a bounced bullet can strike the same surface again.
	if penetration >= BallisticsConfig.penetration_bounce_min and squareness < BallisticsConfig.bounce_square_max:
		var bounce_dmg := damage * squareness * speed_factor * BallisticsConfig.bounce_damage_retention
		direction = direction.bounce(n).normalized()
		rotation = direction.angle()
		speed *= BallisticsConfig.bounce_speed_retention
		print("Shot ricocheted off %s for %.0f damage (%.0f%% square)" % [body.name, bounce_dmg, squareness * 100.0])
		_deal(body, _hit_info(result, incoming, speed_factor, bounce_dmg, false))
		return

	var dealt := damage * squareness * speed_factor
	# 3a. Too slow to punch through: deal the impact and embed (zeroed speed frees the bullet).
	if speed < BallisticsConfig.penetration_min_speed:
		print("Shot blocked by %s for %.0f damage (%.0f%% square)" % [body.name, dealt, squareness * 100.0])
		speed = 0.0
		_deal(body, _hit_info(result, incoming, speed_factor, dealt, false))
		return
	# 3b. Penetrate: deal damage, bleed speed (more when glancing/hard), deflect slightly.
	var loss := clampf((penetration / 100.0) * BallisticsConfig.penetrate_loss_scale * (2.0 - squareness), 0.0, 1.0)
	speed *= (1.0 - loss)
	var j := deg_to_rad(BallisticsConfig.penetrate_deflect_max_deg * penetration / 100.0)
	direction = direction.rotated(randf_range(-j, j))
	rotation = direction.angle()
	_exclude.append(rid)
	print("Shot penetrated %s for %.0f damage (%.0f%% square)" % [body.name, dealt, squareness * 100.0])
	_deal(body, _hit_info(result, incoming, speed_factor, dealt, true))


## The struck object's surface via get_surface(), or the wall-rating fallback for a collider
## that exposes none.
func _surface_for(body: Node) -> Dictionary:
	if body.has_method("get_surface"):
		return body.get_surface()
	return { "coverage": BallisticsConfig.wall_coverage, "penetration": BallisticsConfig.wall_penetration }


## Build the HitInfo handed to the struck object for one damaging interaction.
func _hit_info(result: Dictionary, incoming: Vector2, speed_factor: float, dealt: float, penetrated: bool) -> HitInfo:
	var info := HitInfo.new()
	info.position = result.position
	info.normal = result.normal
	info.direction = incoming
	info.damage = dealt
	info.speed_factor = speed_factor
	info.penetrated = penetrated
	info.source = self
	return info


## Hand the hit to the object (if hittable), re-emit `hit`, and post a world `&"hit"` event so
## decoupled listeners (the AI's combat awareness) learn that something was struck, where, and by
## whom (`attacker` = the shooter, or null).
func _deal(body: Node, info: HitInfo) -> void:
	if body.has_method("take_hit"):
		body.take_hit(info)
	hit.emit(body, info.damage)
	EventBus.post(&"hit", {
		"position": info.position, "victim": body, "source": info.source,
		"direction": info.direction, "damage": info.damage,
		"attacker": ignore if is_instance_valid(ignore) else null,
	})
