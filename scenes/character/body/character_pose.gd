extends RefCounted

## Character POSE (Character domain, animate layer): the living motion layered over the aim. The
## head, each hand, a held weapon and the shoulders each chase `facing` on their own damped spring
## — the head first, a steady (aiming or supporting) hand next, the weapon a touch behind it, free
## hands each at a slightly different pace, the shoulders last — so a turn ripples through the body.
## The hips are planted while standing and turn to the walking direction while walking, so the feet
## stay put under a twisting upper body and step the way the body travels. Walking sways the
## shoulders and swings the free hands along a stride; the head leans into the movement and settles
## when it stops; standing still, it breathes and glances around. A kick (recoil) throws a hand back
## and twists the shoulders; a punch twists them toward the punching side and lunges the upper body.
## Each hand eases between the stances its item asks for (CharacterConfig.stances): where it rests,
## how high it is gripped, how its elbow bends. A stunned character (the level handed to `update`, eased) hunches (the rig
## reads `hunch()`) and staggers: shorter, uneven strides, the hips swaying over the planted foot and the head lolling
## (docs/grenades.md G13). Owned and stepped by character.gd each physics
## frame; read by the hands (their rest pose), the rig (the joints) and the visuals (each part's
## angle and offset). Visual only: aim, shots and punches stay on `facing`. Tuning: CharacterConfig.pose_*, stun_look_ease, stun_hunch_pitch and stun_stagger_*.

## A wavering hand (a stance's `waver`) also rises and falls, this many body radii per px of its wander across, this many
## seconds out of step with it.
const WAVER_RISE := 0.05
const WAVER_LAG := 0.2

var torso_angle := 0.0           ## Shoulders' facing angle (rad, as Vector2.angle()), punch twist included.
var torso_offset := Vector2.ZERO ## Upper body's lunge ahead of the hips (local px).
var hip_angle := 0.0             ## Hips' and feet's facing angle (rad).
var head_angle := 0.0            ## Head's facing angle (rad).
var hand_angles := [0.0, 0.0]    ## Per hand: the angle of the frame its rest pose is built in (rad).
var weapon_angle := 0.0          ## A held weapon's facing angle (rad): trails the aiming hand.
var head_offset := Vector2.ZERO  ## Head's shift off the body center (local px), the lunge included.
var hip_sway := Vector2.ZERO     ## The hips' sideways sway of a stunned walk (local px), for the rig's pelvis.

var _torso_core := 0.0            ## Shoulders' spring angle, before the punch twist (rad).
var _torso_vel := 0.0             ## Shoulders' spring velocity (rad/s).
var _hip_vel := 0.0               ## Hips' spring velocity (rad/s).
var _head_vel := 0.0              ## Head's spring velocity (rad/s).
var _hand_vels := [0.0, 0.0]      ## Per-hand spring velocity (rad/s).
var _weapon_vel := 0.0            ## Weapon's spring velocity (rad/s).
var _steady := [false, false]     ## Per hand: held steady (aiming or supporting), quick to the aim.
var _stance := [_stance_data(&"relaxed"), _stance_data(&"relaxed")]  ## Per hand: its stance, eased.
var _lean := Vector2.ZERO         ## Head lean (local px), on a spring.
var _lean_vel := Vector2.ZERO     ## Head lean spring velocity (px/s).
var _recoil := [0.0, 0.0]         ## Per-hand recoil (px back from the rest pose), on a spring.
var _recoil_vel := [0.0, 0.0]     ## Per-hand recoil spring velocity (px/s).
var _stride := 0.0                ## Walk cycle phase (rad; one turn per stride).
var _walk := 0.0                  ## How much the character is walking, 0..1 (smoothed speed).
var _run := 0.0                   ## How much the character is running, 0..1 (smoothed, past walking speed).
var _move_dir := Vector2.ZERO     ## Last walking direction (unit), for the head bob and the hips.
var _time := 0.0                  ## Seconds alive, for breathing and glances.
var _phase := randf() * TAU       ## Per-character offset so characters don't move in lockstep.
var _primed := false              ## False until the first update snaps every part to the aim.
var _stun := 0.0                  ## How stunned the body looks, 0..1: the stun level handed in, eased.


## Advance the pose by `delta` toward `facing`, walking at `velocity` (top speed `top_speed`);
## `stances` names each hand's stance (the held item's hand_stance()), `punch` is each hand's
## extension, 0 (resting) .. 1 (fully punched), `stun` the character's stun level (0..1; 0 while a ride poses it).
func update(delta: float, facing: Vector2, velocity: Vector2, top_speed: float, stances: Array,
		punch: Array, stun := 0.0) -> void:
	var aim := facing.angle()
	if not _primed:
		torso_angle = aim
		_torso_core = aim
		hip_angle = aim
		head_angle = aim
		hand_angles = [aim, aim]
		weapon_angle = aim
		_stance = [_stance_data(stances[0]), _stance_data(stances[1])]
		_primed = true
	for i in 2:
		_stance[i] = _eased(_stance[i], _stance_data(stances[i]), delta)
	_steady = [_stance[0]["steady"], _stance[1]["steady"]]
	_time += delta
	_stun = lerpf(_stun, stun, 1.0 - exp(-CharacterConfig.stun_look_ease * delta))
	var speed := velocity.length()
	_walk = lerpf(_walk, clampf(speed / maxf(top_speed, 1.0), 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	# Past walking speed is running: how far toward a full run, smoothed like the walk.
	var run_span := maxf(CharacterConfig.run_speed_mult - 1.0, 0.01)
	_run = lerpf(_run, clampf((speed / maxf(top_speed, 1.0) - 1.0) / run_span, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	var stride_length := lerpf(CharacterConfig.pose_stride_length, CharacterConfig.pose_run_stride_length, _run) \
		* lerpf(1.0, CharacterConfig.stun_stagger_stride, _stun)
	# A stunned walk staggers: one step comes longer than the next (a limp) and the pace of the steps wanders.
	var cadence := 1.0 + _stun * (CharacterConfig.stun_stagger_limp * cos(_stride)
		+ CharacterConfig.stun_stagger_wander * sin(_time * 1.3 + _phase))
	_stride = fmod(_stride + speed * delta / maxf(stride_length, 1.0) * TAU * cadence, TAU)
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
		if _steady[i]:
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
	var torso := _turn(_torso_core, _torso_vel, aim, sway, CharacterConfig.pose_torso_freq,
		CharacterConfig.pose_torso_damping, CharacterConfig.pose_torso_max_lag, delta)
	_torso_core = torso.x
	_torso_vel = torso.y
	# A punch drives the shoulder on its side forward and the body in behind it, as the fist goes.
	var punching := maxf(punch[0], punch[1])
	# A runner's shoulders rock against the legs: the one on the forward-swinging arm's side comes
	# forward. Added over the spring, which is far too slow to follow a stride.
	var run_twist := -sin(_stride) * CharacterConfig.pose_run_sway * _run
	torso_angle = wrapf(_torso_core + (punch[1] - punch[0]) * CharacterConfig.pose_punch_twist + run_twist, -PI, PI)
	# A runner leans into the run: the shoulders lead the hips along the way it travels.
	torso_offset = facing * (punching * CharacterConfig.pose_punch_lunge) \
		+ _move_dir * (CharacterConfig.pose_run_lean * _run)
	_step_hips(delta, aim)

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
	# A stunned walk sways the hips over the planted foot (foot 0, the right, is planted while cos > 0) and lolls the head
	# a quarter of a stride behind.
	var across := Vector2.from_angle(hip_angle).orthogonal()
	var stagger := _stun * _walk
	hip_sway = across * (-cos(_stride) * CharacterConfig.stun_stagger_sway * stagger)
	head_offset = _lean + facing * breath + _move_dir * bob + torso_offset \
		+ across * (sin(_stride) * CharacterConfig.stun_stagger_bob * stagger)
	# The upper body shifts over the planted foot each step (foot 0 is planted while cos > 0); the head
	# is set before this, so it stays steady over the rocking shoulders.
	torso_offset += Vector2.from_angle(hip_angle).orthogonal() * (-cos(_stride) \
		* CharacterConfig.pose_run_shoulder_shift * _run)


## The hips plant while standing and turn to the way the character walks (a backward step stays
## facing the aim); the shoulders may twist only so far off them before the feet re-plant.
func _step_hips(delta: float, aim: float) -> void:
	var target := hip_angle
	if _walk > 0.15:
		target = _move_dir.angle()
		if absf(angle_difference(aim, target)) > PI * 0.5:
			target += PI  # Walking backward: the feet still face the aim.
	var hips := _turn(hip_angle, _hip_vel, target, 0.0, CharacterConfig.pose_hip_freq,
		CharacterConfig.pose_hip_damping, PI, delta)
	var planted := _reel(hips.x, hips.y, aim, CharacterConfig.pose_hip_twist, delta)
	hip_angle = planted.x
	_hip_vel = planted.y


## A hand's shift off its rest pose (local px), in its own frame: a free hand swings fore and aft
## with the walk (opposite to the other) as far as its stance allows, a steady hand only drifts a
## little sideways and wanders by its stance's `waver`; both minus any recoil.
func hand_offset(hand: int) -> Vector2:
	var along := Vector2.from_angle(hand_angles[hand])
	var step := sin(_stride + (0.0 if hand == 0 else PI)) * _walk
	if _steady[hand]:
		return along.orthogonal() * (step * CharacterConfig.pose_aim_drift + _waver(hand, 0.0)) - along * _recoil[hand]
	return along * (step * float(_stance[hand]["swing"]) - _recoil[hand])


## A steady hand's slow wander (px; across its frame, and at `offset` out of step, up and down): its stance's `waver`, two
## out-of-step sines.
func _waver(hand: int, offset: float) -> float:
	var w: float = _stance[hand].get("waver", 0.0)
	if w <= 0.0:
		return 0.0
	var t := _time + hand * 1.7 + offset
	return w * (0.6 * sin(t * 7.3 + _phase) + 0.4 * sin(t * 11.9 + _phase * 1.7))


## How far ahead of the body center a hand rests (px), along its frame.
func rest_forward(hand: int) -> float:
	return _stance[hand]["forward"]


## How far out to its own side a hand rests (px).
func rest_lateral(hand: int) -> float:
	return _stance[hand]["lateral"]


## How high a hand is gripped (body radii off the floor): the arm bends to reach it.
func grip_height(hand: int) -> float:
	# Running pumps the arms: the hand swinging forward rises toward the chest, the back one drops to the hip.
	var step := sin(_stride + (0.0 if hand == 0 else PI))
	return _stance[hand]["height"] + step * CharacterConfig.pose_run_hand_rise * _run + _waver(hand, WAVER_LAG) * WAVER_RISE


## Where a hand's elbow bends toward (out, forward, up).
func elbow_pole(hand: int) -> Vector3:
	# Running keeps the elbow tucked in by the body: it drops under the line to a hand swung forward and rides
	# up behind a hand swung back (the bend only ever sits in the plane through the shoulder, the hand and
	# this pole, so a fixed pole would throw the elbow out sideways at one end of the swing).
	var pole: Vector3 = _stance[hand]["elbow_pole"]
	pole.z -= sin(_stride + (0.0 if hand == 0 else PI)) * CharacterConfig.pose_run_elbow_lift * _run
	return pole


## The walk cycle's phase (rad; one turn per stride).
func stride_phase() -> float:
	return _stride


## How much the character is walking, 0..1.
func walk_amount() -> float:
	return _walk


## How much the character is running, 0 (walking or still) .. 1 (full run).
func run_amount() -> float:
	return _run


## How stunned the body looks, 0..1: the stun level, eased (CharacterConfig.stun_look_ease); the stagger scales by it.
func stun_amount() -> float:
	return _stun


## How far the stun bends the spine forward (rad): CharacterConfig.stun_hunch_pitch at the full level, eased.
func hunch() -> float:
	return deg_to_rad(CharacterConfig.stun_hunch_pitch) * _stun


## Recoil: throw `hand` (0 = right as drawn, 1 = left) back and twist the shoulders back on its side, `strength`
## times a pistol's kick. The other hand feels its share if it is steadying the weapon.
func kick(hand: int, strength := 1.0) -> void:
	_recoil_vel[hand] += CharacterConfig.pose_recoil * CharacterConfig.pose_recoil_freq * strength
	var other := 1 - hand
	_recoil_vel[other] += CharacterConfig.pose_recoil * CharacterConfig.pose_recoil_freq * strength \
		* float(_stance[other]["recoil_share"])
	var side := -1.0 if hand == 0 else 1.0
	_torso_vel -= side * CharacterConfig.pose_recoil_twist * CharacterConfig.pose_torso_freq * strength


## A stance's configured values by name (an unknown name is a relaxed hand).
static func _stance_data(name: StringName) -> Dictionary:
	return CharacterConfig.stances.get(name, CharacterConfig.stances[&"relaxed"])


## `now` eased toward the stance `to` (its numbers and elbow pole; `steady` switches at once).
static func _eased(now: Dictionary, to: Dictionary, delta: float) -> Dictionary:
	var k := 1.0 - exp(-CharacterConfig.stance_ease * delta)
	var out := to.duplicate()
	for key in ["forward", "lateral", "height", "swing", "recoil_share"]:
		out[key] = lerpf(now[key], to[key], k)
	out["waver"] = lerpf(now.get("waver", 0.0), to.get("waver", 0.0), k)
	out["elbow_pole"] = (now["elbow_pole"] as Vector3).lerp(to["elbow_pole"], k)
	return out


## One step of a part's angle chasing `aim + offset` on a damped spring, reeled back in when it
## trails the aim by more than `max_lag` (see `_reel`). Returns (angle, velocity).
static func _turn(angle: float, vel: float, aim: float, offset: float, freq: float, damping: float,
		max_lag: float, delta: float) -> Vector2:
	vel = _accel(vel, angle_difference(angle, aim + offset), freq, damping, delta)
	angle += vel * delta
	return _reel(angle, vel, aim, max_lag, delta)


## `angle` past `max_lag` behind `aim` is reeled back in quickly (CharacterConfig.pose_lag_catch)
## rather than snapped, so a sudden flick drags it along smoothly instead of leaving it behind.
## Returns (angle, velocity).
static func _reel(angle: float, vel: float, aim: float, max_lag: float, delta: float) -> Vector2:
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
