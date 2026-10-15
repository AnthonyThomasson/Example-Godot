extends GameTest

## A sandbox to play (ticket #54, V9): you are the player in an open concrete yard walled in, with a red car and a white
## van parked in it, furniture scattered about to shove, and a few dummies standing around. Nothing is asserted. Walk up
## to a door and press E to get in (the nearest door that can open: the car's four, the van's two cab doors, its sliding
## side door and its rear doors), drive, press E again to get out. Feel the drift under the handbrake, crash into the walls,
## plough through the furniture, nudge (or run down) a dummy, and shoot the bodywork to dent it.


func describe() -> Dictionary:
	return {
		"name": "Vehicle yard",
		"description": "Player-controlled sandbox with a car and a van: E gets in by the nearest door (and out again), W throttle, S brake then reverse, A/D steer, Shift handbrake (a slide), mouse wheel zoom. On foot: WASD to walk, LMB to fire (dents the bodywork). Crash into the walls, shove the furniture, bump the dummies.",
		"tags": ["sandbox", "player", "vehicle", "car", "van", "drive"],
		"manual": true,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2400, 1500), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)  # the furniture gets rammed into heaps, which a re-bake would carve as overlapping holes
	s.actor(&"you", &"player", Vector2(380, 760), { "start_slot": 3 })
	s.vehicle(&"car", &"car", Vector2(620, 600))
	s.vehicle(&"van", &"van", Vector2(640, 940))
	# Furniture to plough through: a dining set in the middle of the yard, a lounge corner, a workshop along the far wall.
	s.object(&"table", "dining_table", Vector2(1300, 520))
	s.object(&"chair_a", "chair", Vector2(1230, 450))
	s.object(&"chair_b", "chair", Vector2(1370, 450))
	s.object(&"chair_c", "chair", Vector2(1230, 590))
	s.object(&"chair_d", "chair", Vector2(1370, 590))
	s.object(&"sofa", "sofa", Vector2(1250, 1100))
	s.object(&"armchair", "armchair", Vector2(1420, 1150))
	s.object(&"coffee_table", "coffee_table", Vector2(1300, 1000))
	s.object(&"bench", "bench", Vector2(1800, 300))
	s.object(&"shelving", "shelving", Vector2(2280, 700))
	s.object(&"tool_chest", "tool_chest", Vector2(2280, 900))
	s.object(&"workbench", "workbench", Vector2(2250, 1150))
	# Dummies to bump into (or run down).
	s.actor(&"dummy_a", &"puppet", Vector2(1700, 800), { "max_health": 200.0, "faction": &"dummy" })
	s.actor(&"dummy_b", &"puppet", Vector2(1900, 1050), { "max_health": 200.0, "faction": &"dummy" })
	s.actor(&"dummy_c", &"puppet", Vector2(1000, 300), { "max_health": 200.0, "faction": &"dummy" })
	s.camera_follow([&"you"])
