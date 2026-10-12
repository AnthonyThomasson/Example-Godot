extends GameTest

## Legs do not pass through walls (character_legs.gd). A prone body lying with its feet toward the arena's west wall
## rests against it: no ankle or knee of the drawn rig is on the far side of the wall's face, though the same legs
## solved without the contact would be. A crouched body pressed against the wall with its knees leading stays clear of
## it too (its knees lead over the toes but not past the body). A body in the open, well away from anything, is
## untouched (no leg is held).

const Rig = preload("res://scenes/character/character_rig.gd")
## The west wall's inner face (world x): the arena wall is 12 px thick, centred on the arena's edge.
const WALL_FACE := 6.0


func describe() -> Dictionary:
	return {
		"name": "Legs rest against a wall instead of drawing through it",
		"description": "A prone body with its legs toward a wall keeps every ankle and knee on this side of it where the unobstructed legs would pass through; a crouched one pressed against it stays clear; a body in the open has no leg held.",
		"tags": ["legs", "contact", "wall", "posture", "prone", "crouch", "rig"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.switch(&"nav.rebake", false)
	s.actor(&"prone", &"puppet", Vector2(45, 100), { "start_slot": 3 })     # Faces east, feet toward the west wall.
	s.actor(&"crouch", &"puppet", Vector2(21, 250), { "start_slot": 3 })    # Faces west, pressed against the west wall.
	s.actor(&"open", &"puppet", Vector2(400, 400), { "start_slot": 3 })


func run(t: TestContext) -> void:
	t.puppet(&"prone").aim_at(Vector2(2000, 100))
	t.puppet(&"prone").set_posture(&"prone")
	t.puppet(&"crouch").aim_at(Vector2(-2000, 250))
	t.puppet(&"crouch").set_posture(&"crouch")
	t.puppet(&"open").aim_at(Vector2(2000, 400))
	t.puppet(&"open").set_posture(&"prone")
	await t.seconds(1.8)

	for id in [&"prone", &"crouch"]:
		var c = t.actor(id)
		var rig = c.rig()
		var free = Rig.new(c, false)
		var clamped := 0
		var would_pass := 0
		for i in 2:
			for joint in [Rig.ANKLE[i], Rig.KNEE[i]]:
				var at: float = c.global_position.x + (rig.point(joint) as Vector3).x
				var loose: float = c.global_position.x + (free.point(joint) as Vector3).x
				t.check(at >= WALL_FACE - 0.5, "the %s body's %s joint %d stays this side of the wall (x %.1f, wall face %.1f)" % [id, "ankle" if joint in Rig.ANKLE else "knee", i, at, WALL_FACE])
				if loose < WALL_FACE:
					would_pass += 1
			if c.foot_clamp(i) != null:
				clamped += 1
		if id == &"prone":
			t.check(would_pass > 0, "without the contact the prone body's legs would pass through the wall")
			t.check(clamped > 0, "the prone body has a leg resting against the wall")

	t.check(t.actor(&"open").foot_clamp(0) == null and t.actor(&"open").foot_clamp(1) == null, "a body in the open has no leg held")
