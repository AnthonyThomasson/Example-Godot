extends GameTest

## A sandbox to play: you are the player in a furnished arena with every gun — pistol (3), SMG (5) and assault rifle
## (6) — plus fists (2), a few target dummies, and walls and furniture to press the barrel against. Nothing is
## asserted — compare the guns' fire rate (hold LMB for the automatics), damage and penetration (the rifle shoots
## through the east wall at the dummy behind it), see how each is held, and walk the rifle or SMG up to a wall or
## the chair to watch it come up and stop firing.


func describe() -> Dictionary:
	return {
		"name": "Gun range",
		"description": "Player-controlled sandbox: WASD to move, mouse to aim, LMB to fire (hold it for the SMG and rifle), R to reload, F to punch, V to kick, 2 fists, 3 pistol, 5 SMG, 6 rifle. Press a long gun against a wall or a chair to see it raised.",
		"tags": ["sandbox", "player", "gun", "pistol", "smg", "rifle"],
		"manual": true,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 640), { "floor": "concrete" })
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })
	s.actor(&"dummy_a", &"puppet", Vector2(700, 200), { "max_health": 200.0, "faction": &"dummy" })
	s.actor(&"dummy_b", &"puppet", Vector2(760, 440), { "max_health": 200.0, "faction": &"dummy" })
	# Just outside the east wall: only the rifle's rounds reach it.
	s.actor(&"dummy_behind_wall", &"puppet", Vector2(1040, 320), { "max_health": 200.0, "faction": &"dummy" })
	s.object(&"chair", "chair", Vector2(420, 200))
	s.object(&"armchair", "armchair", Vector2(460, 460))
	s.camera_follow([&"you"])
