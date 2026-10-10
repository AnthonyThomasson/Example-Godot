class_name KitchenCatalog

## Kitchen objects, arrangements, and recipe. Shared items (chair, sink, cabinet)
## live in GeneralCatalog.

const OBJECTS := {
	"kitchen_counter": { "name": "Counter", "shape": "rect", "size": Vector2(100, 50), "color": Color(0.8, 0.7, 0.6), "material": "stone", "weight": 80, "coverage": 55, "penetration": 70, "interactions": [{ "id": "prep", "label": "Prep food" }, { "id": "examine", "label": "Examine" }] },
	"stove": { "name": "Stove", "shape": "square", "size": Vector2(50, 50), "color": Color(0.2, 0.2, 0.22), "material": "metal", "weight": 60, "coverage": 50, "penetration": 80, "interactions": [{ "id": "cook", "label": "Cook" }, { "id": "examine", "label": "Examine" }] },
	"fridge": { "name": "Fridge", "shape": "rect", "size": Vector2(60, 70), "color": Color(0.9, 0.9, 0.95), "material": "metal", "weight": 90, "coverage": 90, "penetration": 85, "interactions": [{ "id": "open", "label": "Open fridge" }, { "id": "examine", "label": "Examine" }] },
	"dining_table": { "name": "Dining", "shape": "rect", "size": Vector2(90, 60), "color": Color(0.6, 0.4, 0.2), "material": "wood", "art": "table", "weight": 30, "coverage": 45, "penetration": 50, "interactions": [{ "id": "sit_at", "label": "Sit at table", "move_to": true }, { "id": "examine", "label": "Examine" }] },
	"table": { "name": "Table", "shape": "square", "size": Vector2(60, 60), "color": Color(0.6, 0.4, 0.2), "material": "wood", "art": "table", "weight": 20, "coverage": 45, "penetration": 50, "interactions": [{ "id": "sit_on", "label": "Sit on it", "move_to": true }, { "id": "examine", "label": "Examine" }] },
	"island": { "name": "Island", "shape": "rect", "size": Vector2(110, 55), "color": Color(0.8, 0.7, 0.6), "material": "stone", "weight": 140, "coverage": 55, "penetration": 70, "interactions": [{ "id": "prep", "label": "Prep food" }, { "id": "sit_at", "label": "Sit at island", "move_to": true }] },
	"microwave": { "name": "Micro", "shape": "square", "size": Vector2(40, 40), "color": Color(0.5, 0.5, 0.5), "material": "metal", "weight": 14, "coverage": 45, "penetration": 60, "interactions": [{ "id": "use", "label": "Heat food" }, { "id": "examine", "label": "Examine" }] },
}

const ARRANGEMENTS := {
	"cooking_line": {
		"placement": "wall", "footprint": Vector2(306, 50),
		"items": [
			{ "key": "kitchen_counter", "pos": Vector2(50, 25) },
			{ "key": "stove", "pos": Vector2(127, 25) },
			{ "key": "sink", "pos": Vector2(179, 25) },
			{ "key": "kitchen_counter", "pos": Vector2(256, 25) },
		],
	},
	"cooking_l_shape": {
		"placement": "wall", "footprint": Vector2(275, 70), "prefer_corner": true,
		"tags": ["fridge"],
		"items": [
			{ "key": "fridge", "pos": Vector2(30, 35) },
			{ "key": "kitchen_counter", "pos": Vector2(115, 25) },
			{ "key": "stove", "pos": Vector2(195, 25) },
			{ "key": "sink", "pos": Vector2(250, 25) },
		],
	},
	"cooking_compact": {
		"placement": "wall", "footprint": Vector2(108, 54),
		"items": [
			{ "key": "stove", "pos": Vector2(27, 27) },
			{ "key": "sink", "pos": Vector2(81, 27) },
		],
	},
	"fridge_corner": {
		"placement": "wall", "footprint": Vector2(60, 70), "prefer_corner": true,
		"tags": ["fridge"],
		"items": [{ "key": "fridge", "pos": Vector2(30, 35) }],
	},
	"dining_set_4": {
		"placement": "center", "footprint": Vector2(110, 130),
		"items": [
			{ "key": "dining_table", "pos": Vector2(55, 65) },
			{ "key": "chair", "pos": Vector2(32, 15) },
			{ "key": "chair", "pos": Vector2(78, 15) },
			{ "key": "chair", "pos": Vector2(32, 115), "facing": Vector2.UP },
			{ "key": "chair", "pos": Vector2(78, 115), "facing": Vector2.UP },
		],
	},
	"dining_set_2": {
		"placement": "center", "footprint": Vector2(70, 120),
		"items": [
			{ "key": "table", "pos": Vector2(35, 60) },
			{ "key": "chair", "pos": Vector2(35, 14) },
			{ "key": "chair", "pos": Vector2(35, 106), "facing": Vector2.UP },
		],
	},
	"island_stools": {
		"placement": "center", "footprint": Vector2(110, 90),
		"items": [
			{ "key": "island", "pos": Vector2(55, 28) },
			{ "key": "chair", "pos": Vector2(30, 75), "facing": Vector2.UP },
			{ "key": "chair", "pos": Vector2(80, 75), "facing": Vector2.UP },
		],
	},
	"pantry": {
		"placement": "wall", "footprint": Vector2(95, 40),
		"items": [
			{ "key": "cabinet", "pos": Vector2(25, 18) },
			{ "key": "microwave", "pos": Vector2(73, 20) },
		],
	},
}

const RECIPES := {
	"kitchen": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.cream },
			{ "wood": GeneralCatalog.WOOD.white, "fabric": GeneralCatalog.FABRIC.sage },
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.terracotta },
		],
		"zones": [
			{ "options": ["cooking_line", "cooking_l_shape"], "count": Vector2i(1, 1), "required": true, "fallback": "cooking_compact" },
			{ "options": ["fridge_corner"], "count": Vector2i(1, 1) },
			{ "options": ["dining_set_4", "dining_set_2", "island_stools"], "count": Vector2i(1, 1), "required": true, "fallback": "dining_compact" },
			{ "options": ["pantry", "plant_corner"], "count": Vector2i(0, 2) },
		],
	},
}
