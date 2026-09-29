class_name KidsRoomCatalog

## Kids-room objects, arrangements, and recipe. Shared items (nightstand, chair,
## bookshelf, plant) live in GeneralCatalog.

const OBJECTS := {
	"kids_bed": { "name": "Bed", "shape": "rect", "size": Vector2(80, 140), "color": Color(0.4, 0.6, 0.85), "material": "fabric", "weight": 20, "coverage": 30, "penetration": 30, "interactions": [{ "id": "lie", "label": "Lie down", "move_to": true }, { "id": "jump", "label": "Jump on bed", "move_to": true }, { "id": "hide", "label": "Hide under bed", "move_to": true }] },
	"toy_chest": { "name": "Toys", "shape": "rect", "size": Vector2(55, 38), "color": Color(0.9, 0.55, 0.25), "material": "wood", "weight": 10, "coverage": 35, "penetration": 45, "interactions": [{ "id": "open", "label": "Open toy chest" }, { "id": "rummage", "label": "Rummage" }] },
	"small_desk": { "name": "Desk", "shape": "rect", "size": Vector2(80, 40), "color": Color(0.45, 0.3, 0.15), "material": "wood", "weight": 14, "coverage": 40, "penetration": 45, "interactions": [{ "id": "sit_at", "label": "Sit at desk", "move_to": true }, { "id": "examine", "label": "Examine" }] },
}

const ARRANGEMENTS := {
	"kids_bed_zone": {
		"placement": "wall", "footprint": Vector2(130, 140), "prefer_corner": true,
		"items": [
			{ "key": "kids_bed", "pos": Vector2(40, 70) },
			{ "key": "nightstand", "pos": Vector2(110, 20) },
		],
	},
	"kids_bed_compact": {
		"placement": "wall", "footprint": Vector2(84, 144), "prefer_corner": true,
		"items": [{ "key": "kids_bed", "pos": Vector2(42, 72) }],
	},
	"play_area": {
		"placement": "wall", "footprint": Vector2(160, 75),
		"items": [
			{ "key": "toy_chest", "pos": Vector2(30, 19) },
			{ "key": "small_desk", "pos": Vector2(110, 20) },
			{ "key": "chair", "pos": Vector2(110, 55) },
		],
	},
	"play_compact": {
		"placement": "wall", "footprint": Vector2(59, 42), "prefer_corner": true,
		"items": [{ "key": "toy_chest", "pos": Vector2(29, 20) }],
	},
	"kids_books": {
		"placement": "wall", "footprint": Vector2(80, 40), "prefer_corner": true,
		"items": [{ "key": "bookshelf", "pos": Vector2(40, 20), "rotated": true }],
	},
}

const RECIPES := {
	"kids_room": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.ash, "fabric": GeneralCatalog.FABRIC.aqua },
			{ "wood": GeneralCatalog.WOOD.white, "fabric": GeneralCatalog.FABRIC.mustard },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.blush },
		],
		"zones": [
			{ "options": ["kids_bed_zone"], "count": Vector2i(1, 1), "required": true, "fallback": "kids_bed_compact" },
			{ "options": ["play_area"], "count": Vector2i(1, 1), "required": true, "fallback": "play_compact" },
			{ "options": ["kids_books", "plant_corner"], "count": Vector2i(0, 1) },
		],
	},
}
