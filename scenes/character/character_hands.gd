extends Node2D

## Character HANDS layer. Owns the hand geometry (collision-resolved so hands rest on
## walls/objects), the punch animation (a tween per swing) and the punch hit detection
## (a shape query at the fist's raw punch position). The character sets `facing` and calls
## `punch(hand)`; visuals read `hand_position()` / `hand_radius`. WHICH hand punches and WHEN
## is decided by the held Item + the controller — this layer only animates and detects the
## swing it is told to.

## Hand geometry (all in pixels, in the character's local space).
@export var hand_radius: float = 6.0      ## Size of each hand circle.
@export var hand_gap: float = 3.5         ## Gap between the body edge and a resting hand.
@export var hand_lateral: float = 8.0     ## How far each hand sits to its side of center.

## Emitted when the extended fist overlaps a body. `hand_index` is 0 (left) or 1 (right);
## `damage` is the range-of-motion-scaled punch damage dealt (0 at point-blank, up at full reach).
signal punched(hand_index: int, body: Node, damage: float)

## Facing unit vector, set by the character each frame.
var facing := Vector2.RIGHT
## Per-hand extension, 0 (resting) .. 1 (fully punched), driven by tweens.
var _punch := [0.0, 0.0]
## Per-hand extension from the previous physics frame, for the swing-speed estimate.
var _prev_punch := [0.0, 0.0]
## Per-hand extension speed (units/s), recomputed each physics frame. Its magnitude, scaled
## to 0..1 by PUNCH_EXTEND_TIME, is the swing's "range of motion" — how hard the fist is moving.
var _punch_speed := [0.0, 0.0]
## Current punch reach (from the held item's reach), updated in _physics_process.
var _current_reach := 28.0
## Per-hand collision-resolved local positions, recomputed each physics frame so the hands
## rest against walls/objects instead of clipping through. Read via hand_position().
var _hand_pos := [Vector2.ZERO, Vector2.ZERO]

## Physics layers the hands collide with (walls + solid furniture default to layer 1).
const HAND_MASK := 1

## Punch tween durations (s): the fist extends, then retracts. The extend time also
## normalizes the swing-speed factor, so a full-speed extend counts as a full-power hit.
const PUNCH_EXTEND_TIME := 0.07
const PUNCH_RETRACT_TIME := 0.11

## Hit-detection state for the current swing.
var _fist_shape: CircleShape2D  ## Query shape for punch detection (fist radius).
var _attack_active := false   ## True for the whole swing (extend + retract); gates hit polling.
var _active_hand := 0         ## Hand the fist is tracking this swing.
var _hit_bodies := {}         ## Bodies already reported this swing (dedup).

@onready var _character := get_parent()  ## Character (CharacterBody2D) — body radius + held item.


func _ready() -> void:
	# Build the fist query shape (punch detection is a shape query at the raw punch position).
	_fist_shape = CircleShape2D.new()
	_fist_shape.radius = hand_radius

	# Seed the resolved-hand cache so the first drawn frame isn't at the body center.
	for hand in [0, 1]:
		_hand_pos[hand] = _raw_hand_position(hand)


func _physics_process(delta: float) -> void:
	# Track the current reach from the held item.
	var item: Item = _character.current_item()
	if item:
		_current_reach = item.reach

	# Estimate each hand's extension speed (units/s) for the range-of-motion punch factor,
	# then resolve each hand against walls/objects so it rests on the surface, not clipping.
	for hand in [0, 1]:
		_punch_speed[hand] = (_punch[hand] - _prev_punch[hand]) / delta if delta > 0.0 else 0.0
		_prev_punch[hand] = _punch[hand]
		_hand_pos[hand] = _resolve_hand(hand)

	# Report anything the punching fist reaches this frame.
	if _attack_active:
		_report_hits()


## True while a swing is in progress (extend + retract).
func is_attacking() -> bool:
	return _attack_active


## Local-space center of a hand (0 = left, 1 = right): the collision-resolved position.
func hand_position(hand: int) -> Vector2:
	return _hand_pos[hand]


## The hand's ideal local position from facing/lateral offset + punch extension, before
## any wall/object collision is applied.
func _raw_hand_position(hand: int) -> Vector2:
	var body_radius: float = _character.radius
	var perp := facing.orthogonal()
	var side := -1.0 if hand == 0 else 1.0
	var rest := facing * (body_radius + hand_radius + hand_gap) + perp * (hand_lateral * side)
	return rest + facing * (_current_reach * _punch[hand])


## Collide-and-slide the hand from the body center toward its raw target: stop at the first
## wall/solid object, then slide the leftover motion along the surface. Returns a local offset.
func _resolve_hand(hand: int) -> Vector2:
	var center: Vector2 = _character.global_position
	var raw_world := center + _raw_hand_position(hand)
	var motion := raw_world - center
	if motion.length_squared() < 0.0001:
		return _raw_hand_position(hand)

	var space := get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = hand_radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.collision_mask = HAND_MASK
	params.exclude = [_character.get_rid()]
	params.transform = Transform2D(0.0, center)
	params.motion = motion

	var res := space.cast_motion(params)  # [safe, unsafe] fractions of motion.
	var safe: float = res[0]
	if safe >= 1.0:
		return motion  # Clear path — full extension.

	# Pushed back toward the body: rest where the hand first touches the surface.
	var rest := center + motion * safe

	# Surface normal from a ray along the approach (mirrors projectile._sweep).
	var ray := PhysicsRayQueryParameters2D.create(center, raw_world, HAND_MASK)
	ray.exclude = [_character.get_rid()]
	var hit := space.intersect_ray(ray)
	var normal: Vector2 = hit.normal if hit and hit.normal.length() > 0.001 else (center - raw_world).normalized()

	# Slide the leftover motion along the surface — the "to the side a bit".
	var slide := (motion * (1.0 - safe)).slide(normal)
	params.transform = Transform2D(0.0, rest)
	params.motion = slide
	var res2 := space.cast_motion(params)
	return (rest + slide * res2[0]) - center


## Throw the given hand forward, then retract it. The Item decides which hand and gates it.
func punch(hand: int) -> void:
	if _punch[hand] > 0.0:
		return  # That hand is still mid-swing; skip.

	_active_hand = hand
	_attack_active = true
	_hit_bodies.clear()

	# Run on the physics step so _punch / _attack_active stay in sync with the
	# _report_hits() poll in _physics_process.
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(_set_punch.bind(hand), 0.0, 1.0, PUNCH_EXTEND_TIME)   # Extend.
	tween.tween_method(_set_punch.bind(hand), 1.0, 0.0, PUNCH_RETRACT_TIME)  # Retract.
	# Stay active across the whole swing: the fist reaches full extension a physics frame
	# after get_overlapping_bodies() would see it, so a window closing at the apex would
	# miss the hit. Per-swing dedup keeps it to one report.
	tween.tween_callback(func() -> void: _attack_active = false)


## Tween setter for a single hand's extension.
func _set_punch(value: float, hand: int) -> void:
	_punch[hand] = value


## Push and report every body the fist reaches this frame (once each per swing), ignoring self.
## Detection is a shape query at the fist's RAW (unclamped) punch position, which extends into
## whatever is being hit — the drawn hand still rests on the surface via _resolve_hand. The
## shove and damage scale with the swing's range of motion (how fast the fist is moving). A
## punch pushes (via the pushable contract) but never deforms; walls have no `apply_impulse`,
## so they take damage without moving.
func _report_hits() -> void:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _fist_shape
	params.collision_mask = HAND_MASK
	params.exclude = [_character.get_rid()]
	params.transform = Transform2D(0.0, _character.global_position + _raw_hand_position(_active_hand))

	# Range of motion: how fast the fist is swinging this frame (1.0 = full-speed extend).
	var motion := clampf(absf(_punch_speed[_active_hand]) * PUNCH_EXTEND_TIME, 0.0, 1.0)
	for result in get_world_2d().direct_space_state.intersect_shape(params, 8):
		var body: Node = result.collider
		if body == _character or _hit_bodies.has(body):
			continue
		_hit_bodies[body] = true
		var impulse := facing * CharacterConfig.punch_impulse * motion
		var pushed := body.has_method("apply_impulse")
		if pushed:
			body.apply_impulse(impulse)
		var damage := CharacterConfig.punch_damage * motion
		print("Punch (hand %d) hit %s for %.1f damage, push %.0f (%s, %.0f%% swing)" % [
			_active_hand, body.name, damage, impulse.length(),
			"pushable" if pushed else "fixed", motion * 100.0])
		punched.emit(_active_hand, body, damage)
		if body.has_method("take_damage"):
			body.take_damage(damage)
