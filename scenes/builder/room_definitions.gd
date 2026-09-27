class_name RoomDefinitions

const ROOMS := {
	"main_room": {
		"position": Vector2(140, 120),
		"size": Vector2(600, 600),
		"wall_thickness": 24.0,
		"openings": [{ "side": 3, "offset": 300.0, "width": 120.0 }],  # 3 = Side.LEFT
	},
}

static func get_definition(key: String) -> Dictionary:
	return ROOMS.get(key, {})

static func get_all() -> Array:
	return ROOMS.keys()
