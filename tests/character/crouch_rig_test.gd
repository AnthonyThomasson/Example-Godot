extends GameTest

## A crouch is a believable fold, not a shrunken stand (character_rig.gd): the spine pitches forward about the
## pelvis with the chest ahead of and above it and the head ahead of the chest, the body stays centred over its feet,
## the hips and feet are closer together than standing, the knees lead over the toes, and the bones keep their
## length. A standing body has none of this lean.

const Rig = preload("res://scenes/character/character_rig.gd")
const BONE_TOLERANCE := 0.06


func describe() -> Dictionary:
	return {
		"name": "A crouch leans forward with the legs together",
		"description": "Crouched: the chest is ahead of the pelvis at a spine pitch, the head ahead of the chest, hips and feet closer than standing, knees ahead of the hips, bones intact, body centred over the feet.",
		"tags": ["posture", "crouch", "rig", "legs", "torso"],
		"timeout": 15.0,
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
	var standing := _shape(t.actor(&"stand"))
	var crouched := _shape(t.actor(&"crouch"))

	t.check(absf(standing["lean"]) < 0.05 * r, "a standing chest is over its pelvis (%.1f px)" % standing["lean"])
	t.check(crouched["lean"] > 0.4 * r, "a crouched chest is ahead of its pelvis (%.1f px)" % crouched["lean"])
	var pitch := rad_to_deg(atan2(crouched["lean"], crouched["rise"]))
	t.check(pitch > 12.0 and pitch < 40.0, "the spine pitches forward about %.0f degrees" % pitch)
	t.check(crouched["rise"] > 0.0 and crouched["rise"] < standing["rise"], "the chest is above the pelvis, but lower than standing")
	t.check(crouched["head_ahead"] > standing["head_ahead"] + 0.1 * r, "the crouched head is ahead of the chest (%.1f px)" % crouched["head_ahead"])
	t.check(absf(crouched["centre"]) < 0.15 * r, "the body stays centred over the feet (%.1f px off)" % crouched["centre"])
	t.check(crouched["hip_gap"] < standing["hip_gap"] * 0.85, "the hips are closer together (%.1f vs %.1f px)" % [crouched["hip_gap"], standing["hip_gap"]])
	t.check(crouched["foot_gap"] < standing["foot_gap"] * 0.7, "the feet are closer together (%.1f vs %.1f px)" % [crouched["foot_gap"], standing["foot_gap"]])
	t.check(crouched["knee_ahead"] > 0.5 * r, "the knees lead over the toes (%.1f px ahead of the hips)" % crouched["knee_ahead"])
	t.check(crouched["head_ahead"] < 0.7 * r, "but not far ahead: the head is nearly over the shoulders (%.1f px)" % crouched["head_ahead"])
	t.check(crouched["reach"] > standing["reach"] * 0.9, "the gun hand is held out as far from the shoulder as standing (%.1f vs %.1f px)" % [crouched["reach"], standing["reach"]])
	t.check(t.actor(&"crouch").get_node("Visuals").draws_laid_out(), "a crouch is drawn from the rig's trunk, its back showing")
	t.check(not t.actor(&"stand").get_node("Visuals").draws_laid_out(), "a standing body is drawn as upright shoulders")
	for bone in ["thigh", "shin"]:
		var want: float = (CharacterConfig.body_thigh if bone == "thigh" else CharacterConfig.body_shin) * r
		var got: float = crouched[bone]
		t.check(absf(got - want) <= want * BONE_TOLERANCE, "the crouched %s keeps its length (%.1f of %.1f px)" % [bone, got, want])


## The measures of `c`'s rig along its facing (+x here): the chest ahead of / above the pelvis, the head ahead of
## the chest, how far the pelvis and chest middle sits off the body centre, the gap between the hips and between the
## ankles, how far the knees are ahead of the hips, and the leg bones' lengths.
func _shape(c) -> Dictionary:
	var rig = c.rig()
	var chest: Vector3 = rig.point(Rig.CHEST)
	var pelvis: Vector3 = rig.point(Rig.PELVIS)
	var head: Vector3 = rig.point(Rig.HEAD)
	var hips := [rig.point(Rig.HIP[0]), rig.point(Rig.HIP[1])]
	var ankles := [rig.point(Rig.ANKLE[0]), rig.point(Rig.ANKLE[1])]
	var knees := [rig.point(Rig.KNEE[0]), rig.point(Rig.KNEE[1])]
	return {
		"lean": chest.x - pelvis.x,
		"rise": chest.z - pelvis.z,
		"head_ahead": head.x - chest.x,
		"centre": (chest.x + pelvis.x) * 0.5,
		"hip_gap": absf(hips[0].y - hips[1].y),
		"foot_gap": absf(ankles[0].y - ankles[1].y),
		"knee_ahead": ((knees[0].x - hips[0].x) + (knees[1].x - hips[1].x)) * 0.5,
		"reach": rig.point(Rig.HAND[0]).x - rig.point(Rig.SHOULDER[0]).x,
		"thigh": hips[1].distance_to(knees[1]),
		"shin": knees[1].distance_to(ankles[1]),
	}
