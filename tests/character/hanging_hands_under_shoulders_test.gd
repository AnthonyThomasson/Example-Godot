extends GameTest

## An unarmed character's hands hang at its sides, below the shoulder height that puts a hand over the shoulders
## (character_visuals.gd `HAND_OVER_HEIGHT`); a hand raised to a gun grips at that height.


func describe() -> Dictionary:
	return {
		"name": "Hanging hands grip below the shoulders",
		"description": "Standing unarmed, the hands grip below the shoulder height; holding a pistol, they grip at it.",
		"tags": ["draw", "hands"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.switch(&"nav.rebake", false)
	s.actor(&"unarmed", &"puppet", Vector2(200, 200), { "start_slot": ItemRegistry.UNARMED_SLOT })
	s.actor(&"armed", &"puppet", Vector2(500, 200), { "start_slot": 3 })


func run(t: TestContext) -> void:
	await t.seconds(1.5)
	var unarmed = t.actor(&"unarmed").get_node("Visuals")
	var armed = t.actor(&"armed").get_node("Visuals")
	t.check(t.actor(&"unarmed").pose.grip_height(0) < unarmed.HAND_OVER_HEIGHT, "unarmed hands grip below the shoulders")
	t.check(t.actor(&"armed").pose.grip_height(0) >= armed.HAND_OVER_HEIGHT, "a gun's hands grip at the shoulders")
