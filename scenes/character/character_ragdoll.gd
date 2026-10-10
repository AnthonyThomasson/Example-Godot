extends RefCounted

## Character RAGDOLL (Character domain, animate layer): the body falling on death. Builds a humanoid
## on the Physics domain's Ragdoll from the live pose — a rigid trunk (chest, pelvis, belly and back,
## shoulders, hips), the head, elbows, fists, knees and ankles — held by anatomical limits: swing
## cones at the neck, shoulders and hips, and hinges at the elbows and knees that only ever bend the
## natural way. It is launched with the body's momentum, a topple along the killing blow and a
## buckle at the knees, then left to fall. Owned and stepped by character.gd once dead; read by the
## visuals, which draw it top-down by height. Index pairs are per hand side (0 = left, 1 = right),
## matching the hands. Tuning: CharacterConfig.ragdoll_*.

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

## Directions in the trunk's frame: x toward the right shoulder, y up the spine, z out of the chest.
const UP := Vector3(0.0, 1.0, 0.0)
const DOWN := Vector3(0.0, -1.0, 0.0)
const FRONT := Vector3(0.0, 0.0, 1.0)
const BACK := Vector3(0.0, 0.0, -1.0)

## The simulated body (Physics domain).
var body := Ragdoll.new()
var _frame := 0  ## The trunk's frame id in `body`.


## Build the body standing in `character`'s live pose, moving at `momentum` (px/s) and knocked over
## along `blow` (the killing hit's direction; zero for none).
func _init(character, momentum: Vector2, blow: Vector2) -> void:
	var r: float = character.radius
	var pose = character.pose
	var f2 := Vector2.from_angle(pose.torso_angle)
	var fwd := Vector3(f2.x, f2.y, 0.0)
	var right := Vector3(f2.orthogonal().x, f2.orthogonal().y, 0.0)  # Hand 1's side.
	var up := Vector3(0.0, 0.0, 1.0)
	var hip_z := CharacterConfig.ragdoll_hip_height * r
	var shoulder_z := CharacterConfig.ragdoll_shoulder_height * r
	var upper := CharacterConfig.ragdoll_upper_arm * r
	var fore := CharacterConfig.ragdoll_forearm * r
	var thigh := CharacterConfig.ragdoll_thigh * r
	var shin := CharacterConfig.ragdoll_shin * r
	var torso_r := CharacterConfig.ragdoll_torso_radius * r
	var limb_r := CharacterConfig.ragdoll_limb_radius * r

	var head := Vector3(pose.head_offset.x, pose.head_offset.y, CharacterConfig.ragdoll_head_height * r)
	var shoulders := []
	var hips := []
	var elbows := []
	var hands := []
	var knees := []
	var ankles := []
	for i in 2:
		var out := right * (-1.0 if i == 0 else 1.0)
		var shoulder := up * shoulder_z + out * CharacterConfig.ragdoll_shoulder_width * r
		var hip := up * hip_z + out * CharacterConfig.ragdoll_hip_width * r
		# The fist where the hands hold it, at the height the arm reaches it with a relaxed bend.
		var grip: Vector2 = character.hand_position(i)
		var flat := grip - Vector2(shoulder.x, shoulder.y)
		var reach := (upper + fore) * 0.85
		if flat.length() > reach * 0.95:
			flat = flat.normalized() * reach * 0.95
		var hand := Vector3(shoulder.x + flat.x, shoulder.y + flat.y,
			shoulder.z - sqrt(maxf(reach * reach - flat.length_squared(), 0.0)))
		# Feet under the hips, fore and aft opposite to the arm swing mid-stride.
		var step: float = -sin(pose.stride_phase() + (0.0 if i == 0 else PI)) * pose.walk_amount() \
			* CharacterConfig.ragdoll_stride * r
		var ankle := Vector3(hip.x, hip.y, limb_r) + fwd * step
		shoulders.append(shoulder)
		hips.append(hip)
		hands.append(hand)
		ankles.append(ankle)
		elbows.append(_bend(shoulder, hand, upper, fore, -fwd + out * 0.6 - up * 0.3))
		knees.append(_bend(hip, ankle, thigh, shin, fwd))

	body.add_point(head, CharacterConfig.ragdoll_head_radius * r, CharacterConfig.ragdoll_head_mass)
	body.add_point(up * shoulder_z, torso_r, CharacterConfig.ragdoll_torso_mass)
	body.add_point(up * hip_z, torso_r, CharacterConfig.ragdoll_torso_mass)
	# Belly and back sit off the spine, their radii reaching just to the trunk's surface, so the trunk
	# lies flat on either side (rather than rocking on a keel) and can never fold through itself.
	var belly := CharacterConfig.ragdoll_belly * r
	var mid_z := (hip_z + shoulder_z) * 0.5
	var skin := maxf(torso_r - belly, 0.05 * r)
	body.add_point(up * mid_z + fwd * belly, skin, CharacterConfig.ragdoll_torso_mass)
	for i in 2:
		body.add_point(shoulders[i], limb_r, CharacterConfig.ragdoll_torso_mass)
	for i in 2:
		body.add_point(hips[i], torso_r * 0.8, CharacterConfig.ragdoll_torso_mass)
	for i in 2:
		body.add_point(elbows[i], limb_r, CharacterConfig.ragdoll_elbow_mass)
	for i in 2:
		body.add_point(hands[i], limb_r, CharacterConfig.ragdoll_hand_mass)
	for i in 2:
		body.add_point(knees[i], limb_r, CharacterConfig.ragdoll_knee_mass)
	for i in 2:
		body.add_point(ankles[i], limb_r, CharacterConfig.ragdoll_ankle_mass)
	body.add_point(up * mid_z - fwd * belly, skin, CharacterConfig.ragdoll_torso_mass)

	body.add_rigid([CHEST, PELVIS, BELLY, SPINE, SHOULDER[0], SHOULDER[1], HIP[0], HIP[1]])
	body.add_bone(CHEST, HEAD)
	for i in 2:
		body.add_bone(SHOULDER[i], ELBOW[i])
		body.add_bone(ELBOW[i], HAND[i])
		body.add_bone(HIP[i], KNEE[i])
		body.add_bone(KNEE[i], ANKLE[i])
	body.exclude.append(character.get_rid())

	_frame = body.add_frame(PELVIS, CHEST, SHOULDER[1], fwd)
	body.add_swing(_frame, CHEST, HEAD, UP, _limits(CharacterConfig.ragdoll_neck_limits, 1))
	var elbow := CharacterConfig.ragdoll_elbow_bend
	var knee := CharacterConfig.ragdoll_knee_bend
	for i in 2:
		body.add_swing(_frame, SHOULDER[i], ELBOW[i], DOWN, _limits(CharacterConfig.ragdoll_shoulder_limits, i))
		body.add_hinge(_frame, SHOULDER[i], ELBOW[i], HAND[i], DOWN, FRONT, deg_to_rad(elbow.x),
			deg_to_rad(elbow.y), deg_to_rad(CharacterConfig.ragdoll_elbow_slack))
		body.add_swing(_frame, HIP[i], KNEE[i], DOWN, _limits(CharacterConfig.ragdoll_hip_limits, i))
		body.add_hinge(_frame, HIP[i], KNEE[i], ANKLE[i], DOWN, BACK, deg_to_rad(knee.x),
			deg_to_rad(knee.y), deg_to_rad(CharacterConfig.ragdoll_knee_slack))

	_launch(momentum, blow, fwd, hip_z, shoulder_z)


## Seed the fall: everything carries the body's momentum; the upper body is pushed over along the
## blow (or, with none, a weaker push along the momentum or a random way), the knees buckle forward
## and every point gets a small random jolt, so no two falls are alike.
func _launch(momentum: Vector2, blow: Vector2, fwd: Vector3, hip_z: float, shoulder_z: float) -> void:
	var topple := CharacterConfig.ragdoll_hit_topple
	var dir := blow
	if dir.length() < 0.001:
		dir = momentum if momentum.length() > 1.0 else Vector2.from_angle(randf() * TAU)
		topple *= 0.4
	dir = dir.normalized()
	var base := Vector3(momentum.x, momentum.y, 0.0)
	var push := Vector3(dir.x, dir.y, 0.0) * topple
	var jitter := CharacterConfig.ragdoll_jitter
	for i in body.point_count():
		var lift := clampf((body.point(i).z - hip_z) / maxf(shoulder_z - hip_z, 1.0), 0.0, 1.2)
		var jolt := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * jitter
		body.push(i, base + push * lift + jolt)
	for i in 2:
		body.push(KNEE[i], fwd * CharacterConfig.ragdoll_knee_buckle)


## Advance the fall (see Ragdoll.step).
func step(delta: float, space: PhysicsDirectSpaceState2D, origin: Vector2) -> void:
	body.step(delta, space, origin)


## True once the body has come to rest.
func is_settled() -> bool:
	return body.asleep


## Point `i`'s position (local x/y px, z = height px).
func point(i: int) -> Vector3:
	return body.point(i)


## The trunk's live orientation: x toward the right shoulder, y up the spine, z out of the chest.
func torso() -> Basis:
	return body.frame_basis(_frame)


## Which way the face looks (unit, 3D).
func face() -> Vector3:
	return _carried(UP, FRONT, CHEST, HEAD)


## Which way side `i`'s toes point (unit, 3D).
func toes(i: int) -> Vector3:
	return _carried(DOWN, FRONT, KNEE[i], ANKLE[i])


## The trunk-frame direction `front` carried by the shortest turn taking the trunk-frame `rest`
## onto the live bone `a` → `b`.
func _carried(rest: Vector3, front: Vector3, a: int, b: int) -> Vector3:
	var basis := torso()
	var from := basis * rest
	var bone := (point(b) - point(a)).normalized()
	if from.dot(bone) < -0.999:
		return -(basis * front)
	return Quaternion(from, bone) * (basis * front)


## A swing cone's limits (degrees, in body terms) as frame-axis radians for side `i` (0 = left,
## 1 = right): a limb's outside is −x on the left and +x on the right.
static func _limits(deg: Dictionary, i: int) -> Dictionary:
	var out := deg_to_rad(deg["out"])
	var across := deg_to_rad(deg["in"])
	return {
		"front": deg_to_rad(deg["front"]), "back": deg_to_rad(deg["back"]),
		"right": out if i == 1 else across, "left": across if i == 1 else out,
	}


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
