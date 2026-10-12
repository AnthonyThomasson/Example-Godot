extends GameTest

## A gun's size decides how it is held. The pistol is held out at arm's length in both hands, side by side on its
## grip; the SMG and the rifle are shouldered, the butt on the right shoulder, the trigger hand at the grip and the
## other hand out along the barrel — both hands on the barrel's line. In every hold the arms keep their
## length, and the muzzle sits where the gun's own length says. Drawing the art runs every frame, so any engine
## error fails the test too.

const Rig = preload("res://scenes/character/character_rig.gd")

## How far a bone may differ from its configured length (fraction), as in the standing-body rig test.
const BONE_TOLERANCE := 0.06
## How far (px) a hand may sit off the line through the weapon hand along the aim.
const LINE_TOLERANCE := 4.0
## How far (px) a long gun's butt may sit from the right shoulder joint, and how far apart (px) the pistol's two fists may be.
const SHOULDER_TOLERANCE := 8.0
const FISTS_TOGETHER := 8.0

const GUNS := {
	&"pistol": [&"pistol_man", 3],
	&"smg": [&"smg_man", 5],
	&"rifle": [&"rifle_man", 6],
}


func describe() -> Dictionary:
	return {
		"name": "Long guns are held by their size",
		"description": "Pistol, SMG and rifle holds: hands on the barrel, pistol hands together, butt of a long gun on the right shoulder, arms at their true length, muzzle at the gun's length.",
		"tags": ["gun", "stance", "rig", "arms", "pose"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.switch(&"nav.rebake", false)
	var y := 100.0
	for gun: StringName in GUNS:
		s.actor(GUNS[gun][0], &"puppet", Vector2(300, y), { "start_slot": GUNS[gun][1] })
		y += 200.0


func run(t: TestContext) -> void:
	for gun: StringName in GUNS:
		t.puppet(GUNS[gun][0]).aim_at(t.actor(GUNS[gun][0]).global_position + Vector2(2000, 0))
	await t.seconds(1.0)

	var lengths := {}
	var butts := {}
	for gun: StringName in GUNS:
		var c = t.actor(GUNS[gun][0])
		var item: GunItem = c.current_item()
		t.check(not c.weapon_blocked(), "%s: nothing is against the barrel" % gun)
		_check_arms(t, c, "%s hold" % gun)

		var f: Vector2 = c.facing
		var grip: Vector2 = c.hand_position(item.weapon_hand())
		var fore: Vector2 = c.hand_position(1 - item.weapon_hand())
		var butt := grip.dot(f) - item.grip_back()
		var tip := grip.dot(f) + item.muzzle_ahead()
		t.check(absf((fore - grip).dot(f.orthogonal())) <= LINE_TOLERANCE,
			"%s: the other hand is on the barrel's line (%.1f px off)" % [gun, absf((fore - grip).dot(f.orthogonal()))])
		t.check(fore.dot(f) >= butt - LINE_TOLERANCE and fore.dot(f) <= tip,
			"%s: the other hand is on the gun, between butt %.0f and muzzle %.0f (at %.0f)" % [gun, butt, tip, fore.dot(f)])
		var muzzle: Vector2 = c.muzzle_origin(item.weapon_hand()) - c.hand_world(item.weapon_hand())
		t.expect_near(muzzle.length(), item.muzzle_ahead(), 0.01, "%s: the muzzle sits muzzle_ahead past the weapon hand" % gun)
		lengths[gun] = item.art_size().y
		var shoulder: Vector3 = c.rig().point(Rig.SHOULDER[item.weapon_hand()])
		butts[gun] = (grip - f * item.grip_back()).distance_to(Vector2(shoulder.x, shoulder.y))
		t.check(grip.dot(f.orthogonal()) < 0.0, "%s: the weapon hand is on the character's right (%.1f px across)" % [gun, -grip.dot(f.orthogonal())])
		if gun == &"pistol":
			t.check(fore.distance_to(grip) <= FISTS_TOGETHER, "pistol: both fists are together on the grip (%.1f px apart)" % fore.distance_to(grip))
			t.check(absf((fore - grip).dot(f)) <= 1.0, "pistol: neither fist is ahead of the other (%.1f px)" % (fore - grip).dot(f))
	t.check(lengths[&"rifle"] > lengths[&"smg"] and lengths[&"smg"] > lengths[&"pistol"],
		"the guns are drawn longer the bigger they are (%s)" % lengths)
	for gun: StringName in [&"smg", &"rifle"]:
		t.check(butts[gun] <= SHOULDER_TOLERANCE, "a %s's butt is on the right shoulder (%.1f px from the joint)" % [gun, butts[gun]])
	var rifle = t.actor(&"rifle_man")
	t.check(rifle.hand_position(1).dot(rifle.facing) > rifle.hand_position(0).dot(rifle.facing) + 8.0,
		"the rifle's other hand reaches out along the barrel past the trigger hand")


## Both arms keep (about) their configured length.
func _check_arms(t: TestContext, c, when: String) -> void:
	var rig = c.rig()
	var r: float = c.radius
	var bones := [
		["upper arm", Rig.SHOULDER, Rig.ELBOW, CharacterConfig.body_upper_arm],
		["forearm", Rig.ELBOW, Rig.HAND, CharacterConfig.body_forearm],
	]
	for i in 2:
		for bone in bones:
			var want: float = bone[3] * r
			var got: float = rig.point(bone[1][i]).distance_to(rig.point(bone[2][i]))
			t.check(absf(got / want - 1.0) <= BONE_TOLERANCE,
				"%s: the %s (side %d) is %.1f px, want %.1f" % [when, bone[0], i, got, want])
