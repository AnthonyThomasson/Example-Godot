class_name LaundryRoomCatalog

## Laundry-room objects, arrangements, and recipe. Shared items (cabinet, plant, and
## the laundry_pair arrangement with washing_machine/dryer) live in GeneralCatalog.

const OBJECTS := {
	"laundry_sink": { "name": "Sink", "shape": "square", "size": Vector2(45, 45), "color": Color(0.72, 0.8, 0.88), "material": "ceramic", "coverage": 45, "penetration": 45 },
}

const ARRANGEMENTS := {
	"laundry_sink": {
		"placement": "wall", "footprint": Vector2(100, 45),
		"items": [
			{ "key": "laundry_sink", "pos": Vector2(23, 23) },
			{ "key": "cabinet", "pos": Vector2(74, 18) },
		],
	},
}

const RECIPES := {
	"laundry_room": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.white, "fabric": GeneralCatalog.FABRIC.slate },
			{ "wood": GeneralCatalog.WOOD.ash, "fabric": GeneralCatalog.FABRIC.aqua },
		],
		"zones": [
			{ "options": ["laundry_pair"], "count": Vector2i(1, 1), "required": true },
			{ "options": ["laundry_sink"], "count": Vector2i(1, 1) },
			{ "options": ["plant_corner"], "count": Vector2i(0, 1) },
		],
	},
}
