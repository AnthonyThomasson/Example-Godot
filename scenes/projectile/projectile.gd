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
@export_flags_2d_physics var collision_mask: int = PhysicsLayers.SOLID
## Streak color.
@export var color: Color = Color(1.0, 0.9, 0.4)
## Streak length in px.
@export var length: float = 7.0

## The speed it left the muzzle at (px/s): the reference its damage and impact scale against, so a weapon's
## damage is what it deals at full speed, head-on. The spawner sets it with `speed`.
var muzzle_speed: float = BallisticsConfig.projectile_speed
## Power to punch through what it hits (1 = a pistol round): it divides the speed lost to a surface and the
## deflection, and lowers the speed it needs to get through at all.
var penetration_power: float = 1.0
## The id of the gun that fired it (&"" when none), carried on its `hit` events so a listener can tell the rounds apart.
var gun: StringName = &""

## How high the bullet flies, 0..100: the same scale as an object's `coverage` (its height). One number for the
## whole flight, drawn once at spawn (see `BallisticsConfig.bullet_height`), so it clears or meets everything it
## crosses consistently: cover that stands taller than it is struck, anything lower is flown over.
var height := 0.0

## Unit travel vector; reassigned on ricochet / penetration deflection.
var direction := Vector2.RIGHT
## Body to skip in the sweep (the shooter).
var ignore: Node
## Distance travelled so far.
var _traveled := 0.0
## Colliders excluded from further sweeps (flown over or penetrated), so the bullet does not
## re-hit them. Ricochets are not added — a bounced bullet may strike the same surface again.
var _exclude: Array[RID] = []
## `_traveled` at the moment the bullet left a body carrying `BallisticsConfig.blood_material` (a character);
## -1 = carrying no blood. The next non-flesh surface within `blood_carry_distance` of it gets marked.
var _blood_from := -1.0

## Emitted for each damaging interaction with the dealt damage. A fly-over emits nothing.
signal hit(body: Node, damage: float)


func _ready() -> void:
	rotation = direction.angle()
	height = BallisticsConfig.bullet_height if BallisticsConfig.bullet_height >= 0.0 else randf() * 100.0
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
	# Incoming speed relative to this round's own muzzle speed: a fast shot hits harder.
	var speed_factor := speed / muzzle_speed if muzzle_speed > 0.0 else 1.0
	# Captured before the ricochet branch reassigns `direction`; the shove follows the shot in.
	var incoming := direction

	var surface := _surface_for(body)
	var coverage: float = surface["coverage"]
	var penetration: float = surface["penetration"]

	# 1. Fly over cover: the bullet is higher than the object stands. No damage, exclude the body, keep flying.
	# Coverage is the object's height, so a body behind cover that is taller than the bullet is flown over too:
	# cover 50 and a body of 60 -> a shot lower than 50 meets the cover (and may punch through to the body), one
	# between 50 and 60 clears the cover and strikes only the body, and a higher one misses both.
	if height >= _flyover_height(coverage):
		_exclude.append(rid)
		GameLog.say("Shot flew over %s" % body.name)
		return

	# 2. Ricochet off hard material at a glancing angle: reflect at reduced speed/damage.
	# Not excluded — a bounced bullet can strike the same surface again.
	if penetration >= BallisticsConfig.penetration_bounce_min and squareness < BallisticsConfig.bounce_square_max:
		var bounce_dmg := damage * squareness * speed_factor * BallisticsConfig.bounce_damage_retention
		direction = direction.bounce(n).normalized()
		rotation = direction.angle()
		speed *= BallisticsConfig.bounce_speed_retention
		GameLog.say("Shot ricocheted off %s for %.0f damage (%.0f%% square)" % [body.name, bounce_dmg, squareness * 100.0])
		_deal(body, _hit_info(result, incoming, speed_factor, bounce_dmg, false, _take_blood(surface)), &"ricochet", surface)
		return

	var dealt := damage * squareness * speed_factor
	# 3a. Too slow to punch through (a more penetrating round needs less speed): deal the impact and embed
	# (zeroed speed frees the bullet).
	if speed < BallisticsConfig.penetration_min_speed / penetration_power:
		GameLog.say("Shot blocked by %s for %.0f damage (%.0f%% square)" % [body.name, dealt, squareness * 100.0])
		speed = 0.0
		_deal(body, _hit_info(result, incoming, speed_factor, dealt, false, _take_blood(surface)), &"blocked", surface)
		return
	# 3b. Penetrate: deal damage, bleed speed (more when glancing/hard), deflect slightly.
	var loss := clampf((penetration / 100.0) * BallisticsConfig.penetrate_loss_scale * (2.0 - squareness)
		/ penetration_power, 0.0, 1.0)
	speed *= (1.0 - loss)
	var j := deg_to_rad(BallisticsConfig.penetrate_deflect_max_deg * penetration / 100.0 / penetration_power)
	direction = direction.rotated(randf_range(-j, j))
	rotation = direction.angle()
	_exclude.append(rid)
	GameLog.say("Shot penetrated %s for %.0f damage (%.0f%% square)" % [body.name, dealt, squareness * 100.0])
	var info := _hit_info(result, incoming, speed_factor, dealt, true, _take_blood(surface))
	_find_exit(info, result.position, rid, incoming)
	_deal(body, info, &"penetrate", surface)
	# Leaving a body (flesh) it carries that body's blood on from the exit.
	if StringName(surface.get("material", "")) == BallisticsConfig.blood_material:
		_blood_from = _traveled + (info.exit_position.distance_to(result.position) if info.has_exit else 0.0)


## The bullet height at and above which a collider of this `coverage` is flown over: its coverage, pushed toward
## "never" by a `cover_flyover_scale` below 1 (0 = never fly over) and toward "always" above it. Coverage 100
## stands taller than any bullet.
func _flyover_height(coverage: float) -> float:
	return clampf(100.0 - (100.0 - coverage) * BallisticsConfig.cover_flyover_scale, 0.0, 100.0)


## The struck object's surface via get_surface(), or the wall-rating fallback for a collider
## that exposes none.
func _surface_for(body: Node) -> Dictionary:
	if body.has_method("get_surface"):
		return body.get_surface()
	return { "coverage": BallisticsConfig.wall_coverage, "penetration": BallisticsConfig.wall_penetration }


## Build the HitInfo handed to the struck object for one damaging interaction.
func _hit_info(result: Dictionary, incoming: Vector2, speed_factor: float, dealt: float, penetrated: bool,
		blood: float = 0.0) -> HitInfo:
	var info := HitInfo.new()
	info.position = result.position
	info.normal = result.normal
	info.direction = incoming
	info.damage = dealt
	info.speed_factor = speed_factor
	info.penetrated = penetrated
	info.blood = blood
	info.source = self
	return info


## Blood this bullet hands to a non-flesh surface it strikes (0..1, fading with the distance since it left
## a body) and then has no more of: the first surface takes it all. 0 if it carries none or has gone
## `blood_carry_distance` px. Flesh never takes it (the wound has its own blood).
func _take_blood(surface: Dictionary) -> float:
	if _blood_from < 0.0 or StringName(surface.get("material", "")) == BallisticsConfig.blood_material:
		return 0.0
	var dist := _traveled - _blood_from
	_blood_from = -1.0
	var reach := BallisticsConfig.blood_carry_distance
	return clampf(1.0 - dist / reach, 0.0, 1.0) if reach > 0.0 and dist <= reach else 0.0


## Fill `info`'s exit fields for a bullet that just penetrated `rid` at `entry`: cast a ray back from
## `exit_probe_distance` px ahead toward the entry, skipping anything else in between, until it meets the
## penetrated collider's far face. Leaves `has_exit` false for a body thicker than the probe.
func _find_exit(info: HitInfo, entry: Vector2, rid: RID, travel: Vector2) -> void:
	if BallisticsConfig.exit_probe_distance <= 0.0:
		return
	var space := get_world_2d().direct_space_state
	var from := entry + travel * BallisticsConfig.exit_probe_distance
	var skip := _exclude.duplicate()
	skip.erase(rid)
	for _i in 4:
		var query := PhysicsRayQueryParameters2D.create(from, entry, collision_mask)
		query.hit_from_inside = true
		query.exclude = skip
		var found := space.intersect_ray(query)
		if found.is_empty():
			return
		if found.rid == rid:
			info.has_exit = true
			info.exit_position = found.position
			info.exit_normal = found.normal
			return
		skip.append(found.rid)


## Hand the hit to the object (if hittable), re-emit `hit`, and post a world `&"hit"` event so
## decoupled listeners (the AI's combat awareness) learn that something was struck, where, and by
## whom (`attacker` = the shooter, or null). The event also says how the round met the surface: `outcome`
## (&"ricochet" / &"blocked" / &"penetrate"), the struck `material` ("" for a wall), the surface `normal`, the
## `speed_factor` it hit at and the firing `gun` and its penetration `power`.
func _deal(body: Node, info: HitInfo, outcome: StringName, surface: Dictionary) -> void:
	if body.has_method("take_hit"):
		body.take_hit(info)
	hit.emit(body, info.damage)
	EventBus.post(&"hit", {
		"position": info.position, "victim": body, "source": info.source,
		"direction": info.direction, "damage": info.damage,
		"attacker": ignore if is_instance_valid(ignore) else null,
		"outcome": outcome, "material": String(surface.get("material", "")), "normal": info.normal,
		"speed_factor": info.speed_factor, "gun": gun, "power": penetration_power,
	})
