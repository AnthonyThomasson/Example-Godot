extends GameTest

## A sandbox to play: you are the player in a furnished arena with a pistol (3), fists (2) and two
## target dummies. Nothing is asserted — try shots, punches, shoves and interactions by hand.


func describe() -> Dictionary:
	return {
		"name": "Pistol range (play it)",
		"description": "Player-controlled sandbox: WASD to move, mouse to aim, LMB to fire, F to punch, Space to interact, 1–4 for items.",
		"tags": ["sandbox", "player", "pistol"],
		"manual": true,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 640), { "floor": "concrete" })
	s.actor(&"you", &"player", Vector2(200, 320), { "start_slot": 3 })
	s.actor(&"dummy_a", &"puppet", Vector2(760, 220), { "max_health": 200.0, "faction": &"dummy" })
	s.actor(&"dummy_b", &"puppet", Vector2(800, 440), { "max_health": 30.0, "faction": &"dummy" })
	s.object(&"chair", "chair", Vector2(420, 200))
	s.object(&"armchair", "armchair", Vector2(460, 460))
	s.camera_follow([&"you"])
