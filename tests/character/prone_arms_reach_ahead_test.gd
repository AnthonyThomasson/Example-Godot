extends GameTest

## Lying prone, the arms reach out in front of the head (character_hands.gd adds `posture_hand_ahead`), as a prone
## shooter's do, for a pistol and a rifle alike, with the bones at their length.

const Rig = preload("res://scenes/character/character_rig.gd")
const BONE_TOLERANCE := 0.06


func describe() -> Dictionary:
	return {
		"name": "A prone body's fists reach out ahead of its head",
		"description": "Prone with a pistol and with a rifle: both fists are ahead of the head along the aim, the arm bones keep their length.",
		"tags": ["posture", "prone", "rig", "arms", "pistol", "rifle"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.switch(&"nav.rebake", false)
	s.actor(&"pistol", &"puppet", Vector2(150, 100), { "start_slot": 3 })
	s.actor(&"rifle", &"puppet", Vector2(150, 250), { "start_slot": 6 })


func run(t: TestContext) -> void:
	for id in [&"pistol", &"rifle"]:
		t.puppet(id).aim_at(Vector2(2000, t.actor(id).global_position.y))
	t.puppet(&"pistol").set_posture(&"prone")
	t.puppet(&"rifle").set_posture(&"prone")
	await t.seconds(1.5)
	var r: float = t.actor(&"pistol").radius
	for id in [&"pistol", &"rifle"]:
		var rig = t.actor(id).rig()
		var head: Vector3 = rig.point(Rig.HEAD)
		t.check(head.x - rig.point(Rig.CHEST).x < 1.1 * r, "%s: the neck is short, the head %.1f px past the chest" % [id, head.x - rig.point(Rig.CHEST).x])
		for i in 2:
			var toes: Vector3 = rig.toes(i)
			# Side 1 is the aim's right hand (local -y, as the hands' lateral runs along orthogonal()), side 0 its left.
			var out := 1.0 if i == 0 else -1.0
			t.check(toes.y * out > 0.7, "%s: foot %d lies out to the side, not along the spine (%.2f)" % [id, i, toes.y * out])
			t.check(toes.x < 0.0, "%s: and its toes are turned back, not forward" % id)
			var hand: Vector3 = rig.point(Rig.HAND[i])
			t.check(hand.x > head.x, "%s: fist %d (%.1f px) is ahead of the head (%.1f px)" % [id, i, hand.x, head.x])
			for bone in [[Rig.SHOULDER, Rig.ELBOW, CharacterConfig.body_upper_arm], [Rig.ELBOW, Rig.HAND, CharacterConfig.body_forearm]]:
				var want: float = bone[2] * r
				var got: float = rig.point(bone[0][i]).distance_to(rig.point(bone[1][i]))
				t.check(absf(got / want - 1.0) <= BONE_TOLERANCE, "%s: side %d: an arm bone keeps its length (%.1f of %.1f px)" % [id, i, got, want])
