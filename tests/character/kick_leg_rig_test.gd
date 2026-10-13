extends GameTest

## A kick draws the leg: the kicking foot rises and is thrown out along the aim within the leg's reach, the thigh
## and shin keep their length throughout, the other leg stays put, and the foot returns to rest afterwards.

const Rig = preload("res://scenes/character/body/character_rig.gd")

## How far a bone may differ from its configured length (fraction).
const BONE_TOLERANCE := 0.06


func describe() -> Dictionary:
	return {
		"name": "Kick throws the foot out",
		"description": "Mid-kick the kicking ankle is raised and out along the aim, bones keep their length, the other foot stays, and it all returns to rest.",
		"tags": ["kick", "rig", "legs"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"kicker", &"puppet", Vector2(400, 250), { "start_slot": 1 })


func run(t: TestContext) -> void:
	var c := t.actor(&"kicker")
	var puppet := t.puppet(&"kicker")
	puppet.aim_at(Vector2(700, 250))
	await t.seconds(0.4)
	var rest: Vector3 = c.rig().point(Rig.ANKLE[0])
	var still: Vector3 = c.rig().point(Rig.ANKLE[1])
	puppet.kick()
	var out := 0.0
	var high := 0.0
	var still_moved := 0.0
	var r: float = c.radius
	for i in 30:
		await t.frames(1)
		var leg := 0  # The right leg always kicks.
		var rig = c.rig()
		var ankle: Vector3 = rig.point(Rig.ANKLE[leg])
		out = maxf(out, Vector2(ankle.x, ankle.y).dot(c.facing))
		high = maxf(high, ankle.z)
		still_moved = maxf(still_moved, rig.point(Rig.ANKLE[1 - leg]).distance_to(still if leg == 0 else rest))
		for bone in [["thigh", Rig.HIP, Rig.KNEE, CharacterConfig.body_thigh], ["shin", Rig.KNEE, Rig.ANKLE, CharacterConfig.body_shin]]:
			var want: float = bone[3] * r
			var got: float = rig.point(bone[1][leg]).distance_to(rig.point(bone[2][leg]))
			t.check(absf(got / want - 1.0) <= BONE_TOLERANCE, "frame %d: the kicking %s is %.1f px, want %.1f" % [i, bone[0], got, want])
	t.check(out > 30.0, "the foot is thrown out along the aim (%.1f px)" % out)
	t.check(out <= CharacterConfig.kick_reach + 0.5, "no further than kick_reach (%.1f px)" % out)
	t.check(high > rest.z + 10.0, "the foot is lifted (%.1f px up)" % high)
	t.check(still_moved < 1.0, "the other foot stays put (%.1f px)" % still_moved)
	await t.seconds(0.5)
	var back: Vector3 = c.rig().point(Rig.ANKLE[0])
	t.check(back.distance_to(rest) < 2.0, "the foot is back at rest (%.1f px away)" % back.distance_to(rest))
