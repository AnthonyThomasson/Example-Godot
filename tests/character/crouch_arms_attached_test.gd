extends GameTest

## A crouch keeps the arms on the body: the folded spine carries the chest ahead of the pelvis, and the drawn
## shoulders and head go with it (character_visuals.gd draws them at the rig's chest and head), so each sleeve starts
## inside the shoulders instead of floating ahead of them. Standing, nothing moves, and the arms keep their length.

const Rig = preload("res://scenes/character/character_rig.gd")
const BONE_TOLERANCE := 0.06


func describe() -> Dictionary:
	return {
		"name": "A crouched body's shoulders and head go with its folded spine",
		"description": "Crouched: the drawn shoulders and head sit at the rig's chest and head (ahead of the standing spot), every sleeve starts within the shoulders' edge, and the arm bones keep their length.",
		"tags": ["posture", "crouch", "rig", "arms", "visuals"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.switch(&"nav.rebake", false)
	s.actor(&"stand", &"puppet", Vector2(150, 100), { "start_slot": 3 })
	s.actor(&"crouch", &"puppet", Vector2(150, 250), { "start_slot": 3 })


func run(t: TestContext) -> void:
	for id in [&"stand", &"crouch"]:
		t.puppet(id).aim_at(Vector2(2000, t.actor(id).global_position.y))
	t.puppet(&"crouch").set_posture(&"crouch")
	await t.seconds(1.5)
	var r: float = t.actor(&"stand").radius
	var standing = t.actor(&"stand")
	var crouched = t.actor(&"crouch")
	var shoulders: Vector2 = crouched.get_node("Visuals").shoulder_centre()
	var head: Vector2 = crouched.get_node("Visuals").head_centre()

	t.check(standing.get_node("Visuals").shoulder_centre().length() < 0.1 * r, "standing, the shoulders are over the body centre")
	t.check(shoulders.x > 0.3 * r, "crouched, the drawn shoulders are carried ahead (%.1f px)" % shoulders.x)
	t.check(crouched.get_node("Visuals").draws_laid_out(), "the crouched body is drawn from its trunk, so the sleeves meet a real back")
	t.check(head.x > shoulders.x, "and the head is ahead of them (%.1f vs %.1f px)" % [head.x, shoulders.x])
	var rig = crouched.rig()
	for i in 2:
		var start := Vector2(rig.point(Rig.SHOULDER[i]).x, rig.point(Rig.SHOULDER[i]).y)
		t.check(start.distance_to(shoulders) <= r * 1.0, "side %d: the sleeve starts inside the drawn shoulders (%.1f px from their centre)" % [i, start.distance_to(shoulders)])
		for bone in [[Rig.SHOULDER, Rig.ELBOW, CharacterConfig.body_upper_arm], [Rig.ELBOW, Rig.HAND, CharacterConfig.body_forearm]]:
			var want: float = bone[2] * r
			var got: float = rig.point(bone[0][i]).distance_to(rig.point(bone[1][i]))
			t.check(absf(got / want - 1.0) <= BONE_TOLERANCE, "side %d: an arm bone keeps its length (%.1f of %.1f px)" % [i, got, want])
