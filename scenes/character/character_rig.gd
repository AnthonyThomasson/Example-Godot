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
## Joints are read by index (the constants below, shared with the ragdoll) through `point(i)`, and
## each foot's direction through `toes(i)`. Index pairs are per hand side (0 = left, 1 = right).
## Tuning: CharacterConfig.body_*, CharacterConfig.stances.

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


## Solve the skeleton of `character` as it stands now.
func _init(character) -> void:
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
	var hip_z: float = (CharacterConfig.body_hip_height - CharacterConfig.body_run_hip_drop * pose.run_amount()) * r  # A run sinks.
	var shoulder_z := CharacterConfig.body_shoulder_height * r
	var upper := CharacterConfig.body_upper_arm * r
	var fore := CharacterConfig.body_forearm * r
	var thigh := CharacterConfig.body_thigh * r
	var shin := CharacterConfig.body_shin * r
	var arm_reach := (upper + fore) * CharacterConfig.body_arm_extension
	var foot_z := CharacterConfig.ragdoll_limb_radius * r

	_points.resize(17)
	_points[HEAD] = Vector3(pose.head_offset.x, pose.head_offset.y, CharacterConfig.body_head_height * r)
	_points[CHEST] = lunge + up * shoulder_z
	_points[PELVIS] = up * hip_z
	var mid: Vector3 = (_points[CHEST] + _points[PELVIS]) * 0.5
	_points[BELLY] = mid + fwd * CharacterConfig.ragdoll_belly * r
	_points[SPINE] = mid - fwd * CharacterConfig.ragdoll_belly * r

	for i in 2:
		var out := -1.0 if i == 0 else 1.0
		# Arm: the shoulder reaches for the fist the hands layer holds, at its stance's grip height.
		var shoulder: Vector3 = _points[CHEST] + right * out * CharacterConfig.body_shoulder_width * r
		var grip: Vector2 = character.hand_position(i)
		var hand := Vector3(grip.x, grip.y, pose.grip_height(i) * r)
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

		# Leg: the foot strides along the hips' forward, back when the arm on its side swings forward.
		var hip: Vector3 = _points[PELVIS] + hip_right * out * CharacterConfig.body_hip_width * r
		var phase: float = pose.stride_phase() + (0.0 if i == 0 else PI)
		var walk: float = pose.walk_amount()
		var run: float = pose.run_amount()  # A run strides wider and lifts higher.
		var stride := lerpf(CharacterConfig.body_stride, CharacterConfig.body_run_stride, run)
		var foot_lift := lerpf(CharacterConfig.body_foot_lift, CharacterConfig.body_run_foot_lift, run)
		var step := -sin(phase) * walk * stride * r
		var lift := maxf(-cos(phase), 0.0) * walk * foot_lift * r  # Off the floor mid-swing.
		var ankle := Vector3(hip.x, hip.y, foot_z + lift) + hip_fwd * step
		_points[HIP[i]] = hip
		_points[ANKLE[i]] = ankle
		_points[KNEE[i]] = _bend(hip, ankle, thigh, shin, hip_fwd)
		_toes[i] = hip_fwd


## Joint `i`'s position (local x/y px, z = height px).
func point(i: int) -> Vector3:
	return _points[i]


## Which way side `i`'s toes point (unit, flat).
func toes(i: int) -> Vector3:
	return _toes[i]


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
