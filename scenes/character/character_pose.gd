extends RefCounted

## Character POSE (Character domain, animate layer): the living motion layered over the aim. The
## head, each hand, a held weapon and the shoulders each chase `facing` on their own damped spring
## — the head first, an aiming hand next, the weapon a touch behind it, free hands each at a
## slightly different pace, the shoulders last — so a turn ripples through the body. Walking sways
## the shoulders and swings the free hands along a stride (an aiming hand stays steady, drifting
## only a little sideways); the head leans into the movement and settles when it stops; standing
## still, it breathes and glances around. A kick (recoil) throws a hand back and twists the
## shoulders. Owned and stepped by character.gd each
## physics frame; read by the hands (their rest pose) and the visuals (each part's angle and
## offset). Visual only: aim, shots and punches stay on `facing`. Tuning: CharacterConfig.pose_*.

var torso_angle := 0.0           ## Shoulders' facing angle (rad, as Vector2.angle()).
var head_angle := 0.0            ## Head's facing angle (rad).
var hand_angles := [0.0, 0.0]    ## Per hand: the angle of the frame its rest pose is built in (rad).
var weapon_angle := 0.0          ## A held weapon's facing angle (rad): trails the aiming hand.
var head_offset := Vector2.ZERO  ## Head's shift off the body center (local px).

var _torso_vel := 0.0             ## Shoulders' spring velocity (rad/s).
var _head_vel := 0.0              ## Head's spring velocity (rad/s).
var _hand_vels := [0.0, 0.0]      ## Per-hand spring velocity (rad/s).
var _weapon_vel := 0.0            ## Weapon's spring velocity (rad/s).
var _aiming := [false, false]     ## Per hand: holding an aimed weapon (steady, quicker to the aim).
var _lean := Vector2.ZERO         ## Head lean (local px), on a spring.
var _lean_vel := Vector2.ZERO     ## Head lean spring velocity (px/s).
var _recoil := [0.0, 0.0]         ## Per-hand recoil (px back from the rest pose), on a spring.
var _recoil_vel := [0.0, 0.0]     ## Per-hand recoil spring velocity (px/s).
var _stride := 0.0                ## Walk cycle phase (rad; one turn per stride).
var _walk := 0.0                  ## How much the character is walking, 0..1 (smoothed speed).
var _move_dir := Vector2.ZERO     ## Last walking direction (unit), for the head bob.
var _time := 0.0                  ## Seconds alive, for breathing and glances.
var _phase := randf() * TAU       ## Per-character offset so characters don't move in lockstep.
var _primed := false              ## False until the first update snaps every part to the aim.


## Advance the pose by `delta` toward `facing`, walking at `velocity` (top speed `top_speed`);
## `aiming` lists the hands holding an aimed weapon (the held item's aiming_hands()).
func update(delta: float, facing: Vector2, velocity: Vector2, top_speed: float, aiming: Array = []) -> void:
	var aim := facing.angle()
	if not _primed:
		torso_angle = aim
		head_angle = aim
		hand_angles = [aim, aim]
		weapon_angle = aim
		_primed = true
	_aiming = [aiming.has(0), aiming.has(1)]
	_time += delta
	var speed := velocity.length()
	_walk = lerpf(_walk, clampf(speed / maxf(top_speed, 1.0), 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	_stride = fmod(_stride + speed * delta / maxf(CharacterConfig.pose_stride_length, 1.0) * TAU, TAU)
	if speed > 1.0:
		_move_dir = velocity / speed

	var glance := (sin(_time * 0.5 + _phase) * 0.6 + sin(_time * 0.21 + _phase * 2.3) * 0.4) \
		* CharacterConfig.pose_glance * (1.0 - _walk)
	var sway := sin(_stride) * CharacterConfig.pose_walk_sway * _walk

	var head := _turn(head_angle, _head_vel, aim, glance, CharacterConfig.pose_head_freq,
		CharacterConfig.pose_head_damping, CharacterConfig.pose_head_max_lag, delta)
	head_angle = head.x
	_head_vel = head.y
	for i in 2:
		var hand: Vector2
		if _aiming[i]:
			hand = _turn(hand_angles[i], _hand_vels[i], aim, 0.0, CharacterConfig.pose_aim_freq,
				CharacterConfig.pose_aim_damping, CharacterConfig.pose_aim_max_lag, delta)
		else:
			# Each free hand at its own pace, so the pair doesn't turn as one rigid piece.
			var pace := 1.0 + CharacterConfig.pose_hand_pace_spread * (-0.5 if i == 0 else 0.5)
			hand = _turn(hand_angles[i], _hand_vels[i], aim, 0.0, CharacterConfig.pose_hand_freq * pace,
				CharacterConfig.pose_hand_damping, CharacterConfig.pose_hand_max_lag, delta)
		hand_angles[i] = hand.x
		_hand_vels[i] = hand.y
	var weapon := _turn(weapon_angle, _weapon_vel, aim, 0.0, CharacterConfig.pose_weapon_freq,
		CharacterConfig.pose_weapon_damping, CharacterConfig.pose_weapon_max_lag, delta)
	weapon_angle = weapon.x
	_weapon_vel = weapon.y
	var torso := _turn(torso_angle, _torso_vel, aim, sway, CharacterConfig.pose_torso_freq,
		CharacterConfig.pose_torso_damping, CharacterConfig.pose_torso_max_lag, delta)
	torso_angle = torso.x
	_torso_vel = torso.y

	for i in 2:
		_recoil_vel[i] = _accel(_recoil_vel[i], -_recoil[i], CharacterConfig.pose_recoil_freq,
			CharacterConfig.pose_recoil_damping, delta)
		_recoil[i] += _recoil_vel[i] * delta

	var lean_target := velocity / maxf(top_speed, 1.0) * CharacterConfig.pose_lean
	_lean_vel = Vector2(
		_accel(_lean_vel.x, lean_target.x - _lean.x, CharacterConfig.pose_lean_freq, CharacterConfig.pose_lean_damping, delta),
		_accel(_lean_vel.y, lean_target.y - _lean.y, CharacterConfig.pose_lean_freq, CharacterConfig.pose_lean_damping, delta))
	_lean += _lean_vel * delta
	var breath := sin(_time * TAU / maxf(CharacterConfig.pose_breath_period, 0.1) + _phase) \
		* CharacterConfig.pose_breath * (1.0 - _walk)
	var bob := cos(_stride * 2.0) * CharacterConfig.pose_head_bob * _walk  # A bob per step.
	head_offset = _lean + facing * breath + _move_dir * bob


## A hand's shift off its rest pose (local px), in its own frame: a free hand swings fore and aft
## with the walk (opposite to the other), an aiming hand only drifts a little sideways; both minus
## any recoil.
func hand_offset(hand: int) -> Vector2:
	var along := Vector2.from_angle(hand_angles[hand])
	var step := sin(_stride + (0.0 if hand == 0 else PI)) * _walk
	if _aiming[hand]:
		return along.orthogonal() * step * CharacterConfig.pose_aim_drift - along * _recoil[hand]
	return along * (step * CharacterConfig.pose_hand_swing - _recoil[hand])


## Recoil: throw `hand` (0 = left, 1 = right) back and twist the shoulders back on its side.
func kick(hand: int) -> void:
	_recoil_vel[hand] += CharacterConfig.pose_recoil * CharacterConfig.pose_recoil_freq
	var side := -1.0 if hand == 0 else 1.0
	_torso_vel -= side * CharacterConfig.pose_recoil_twist * CharacterConfig.pose_torso_freq


## One step of a part's angle chasing `aim + offset` on a damped spring. Past `max_lag` behind the
## aim it is reeled back in quickly (CharacterConfig.pose_lag_catch) rather than snapped, so a
## sudden flick drags it along smoothly instead of leaving it behind. Returns (angle, velocity).
static func _turn(angle: float, vel: float, aim: float, offset: float, freq: float, damping: float,
		max_lag: float, delta: float) -> Vector2:
	vel = _accel(vel, angle_difference(angle, aim + offset), freq, damping, delta)
	angle += vel * delta
	var lag := angle_difference(aim, angle)
	if absf(lag) > max_lag:
		var excess := lag - signf(lag) * max_lag
		angle -= excess * (1.0 - exp(-CharacterConfig.pose_lag_catch * delta))
		if signf(vel) == signf(lag):
			vel = 0.0  # Moving further away from the aim: stop it there.
	return Vector2(wrapf(angle, -PI, PI), vel)


## A damped spring's velocity after `delta`, pulled to close `error` (target − value): `freq` is
## its natural frequency (rad/s), `damping` its ratio (1 = no overshoot).
static func _accel(vel: float, error: float, freq: float, damping: float, delta: float) -> float:
	return vel + (freq * freq * error - 2.0 * damping * freq * vel) * delta
