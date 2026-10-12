extends RefCounted

## Character RIG (Character domain, animate layer): the standing skeleton as 3D joints (local x/y
## over the floor plus height z), solved fresh from the live pose and the hands. Both the standing
## body's limbs (character_visuals.gd) and the ragdoll's starting pose (character_ragdoll.gd) are
## drawn from it, so a body falls from exactly the pose it was standing in.
## - The upper body (chest, head, shoulders) sits at the pose's torso frame and lunge; the hips and
##   feet at its hip frame, which stays planted while the shoulders twist over it.
## - Each arm is two-bone IK from its shoulder to where the hands layer holds the fist, at the
##   grip height of its stance, the elbow bent toward the stance's pole. A hand out of reach pulls
##   its shoulder after it (a punch's lean-in), up to CharacterConfig.body_shoulder_reach.
## - Each foot strides fore and aft, opposite to the arm on its side, lifting as it swings through;
##   the knee is IK bent forward.
## - A crouch lowers the hips to the character's eased posture height and pitches the spine forward about the
##   pelvis (the neck pitching on, so the head sits ahead of and above the shoulders); the hips and feet come
##   together, the feet standing a little ahead of the pelvis so the knees lead.
## - Each ankle rests where the legs layer (character_legs.gd) stopped it against a wall or piece of furniture.
## Joints are read by index (the constants below, shared with the ragdoll) through `point(i)`, and
## each foot's direction through `toes(i)`. Index pairs are per hand side (0 = left, 1 = right). A rig also
## answers `torso()` and `face()`, so a crouched body is drawn like a fallen one.
## Tuning: CharacterConfig.body_*, CharacterConfig.stances, CharacterConfig.postures.

const HEAD := 0
const CHEST := 1
const PELVIS := 2
const BELLY := 3
const SHOULDER := [4, 5]
const HIP := [6, 7]
const ELBOW := [8, 9]
const HAND := [10, 11]
const KNEE := [12, 13]
const ANKLE := [14, 15]
const SPINE := 16  ## The back, opposite the belly.

var _points: Array = []                       ## Vector3 per joint index.
var _toes := [Vector3.RIGHT, Vector3.RIGHT]   ## Per side: the way the foot points (unit, flat).
var _face := Vector3.RIGHT                    ## The way the face looks (unit, flat).
var _knee_poles := [Vector3.RIGHT, Vector3.RIGHT]  ## Per side: the way the knee bends toward.
var _thigh := 0.0                             ## Bone lengths (px), for re-solving a knee.
var _shin := 0.0


## Solve the skeleton of `character` as it stands now. With `with_legs` (the default) each ankle takes the place
## the legs layer rested it at against a wall or piece of furniture (`character.foot_clamp(i)`, when it has
## one); the legs layer itself solves without, to learn where the legs would go unobstructed.
func _init(character, with_legs := true) -> void:
	var r: float = character.radius
	var pose = character.pose
	var up := Vector3(0.0, 0.0, 1.0)
	var torso := Vector2.from_angle(pose.torso_angle)
	var fwd := Vector3(torso.x, torso.y, 0.0)
	var right := Vector3(torso.orthogonal().x, torso.orthogonal().y, 0.0)  # Hand 1's side.
	var hips := Vector2.from_angle(pose.hip_angle)
	var hip_fwd := Vector3(hips.x, hips.y, 0.0)
	var hip_right := Vector3(hips.orthogonal().x, hips.orthogonal().y, 0.0)
	var lunge := Vector3(pose.torso_offset.x, pose.torso_offset.y, 0.0)
	# A lower posture scales the standing heights down and folds the body: the spine pitches forward about the
	# pelvis (the pelvis sits back and the chest forward by half the lean, so the body stays centred over its
	# feet), the neck pitches on from the shoulders, the hips and feet come together, and the feet stand ahead of
	# the pelvis so the knees lead over the toes.
	var height: float = character.posture_height()
	var crouch_height: float = CharacterConfig.postures[&"crouch"]["height"]
	var folded := clampf((1.0 - height) / maxf(1.0 - crouch_height, 0.01), 0.0, 1.0)
	var pitch := deg_to_rad(CharacterConfig.body_crouch_pitch) * folded
	var neck_pitch := pitch + deg_to_rad(CharacterConfig.body_crouch_neck_pitch) * folded
	var spine := (CharacterConfig.body_shoulder_height - CharacterConfig.body_hip_height) * r
	var neck := (CharacterConfig.body_head_height - CharacterConfig.body_shoulder_height) * r
	var lean := spine * sin(pitch)  # How far the chest sits ahead of the pelvis.
	var hip_z: float = (CharacterConfig.body_hip_height - CharacterConfig.body_run_hip_drop * pose.run_amount()) * r * height  # A run sinks.
	var chest_z := CharacterConfig.body_hip_height * r * height + spine * cos(pitch)
	var upper := CharacterConfig.body_upper_arm * r
	var fore := CharacterConfig.body_forearm * r
	var thigh := CharacterConfig.body_thigh * r
	var shin := CharacterConfig.body_shin * r
	_thigh = thigh
	_shin = shin
	var arm_reach := (upper + fore) * CharacterConfig.body_arm_extension
	var foot_z := CharacterConfig.ragdoll_limb_radius * r
	var hip_half := CharacterConfig.body_hip_width * r * lerpf(1.0, CharacterConfig.body_crouch_hip_width, folded)
	var foot_half := CharacterConfig.body_hip_width * r * lerpf(1.0, CharacterConfig.body_crouch_foot_gap, folded)
	var foot_fwd := CharacterConfig.body_crouch_foot_ahead * r * folded - lean * 0.5
	var item: Item = character.current_item()
	var weapon_hand: int = item.weapon_hand() if item != null else 1

	_points.resize(17)
	_face = Vector3(cos(pose.head_angle), sin(pose.head_angle), 0.0)
	_points[CHEST] = lunge + fwd * lean * 0.5 + up * chest_z
	_points[HEAD] = Vector3(pose.head_offset.x, pose.head_offset.y, 0.0) + fwd * (lean * 0.5 + neck * sin(neck_pitch)) \
		+ up * (chest_z + neck * cos(neck_pitch))
	_points[PELVIS] = -fwd * lean * 0.5 + up * hip_z
	var mid: Vector3 = (_points[CHEST] + _points[PELVIS]) * 0.5
	var belly := fwd * cos(pitch) - up * sin(pitch)  # Out of the chest, square to the leaning spine.
	_points[BELLY] = mid + belly * CharacterConfig.ragdoll_belly * r
	_points[SPINE] = mid - belly * CharacterConfig.ragdoll_belly * r

	for i in 2:
		var out := -1.0 if i == 0 else 1.0
		# Arm: the shoulder reaches for the fist the hands layer holds, at its stance's grip height.
		var shoulder: Vector3 = _points[CHEST] + right * out * CharacterConfig.body_shoulder_width * r
		var grip: Vector2 = character.hand_position(i)
		var hand := Vector3(grip.x, grip.y, pose.grip_height(i) * r * height)
		hand.z = clampf(hand.z, shoulder.z - arm_reach * 0.98, shoulder.z + arm_reach * 0.98)
		var flat := Vector2(hand.x - shoulder.x, hand.y - shoulder.y)
		var rise := hand.z - shoulder.z
		var flat_reach := sqrt(maxf(arm_reach * arm_reach - rise * rise, 0.0))
		if flat.length() > flat_reach:
			var follow := minf(flat.length() - flat_reach, CharacterConfig.body_shoulder_reach * r)
			shoulder += Vector3(flat.x, flat.y, 0.0).normalized() * follow
		var pole: Vector3 = pose.elbow_pole(i)
		_points[SHOULDER[i]] = shoulder
		_points[HAND[i]] = hand
		_points[ELBOW[i]] = _bend(shoulder, hand, upper, fore, right * out * pole.x + fwd * pole.y + up * pole.z)

		# Leg: the foot strides along the hips' forward, back when the arm on its side swings forward. A crouch
		# stands the feet closer together, a little ahead of the pelvis and staggered (the weapon hand's side back),
		# and takes a shorter step.
		var hip: Vector3 = _points[PELVIS] + hip_right * out * hip_half
		var phase: float = pose.stride_phase() + (0.0 if i == 0 else PI)
		var walk: float = pose.walk_amount()
		var run: float = pose.run_amount()  # A run strides wider and lifts higher.
		var stride := lerpf(CharacterConfig.body_stride, CharacterConfig.body_run_stride, run) \
			* lerpf(1.0, CharacterConfig.body_crouch_stride, folded)
		var foot_lift := lerpf(CharacterConfig.body_foot_lift, CharacterConfig.body_run_foot_lift, run)
		var step := -sin(phase) * walk * stride * r
		var lift := maxf(-cos(phase), 0.0) * walk * foot_lift * r  # Off the floor mid-swing.
		var stagger := (-0.5 if i == weapon_hand else 0.5) * CharacterConfig.body_crouch_stagger * r * folded
		var base := hip_right * out * foot_half + hip_fwd * (foot_fwd + stagger)
		var ankle := Vector3(base.x, base.y, foot_z + lift) + hip_fwd * step
		_points[HIP[i]] = hip
		_points[ANKLE[i]] = ankle
		_knee_poles[i] = hip_fwd
		_points[KNEE[i]] = _bend(hip, ankle, thigh, shin, hip_fwd)
		_toes[i] = hip_fwd

	if with_legs:
		for i in 2:
			var rested = character.foot_clamp(i)
			if rested != null:
				var ankle: Vector3 = _points[ANKLE[i]]
				ankle.x = (rested as Vector2).x
				ankle.y = (rested as Vector2).y
				_points[ANKLE[i]] = ankle
				_points[KNEE[i]] = knee_at(i, ankle)


## Where side `i`'s knee sits with its ankle at `ankle`: the middle joint of the leg's two bones, bent the way this
## pose bends it.
func knee_at(i: int, ankle: Vector3) -> Vector3:
	return _bend(_points[HIP[i]], ankle, _thigh, _shin, _knee_poles[i])


## Joint `i`'s position (local x/y px, z = height px).
func point(i: int) -> Vector3:
	return _points[i]


## Which way side `i`'s toes point (unit, flat).
func toes(i: int) -> Vector3:
	return _toes[i]


## Which way the face looks (unit, flat).
func face() -> Vector3:
	return _face


## The trunk's orientation: x toward the right shoulder, y up the spine (hips to chest), z out of the chest. A
## body face down has z pointing at the floor.
func torso() -> Basis:
	var y: Vector3 = (_points[CHEST] - _points[PELVIS]).normalized()
	var across: Vector3 = _points[SHOULDER[1]] - _points[SHOULDER[0]]
	var x := (across - y * across.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


## Where the middle joint of a two-bone chain from `a` to `b` (bone lengths `l1`, `l2`) sits, bent
## toward `pole`.
static func _bend(a: Vector3, b: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var ab := b - a
	var d := clampf(ab.length(), 0.001, l1 + l2 - 0.001)
	var along := ab.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var side := (pole - along * pole.dot(along)).normalized()
	return a + along * x + side * h
