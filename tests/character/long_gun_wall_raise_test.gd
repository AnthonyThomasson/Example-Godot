extends GameTest

## A long gun is too long for a wall: with its barrel against a wall or object the SMG and the rifle are raised, pointing
## up with the butt still on the shoulder, and cannot fire. The pistol can, point-blank. Backing off lowers the gun
## again and it fires. A person standing in front of the barrel is not a wall, and does not stop it.

const Rig = preload("res://scenes/character/body/character_rig.gd")

## How far a bone may differ from its configured length (fraction), as in the standing-body rig test.
const BONE_TOLERANCE := 0.06


func describe() -> Dictionary:
	return {
		"name": "A long gun is raised and silent against a wall",
		"description": "SMG and rifle against a wall: blocked, raised and unable to fire; the pistol fires; backing off lowers them; a person in front doesn't block.",
		"tags": ["gun", "wall", "raise", "stance", "rifle", "smg", "pistol"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"projectile.flyover", false)
	# The arena's west wall runs along x = 0, 12 px thick: its face is at x = 6. Close enough to touch the barrel.
	s.actor(&"rifle_wall", &"puppet", Vector2(30, 100), { "start_slot": 6 })
	s.actor(&"smg_wall", &"puppet", Vector2(30, 200), { "start_slot": 5 })
	s.actor(&"pistol_wall", &"puppet", Vector2(30, 300), { "start_slot": 3 })
	s.actor(&"rifle_free", &"puppet", Vector2(300, 400), { "start_slot": 6 })
	# A rifle with a person right in front of its barrel, and nothing else near.
	s.actor(&"rifle_person", &"puppet", Vector2(400, 500), { "start_slot": 6 })
	s.actor(&"bystander", &"puppet", Vector2(360, 500), { "max_health": 400.0 })
	# A rifle against the east wall (its face is at x = 794), facing east as every character does until it is told
	# otherwise, that is told to shoot on its very first frame.
	s.actor(&"rifle_first", &"puppet", Vector2(770, 300), { "start_slot": 6 })


func run(t: TestContext) -> void:
	# Before anything has been judged: a controller that pulls the trigger on the character's first frame must not
	# get a round out through the wall.
	var first_rounds: int = t.actor(&"rifle_first").ammo()
	t.puppet(&"rifle_first").shoot()
	await t.frames(3)
	t.expect_eq(t.actor(&"rifle_first").ammo(), first_rounds, "a long gun told to shoot on its first frame, against a wall, fires nothing")

	for id in [&"rifle_wall", &"smg_wall", &"pistol_wall", &"rifle_free", &"rifle_person"]:
		t.puppet(id).aim_at(t.actor(id).global_position + Vector2(-1000, 0))  # West, into the wall or the open.
	await t.seconds(1.0)

	# Against the wall: the long guns are blocked, raised and silent; the pistol is none of those.
	for id in [&"rifle_wall", &"smg_wall"]:
		var c = t.actor(id)
		t.check(c.weapon_blocked(), "%s: its barrel is against the wall" % id)
		t.check(c.weapon_raise() > 0.95, "%s: the gun is raised (%.2f)" % [id, c.weapon_raise()])
		_check_arms(t, c, "%s raised" % id)
	var pistol = t.actor(&"pistol_wall")
	t.check(not pistol.weapon_blocked() and pistol.weapon_raise() == 0.0, "the pistol is not raised against a wall")
	for id in [&"rifle_free", &"rifle_person"]:
		t.check(not t.actor(id).weapon_blocked(), "%s: nothing solid is against the barrel" % id)
	t.check(t.actor(&"rifle_free").weapon_raise() == 0.0, "the rifle in the open is held to the aim")

	# Firing: only the unblocked guns spend a round.
	var rounds := {}
	for id in [&"rifle_wall", &"smg_wall", &"pistol_wall", &"rifle_free", &"rifle_person"]:
		rounds[id] = t.actor(id).ammo()
		t.puppet(id).shoot()
	await t.seconds(0.4)
	for id in [&"rifle_wall", &"smg_wall"]:
		t.expect_eq(t.actor(id).ammo(), rounds[id], "%s: it cannot fire against the wall" % id)
	for id in [&"pistol_wall", &"rifle_free", &"rifle_person"]:
		t.expect_eq(t.actor(id).ammo(), rounds[id] - 1, "%s: it fires" % id)
	t.check(not t.actor(&"rifle_wall").shoot(), "the character's own shoot() says no round left the barrel")

	# Backing off clears the barrel: the gun comes down and fires again.
	for id in [&"rifle_wall", &"smg_wall"]:
		t.puppet(id).walk_to(Vector2(140, t.actor(id).global_position.y))
	for id in [&"rifle_wall", &"smg_wall"]:
		t.check(await t.until(func(): return t.puppet(id).has_arrived(), 4.0), "%s: it backs away from the wall" % id)
	await t.seconds(0.8)
	for id in [&"rifle_wall", &"smg_wall"]:
		var c = t.actor(id)
		t.check(not c.weapon_blocked() and c.weapon_raise() < 0.05, "%s: clear of the wall, the gun comes back down (%.2f)" % [id, c.weapon_raise()])
		var before: int = c.ammo()
		t.puppet(id).shoot()
		await t.seconds(0.3)
		t.expect_eq(c.ammo(), before - 1, "%s: and it fires" % id)


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
