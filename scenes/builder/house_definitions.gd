class_name HouseDefinitions

## House floorplans, in house-local coordinates (walls run along the rect edges).
##   rooms: key, type (a recipe in ArrangementDefinitions), rect.
##   doors: `pos` is the doorway center ON a wall line; every room whose wall passes
##          through it gets that gap cut. Exactly one door is `front` (the exterior
##          entrance the house is positioned by).

const PLANS := {
	"starter_home": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 0, 520, 350) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(520, 0, 380, 350) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 350, 520, 350) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(520, 350, 380, 350) },
		],
		"doors": [
			{ "pos": Vector2(260, 700), "width": 110.0, "front": true },  # living room, exterior
			{ "pos": Vector2(520, 525), "width": 100.0 },  # living room <-> kitchen
			{ "pos": Vector2(400, 350), "width": 100.0 },  # living room <-> bedroom
			{ "pos": Vector2(520, 175), "width": 90.0 },  # bedroom <-> bathroom (en-suite)
		],
	},
}

static func get_plan(key: String) -> Dictionary:
	return PLANS.get(key, {})
