extends GameTest

## The standing body is a full, proportioned skeleton (character_rig.gd): bones keep their length in
## every stance and mid-punch, each hand's grip matches its stance (arms hanging, fists up, a
## two-handed pistol hold), a punch still lands where it always did, the feet stride in
## opposition and the hips stay planted under a turning upper body, and a body that dies falls from
## exactly the pose it stood in. Drawing it all runs every frame, so any engine error fails the test too.

const Rig = preload("res://scenes/character/character_rig.gd")

## How far a bone may differ from its configured length (fraction): a punch stretches its arm a little.
const BONE_TOLERANCE := 0.06


func describe() -> Dictionary:
	return {
		"name": "Standing body skeleton",
		"description": "Bones keep their length, hands are held per stance, the punch lands as before, feet stride, hips plant, and a death starts from the standing pose.",
		"tags": ["rig", "pose", "arms", "legs", "stance", "ragdoll"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"unarmed", &"puppet", Vector2(200, 100), { "start_slot": 1 })
	s.actor(&"boxer", &"puppet", Vector2(200, 200), { "start_slot": 2 })
	s.actor(&"gunner", &"puppet", Vector2(200, 300), { "start_slot": 3 })
	s.actor(&"walker", &"puppet", Vector2(200, 400), { "start_slot": 2 })


func run(t: TestContext) -> void:
	for id in [&"unarmed", &"boxer", &"gunner", &"walker"]:
		t.puppet(id).aim_at(Vector2(2000, t.actor(id).global_position.y))
	await t.seconds(1.0)

	_check_stances(t)
	for id in [&"unarmed", &"boxer", &"gunner"]:
		_check_bones(t, id, "at rest")
	await _check_punch(t)
	await _check_hips(t)
	await _check_stride(t)
	await _check_death(t)


## Each stance holds its hands where it should: hanging low, fists up in front, the pistol out in
## front with the other hand cupping it.
func _check_stances(t: TestContext) -> void:
	var r: float = t.actor(&"boxer").radius
	var arm := (CharacterConfig.body_upper_arm + CharacterConfig.body_forearm) * r
	for i in 2:
		var low: float = t.actor(&"unarmed").rig().point(Rig.HAND[i]).z
		var shoulder: float = t.actor(&"unarmed").rig().point(Rig.SHOULDER[i]).z
		t.check(low < shoulder - arm * 0.8, "an unarmed hand hangs well below the shoulder (side %d, %.0f px)" % [i, shoulder - low])
		var raised: float = t.actor(&"boxer").rig().point(Rig.HAND[i]).z
		var guard_shoulder: float = t.actor(&"boxer").rig().point(Rig.SHOULDER[i]).z
		t.check(raised > guard_shoulder - arm * 0.3, "a fist is held up near the shoulder (side %d, %.0f px below)" % [i, guard_shoulder - raised])
	var gunner = t.actor(&"gunner")
	var aiming: Vector2 = gunner.hand_position(1)
	var cupping: Vector2 = gunner.hand_position(0)
	t.check(aiming.dot(gunner.facing) > 20.0, "the pistol hand reaches out in front (%.1f px ahead)" % aiming.dot(gunner.facing))
	t.check(aiming.distance_to(cupping) < 12.0, "the other hand cups it (%.1f px apart)" % aiming.distance_to(cupping))
	var muzzle: Vector2 = gunner.muzzle_origin(1) - gunner.hand_world(1)
	t.expect_near(muzzle.length(), CharacterConfig.muzzle_ahead, 0.01, "the muzzle sits muzzle_ahead past the weapon hand")


## Every bone keeps (about) its configured length, and each hand joint is where the hands layer put it.
func _check_bones(t: TestContext, id: StringName, when: String) -> void:
	var c = t.actor(id)
	var rig = c.rig()
	var r: float = c.radius
	var bones := [
		["upper arm", Rig.SHOULDER, Rig.ELBOW, CharacterConfig.body_upper_arm],
		["forearm", Rig.ELBOW, Rig.HAND, CharacterConfig.body_forearm],
		["thigh", Rig.HIP, Rig.KNEE, CharacterConfig.body_thigh],
		["shin", Rig.KNEE, Rig.ANKLE, CharacterConfig.body_shin],
	]
	for i in 2:
		for bone in bones:
			var want: float = bone[3] * r
			var got: float = rig.point(bone[1][i]).distance_to(rig.point(bone[2][i]))
			t.check(absf(got / want - 1.0) <= BONE_TOLERANCE,
				"%s: %s's %s (side %d) is %.1f px, want %.1f" % [when, id, bone[0], i, got, want])
		var hand: Vector3 = rig.point(Rig.HAND[i])
		t.check(Vector2(hand.x, hand.y).distance_to(c.hand_position(i)) < 0.01,
			"%s: %s's rig hand %d is where the hands layer holds it" % [when, id, i])


## A punch lands where it always did, the arm still reaches it (the shoulder leans in), the bones keep
## their length throughout, and the shoulders twist toward the punching side.
func _check_punch(t: TestContext) -> void:
	var boxer = t.actor(&"boxer")
	var hands = boxer.get_node("Hands")
	var rest_angle: float = boxer.pose.torso_angle
	t.puppet(&"boxer").punch()  # Hand 0 first.
	var reach := 0.0
	var twist := 0.0
	var lean := -1000.0
	for i in 24:
		await t.frames(1)
		if hands.punch_amount(0) > 0.5:
			_check_bones(t, &"boxer", "mid-punch")
		reach = maxf(reach, boxer.hand_position(0).dot(boxer.facing))
		twist = maxf(twist, absf(angle_difference(rest_angle, boxer.pose.torso_angle)))
		var shoulder: Vector3 = boxer.rig().point(Rig.SHOULDER[0])
		lean = maxf(lean, Vector2(shoulder.x, shoulder.y).dot(boxer.facing))
	var landing: float = boxer.radius + hands.hand_radius + hands.punch_gap + boxer.item_reach()
	t.check(reach > landing - 2.0, "the fist lands about %.0f px out (%.1f ahead)" % [landing, reach])
	t.check(twist > CharacterConfig.pose_punch_twist * 0.5, "the shoulders twist into the punch (%.2f rad)" % twist)
	t.check(lean > CharacterConfig.pose_punch_lunge, "the punching shoulder comes forward (%.1f px)" % lean)
	await t.seconds(0.4)
	t.check(boxer.pose.torso_offset.length() < 0.1, "the lunge settles once the punch is back")


## Hips stay planted under small turns of the aim, and follow once the shoulders twist past the limit.
func _check_hips(t: TestContext) -> void:
	var unarmed = t.actor(&"unarmed")
	var planted: float = unarmed.pose.hip_angle
	var off := Vector2(2000.0, 100.0 + 2000.0 * tan(deg_to_rad(20.0)))
	t.puppet(&"unarmed").aim_at(off)
	await t.seconds(0.8)
	t.check(absf(angle_difference(planted, unarmed.pose.hip_angle)) < 0.05,
		"the feet stay planted for a small turn (moved %.2f rad)" % absf(angle_difference(planted, unarmed.pose.hip_angle)))
	t.puppet(&"unarmed").aim_at(Vector2(200.0, -2000.0))
	var worst := 0.0
	for i in 20:
		await t.seconds(0.1)
		worst = maxf(worst, absf(angle_difference(unarmed.facing.angle(), unarmed.pose.hip_angle)))
	t.check(worst < CharacterConfig.pose_hip_twist + 0.3, "the hips are never twisted far past their limit (%.2f rad)" % worst)
	t.check(absf(angle_difference(unarmed.facing.angle(), unarmed.pose.hip_angle)) < CharacterConfig.pose_hip_twist + 0.15,
		"the feet end up within the twist limit of the aim")


## Walking east: each foot swings fore and aft, the two in opposition, lifting as they pass.
func _check_stride(t: TestContext) -> void:
	var walker = t.actor(&"walker")
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(0.8)
	var fore := [[], []]
	var lift := 0.0
	for k in 40:
		await t.frames(3)
		var rig = walker.rig()
		for i in 2:
			var ankle: Vector3 = rig.point(Rig.ANKLE[i])
			fore[i].append(ankle.x - rig.point(Rig.HIP[i]).x)
			lift = maxf(lift, ankle.z)
		if k % 10 == 0:
			_check_bones(t, &"walker", "walking")
	t.puppet(&"walker").stop()
	var span := 0.0
	var together := 0.0
	for k in fore[0].size():
		span = maxf(span, absf(fore[0][k]))
		together += fore[0][k] * fore[1][k]
	t.check(span > CharacterConfig.body_stride * walker.radius * 0.6, "the feet swing out fore and aft (%.1f px)" % span)
	t.check(together < 0.0, "the feet swing in opposition (%.0f)" % together)
	t.check(lift > CharacterConfig.ragdoll_limb_radius * walker.radius + 1.0, "a swinging foot lifts off the floor (%.1f px)" % lift)


## Killed mid-pose, the ragdoll's joints start exactly where the standing rig held them.
func _check_death(t: TestContext) -> void:
	var gunner = t.actor(&"gunner")
	var joints := [Rig.ELBOW[0], Rig.HAND[1], Rig.KNEE[0], Rig.ANKLE[1], Rig.SHOULDER[1], Rig.HEAD]
	var before := {}
	var rig = gunner.rig()
	for j in joints:
		before[j] = rig.point(j)
	gunner.take_damage(500.0)
	t.require(gunner.is_dead and gunner.ragdoll != null, "the gunner dies and starts to fall")
	for j in joints:
		var now: Vector3 = gunner.ragdoll.point(j)
		t.check(now.distance_to(before[j]) < 0.5, "joint %d starts where it stood (%.2f px off)" % [j, now.distance_to(before[j])])
	await t.seconds(0.3)
