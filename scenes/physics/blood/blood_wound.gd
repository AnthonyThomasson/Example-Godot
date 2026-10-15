class_name BloodWound
extends Node

## Physics System, blood: a wounded body's bleeding, composed by the character like Knockback / Deformable. Each hit
## throws a quick spray of splatters out of the wound (`record`) and adds to a budget of drips; then, while the budget
## lasts, one drop falls every BloodConfig.drip_interval_min..max seconds from where the body's blood leaves it, landing
## as a BloodSplat (a moving body's drops land ahead of it and stretch with its speed). `stop` ends the dripping (the
## body died; its bleed-out pool takes over). Splatters are added to the body's parent and capped per body
## (BloodConfig.max_splats_per_body, oldest freed first). Nothing happens while BloodConfig.enabled is off.

## Drips still owed, and seconds until the next one.
var _drips := 0
var _wait := 0.0
## This body's splatters, oldest first.
var _splats: Array[Node] = []
var _stopped := false  ## Set by `stop()` (death): no more splatters or drips.


func _ready() -> void:
	set_physics_process(false)


## Take a hit: spray splatters from `hit.position` out the wound's exit side and owe more drips.
func record(hit: HitInfo) -> void:
	if not BloodConfig.enabled or _stopped:
		return
	var host := get_parent() as Node2D
	if host == null:
		return
	var out := hit.normal if hit.normal.length() > 0.001 else -hit.direction
	var sprays := clampi(ceili(hit.damage / maxf(BloodConfig.hit_splat_damage, 0.001)), 1, BloodConfig.hit_splat_max)
	for i in sprays:
		var dir := out.rotated(randf_range(-BloodConfig.hit_spray_spread, BloodConfig.hit_spray_spread))
		var reach := randf_range(BloodConfig.hit_spray_reach_min, BloodConfig.hit_spray_reach_max) if i > 0 else 0.0
		var size := randf_range(BloodConfig.drip_size_min, BloodConfig.drip_size_max) * BloodConfig.hit_splat_size
		_add_splat(hit.position + dir * reach, size, dir, BloodConfig.hit_spray_energy if i > 0 else 0.4)

	# A round that went right through also throws blood out the far side, along its flight.
	if hit.has_exit:
		var size := randf_range(BloodConfig.drip_size_min, BloodConfig.drip_size_max) * BloodConfig.hit_splat_size
		_add_splat(hit.exit_position, size, hit.direction, BloodConfig.hit_spray_energy)

	var owed := maxi(1, ceili(hit.damage * BloodConfig.drips_per_damage))
	if _drips == 0:
		_wait = _next_wait()
	_drips = mini(_drips + owed, BloodConfig.max_pending_drips)
	set_physics_process(true)


## The body died: no more drips.
func stop() -> void:
	_stopped = true
	_drips = 0
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not BloodConfig.enabled:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_drip()
	_drips -= 1
	if _drips <= 0:
		set_physics_process(false)
	else:
		_wait = _next_wait()


## One drop leaves the body and lands: it keeps the body's walking velocity for `drip_fall_time`, so a
## walker's drops land ahead of it and splat stretched along its heading.
func _drip() -> void:
	var host := get_parent() as Node2D
	if host == null:
		return
	var origin: Vector2 = host.blood_origin() if host.has_method("blood_origin") else host.global_position
	var velocity := Vector2.ZERO
	var v = host.get("velocity")
	if v is Vector2:
		velocity = v
	var land := origin + velocity * BloodConfig.drip_fall_time + _jitter()
	var energy := clampf(velocity.length() / maxf(BloodConfig.drip_full_energy_speed, 0.001), 0.0, 1.0)
	var size := randf_range(BloodConfig.drip_size_min, BloodConfig.drip_size_max)
	_add_splat(land, size, velocity, energy)


## Seconds until the next drip falls, drawn from the configured interval.
func _next_wait() -> float:
	return randf_range(BloodConfig.drip_interval_min, BloodConfig.drip_interval_max)


## A random offset, up to `BloodConfig.drip_jitter` px, that scatters where a drip lands.
func _jitter() -> Vector2:
	return Vector2.from_angle(randf() * TAU) * randf() * BloodConfig.drip_jitter


## Place a splatter at world `at` and keep it within this body's cap.
func _add_splat(at: Vector2, size: float, direction: Vector2, energy: float) -> void:
	var host := get_parent() as Node2D
	var splat := BloodSpawner.splat(host.get_parent(), at, size, direction, energy, [(host as CollisionObject2D).get_rid()] if host is CollisionObject2D else [])
	_splats.append(splat)
	while _splats.size() > BloodConfig.max_splats_per_body or (not _splats.is_empty() and not is_instance_valid(_splats[0])):
		# Untyped: the loop also pops an already-freed splat (something else freed it), and assigning a freed
		# instance to a typed `Node` is an engine error.
		var oldest = _splats.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
