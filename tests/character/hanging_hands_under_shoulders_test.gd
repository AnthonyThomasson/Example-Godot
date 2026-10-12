extends GameTest

## An unarmed character's hands hang at its sides, below the shoulders, so the shoulders are painted over them
## (character_visuals.gd); a hand raised to a gun is painted over the shoulders.


func describe() -> Dictionary:
	return {
		"name": "Hanging hands are drawn under the shoulders",
		"description": "Standing unarmed, the hands are lower than the shoulders and are painted before the torso; holding a pistol, they are painted after it.",
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
	t.check(armed.draw_order.find(&"hands") > armed.draw_order.find(&"torso"), "a gun's hands are painted over the torso")
	t.check(t.actor(&"armed").pose.grip_height(0) >= armed.HAND_OVER_HEIGHT, "a gun's hands grip at the shoulders")
