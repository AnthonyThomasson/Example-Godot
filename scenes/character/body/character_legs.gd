extends RefCounted

## Character LEGS (Character domain, animate layer): the legs' contact with the world. The rig strides, folds
## and trails the feet wherever the pose puts them, which can be well past the body's collision circle (a
## stride's toes, a crouch's leading knees), so this layer, stepped by
## character.gd each physics frame after the pose, finds where each leg would stop and keeps the drawn leg there:
## - each ankle is swept from the body centre toward where the rig would put it (a foot-sized circle, like the
##   hands layer's `_resolve_hand`) and rests at the first wall or solid piece it meets, sliding the leftover
##   along the surface; the rig reads it back through `character.foot_clamp(i)`;
## - the knee is judged the same way from the leg the ankle leaves: a knee that would pass through something
##   moves the foot back by what it overshot (a crouch facing a wall keeps its knees off it), up to `KNEE_TRIES`;
## - a foot or knee swinging into a light, pushable piece shoves it, scaled by how fast the foot is moving into
##   it and how far it wanted to go, and capped so the piece is never driven faster than the character walks (the
##   same rule as the body's own push). A fixed wall only stops the leg, and a foot at rest pushes nothing.
## Other characters are solid to a leg (it rests against them) but are never shoved by it. Nothing is cast while
## nothing is near. Tuning: CharacterConfig.leg_*.

const Rig = preload("res://scenes/character/body/character_rig.gd")

## Physics layer a leg meets: walls, solid furniture and living characters (the hands' mask).
const MASK := PhysicsLayers.SOLID
## Nothing is cast unless something solid lies within this many px of the body centre (a leg reaches ~55).
const NEAR := 72.0
## How many times a knee that would pass through something may move its foot back.
const KNEE_TRIES := 3
## A foot this far (px) short of where it wanted to go is resting against something.
const REST_EPS := 0.5
## Px a foot must have wanted to go past the obstacle for its shove to be at full strength.
const FULL_PRESS := 6.0

## Per side: where the ankle rests (local x/y px), or null when nothing stops it.
var _ankle: Array = [null, null]
## Per side, ankle then knee: where each was wanted last frame (local px), for its speed.
var _prev: Array = [null, null, null, null]


## Where side `i`'s ankle rests (local x/y), or null when nothing is in its way.
func ankle(i: int) -> Variant:
	return _ankle[i]


## Forget every contact (the character is locked in an interaction, or has died).
func clear() -> void:
	_ankle = [null, null]
	_prev = [null, null, null, null]


## Rest both legs of `character` against what is near and shove what a foot swings into.
func update(character, delta: float) -> void:
	var space: PhysicsDirectSpaceState2D = character.get_world_2d().direct_space_state
	if not _anything_near(space, character):
		clear()
		return
	var rig := Rig.new(character, false)
	for i in 2:
		_ankle[i] = _rest_leg(space, character, rig, i, delta)


## Whether anything solid is within `NEAR` px of the body centre.
func _anything_near(space: PhysicsDirectSpaceState2D, character) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = NEAR
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.collision_mask = MASK
	params.exclude = [character.get_rid()]
	params.transform = Transform2D(0.0, character.global_position)
	return not space.intersect_shape(params, 1).is_empty()


## Side `i`'s resting ankle (local x/y), or null when neither it nor the knee meets anything.
func _rest_leg(space: PhysicsDirectSpaceState2D, character, rig, i: int, delta: float) -> Variant:
	var hip: Vector3 = rig.point(Rig.HIP[i])
	var wanted: Vector3 = rig.point(Rig.ANKLE[i])
	var ankle := Vector2(wanted.x, wanted.y)
	var rested := _sweep(space, character, ankle)
	var knee_wanted := Vector2.ZERO
	var knee_rested := Vector2.ZERO
	for _try in KNEE_TRIES:
		var knee3: Vector3 = rig.knee_at(i, Vector3(rested.x, rested.y, wanted.z))
		knee_wanted = Vector2(knee3.x, knee3.y)
		knee_rested = _sweep(space, character, knee_wanted)
		var overshoot := knee_rested - knee_wanted
		if overshoot.length() <= REST_EPS:
			break
		# The knee would pass through something: step the foot back by how far it overshot, then rest it again.
		rested = _sweep(space, character, rested + overshoot)
	_press(space, character, 2 + i, knee_wanted, knee_rested, delta)
	_press(space, character, i, ankle, rested, delta)
	if rested.distance_to(ankle) <= REST_EPS and knee_rested.distance_to(knee_wanted) <= REST_EPS:
		return null
	return rested


## The place `target` (local px) can be reached from the body centre by a foot-sized circle: `target` itself when
## the way is clear, else where it first touches a wall or solid piece, slid along the surface for what is left.
func _sweep(space: PhysicsDirectSpaceState2D, character, target: Vector2) -> Vector2:
	var centre: Vector2 = character.global_position
	var motion := target
	if motion.length_squared() < 0.0001:
		return target
	var circle := CircleShape2D.new()
	circle.radius = CharacterConfig.leg_radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.collision_mask = MASK
	params.exclude = [character.get_rid()]
	params.transform = Transform2D(0.0, centre)
	params.motion = motion
	var safe: float = space.cast_motion(params)[0]
	if safe >= 1.0:
		return target
	var rest := motion * safe
	var ray := PhysicsRayQueryParameters2D.create(centre, centre + motion, MASK)
	ray.exclude = [character.get_rid()]
	var hit := space.intersect_ray(ray)
	var normal: Vector2 = hit.normal if not hit.is_empty() and hit.normal.length() > 0.001 else -motion.normalized()
	var slide := (motion * (1.0 - safe)).slide(normal)
	params.transform = Transform2D(0.0, centre + rest)
	params.motion = slide
	return rest + slide * float(space.cast_motion(params)[0])


## Shove the light piece (if any) that a point wanted at `wanted` but rested at `rested` (local px) is pressing
## into. `slot` indexes `_prev`: how fast the point is moving, in the world, into the piece sets the strength.
func _press(space: PhysicsDirectSpaceState2D, character, slot: int, wanted: Vector2, rested: Vector2,
		delta: float) -> void:
	var previous = _prev[slot]
	_prev[slot] = wanted
	var into := wanted - rested
	var depth := into.length()
	if previous == null or depth <= REST_EPS or delta <= 0.0:
		return
	var dir := into / depth
	var velocity: Vector2 = (wanted - (previous as Vector2)) / delta + character.get_real_velocity()
	var approach := velocity.dot(dir)
	if approach <= 0.0:
		return
	var piece := _pushable_at(space, character, character.global_position + rested)
	if piece == null:
		return
	var strength := clampf(approach / maxf(float(character.speed), 1.0), 0.0, 1.0) * clampf(depth / FULL_PRESS, 0.0, 1.0)
	var impulse := CharacterConfig.leg_push_impulse * strength * delta
	# Carry the piece along rather than launch it: never drive it faster than the character walks.
	if "linear_velocity" in piece:
		var gap := maxf(float(character.speed) * CharacterConfig.push_carry_factor - piece.linear_velocity.dot(dir), 0.0)
		impulse = minf(impulse, gap * piece.get_mass())
	piece.apply_impulse(dir * impulse)


## The light, pushable piece touching a foot-sized circle at world point `at`, or null: a body that takes an
## impulse and has a mass, and is not another character.
func _pushable_at(space: PhysicsDirectSpaceState2D, character, at: Vector2) -> Node:
	var circle := CircleShape2D.new()
	circle.radius = CharacterConfig.leg_radius + 1.5
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.collision_mask = MASK
	params.exclude = [character.get_rid()]
	params.transform = Transform2D(0.0, at)
	for result in space.intersect_shape(params, 4):
		var body: Object = result.collider
		if body is CharacterBody2D:
			continue
		if body.has_method("apply_impulse") and body.has_method("get_mass"):
			return body
	return null
