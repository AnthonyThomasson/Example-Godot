class_name RoomDefinitions

const ROOMS := {
	"main_room": {
		"position": Vector2(140, 120),
		"size": 600.0,
		"wall_thickness": 24.0,
		"opening_side": 3,
		"opening_width": 120.0,
	},
}

static func get_definition(key: String) -> Dictionary:
	return ROOMS.get(key, {})

static func get_all() -> Array:
	return ROOMS.keys()
