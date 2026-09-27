class_name GeneralCatalog

## Shared catalogue: objects and arrangements used by 2+ room categories, the
## combined room-type recipes (kitchen_living, studio) that draw from several
## categories, and the WOOD/FABRIC material palettes every recipe shares.
##
## Object fields: name, shape ("circle"|"square"|"rect"), size, color (required);
##   material ("wood"|"fabric", optional — takes the room palette's tone);
##   solid (optional, default true; false = walk-over decor drawn under everything).
## Arrangements/recipes: see ArrangementDefinitions for the authoring conventions.

const OBJECTS := {
	"chair": { "name": "Chair", "shape": "square", "size": Vector2(28, 28), "color": Color(0.5, 0.33, 0.18), "material": "wood" },
	"lamp": { "name": "Lamp", "shape": "circle", "size": Vector2(20, 20), "color": Color(1.0, 1.0, 0.6) },
	"plant": { "name": "Plant", "shape": "circle", "size": Vector2(26, 26), "color": Color(0.25, 0.6, 0.3) },
	"armchair": { "name": "Armchair", "shape": "square", "size": Vector2(50, 50), "color": Color(0.7, 0.45, 0.3), "material": "fabric" },
	"side_table": { "name": "Side", "shape": "square", "size": Vector2(30, 30), "color": Color(0.55, 0.35, 0.2), "material": "wood" },
	"bookshelf": { "name": "Books", "shape": "rect", "size": Vector2(40, 80), "color": Color(0.4, 0.2, 0.0), "material": "wood" },
	"coat_rack": { "name": "Coats", "shape": "circle", "size": Vector2(24, 24), "color": Color(0.45, 0.3, 0.15), "material": "wood" },
	"shoe_rack": { "name": "Shoes", "shape": "rect", "size": Vector2(60, 25), "color": Color(0.45, 0.3, 0.15), "material": "wood" },
	"sink": { "name": "Sink", "shape": "square", "size": Vector2(50, 50), "color": Color(0.7, 0.8, 0.9) },
	"cabinet": { "name": "Cabinet", "shape": "rect", "size": Vector2(50, 35), "color": Color(0.55, 0.35, 0.2), "material": "wood" },
	"nightstand": { "name": "Night", "shape": "square", "size": Vector2(40, 40), "color": Color(0.6, 0.4, 0.2), "material": "wood" },
	"desk": { "name": "Desk", "shape": "rect", "size": Vector2(120, 50), "color": Color(0.4, 0.25, 0.1), "material": "wood" },
	"washing_machine": { "name": "Wash", "shape": "square", "size": Vector2(60, 60), "color": Color(0.9, 0.9, 0.9) },
	"dryer": { "name": "Dryer", "shape": "square", "size": Vector2(60, 60), "color": Color(0.7, 0.7, 0.7) },
}

const ARRANGEMENTS := {
	"plant_corner": {
		"placement": "wall", "footprint": Vector2(30, 30), "prefer_corner": true,
		"items": [{ "key": "plant", "pos": Vector2(15, 15) }],
	},
	"entry_area": {
		"placement": "wall", "footprint": Vector2(110, 32),
		"items": [
			{ "key": "coat_rack", "pos": Vector2(14, 16) },
			{ "key": "shoe_rack", "pos": Vector2(70, 13) },
		],
	},
	"side_table_lamp": {
		"placement": "wall", "footprint": Vector2(58, 30), "prefer_corner": true,
		"items": [
			{ "key": "side_table", "pos": Vector2(15, 15) },
			{ "key": "lamp", "pos": Vector2(45, 15) },
		],
	},
	"reading_chair": {
		"placement": "wall", "footprint": Vector2(80, 55), "prefer_corner": true,
		"tags": ["reading"],
		"items": [
			{ "key": "armchair", "pos": Vector2(25, 27) },
			{ "key": "lamp", "pos": Vector2(65, 15) },
		],
	},
	"laundry_pair": {
		"placement": "wall", "footprint": Vector2(125, 60), "prefer_corner": true,
		"items": [
			{ "key": "washing_machine", "pos": Vector2(30, 30) },
			{ "key": "dryer", "pos": Vector2(95, 30) },
		],
	},
	"dining_compact": {
		"placement": "wall", "footprint": Vector2(64, 64), "prefer_corner": true,
		"items": [{ "key": "table", "pos": Vector2(32, 32) }],
	},
}

## Material tones shared by all arrangements in a room, so zones blend together.
const WOOD := {
	"oak": Color(0.72, 0.53, 0.32), "walnut": Color(0.42, 0.27, 0.15),
	"cherry": Color(0.55, 0.27, 0.18), "ash": Color(0.8, 0.72, 0.6),
	"white": Color(0.88, 0.86, 0.82), "charcoal": Color(0.25, 0.25, 0.27),
}
const FABRIC := {
	"navy": Color(0.2, 0.28, 0.5), "sage": Color(0.5, 0.62, 0.48),
	"terracotta": Color(0.78, 0.42, 0.3), "mustard": Color(0.85, 0.65, 0.25),
	"blush": Color(0.85, 0.6, 0.62), "slate": Color(0.45, 0.5, 0.55),
	"cream": Color(0.9, 0.87, 0.78), "aqua": Color(0.45, 0.7, 0.75),
}

## Combined room types that pull arrangements from several categories.
const RECIPES := {
	"kitchen_living": {
		"palettes": [
			{ "wood": WOOD.oak, "fabric": FABRIC.terracotta },
			{ "wood": WOOD.walnut, "fabric": FABRIC.cream },
			{ "wood": WOOD.ash, "fabric": FABRIC.sage },
			{ "wood": WOOD.white, "fabric": FABRIC.navy },
		],
		"zones": [
			{ "options": ["tv_wall_cozy", "tv_wall_modern"], "count": Vector2i(1, 1), "required": true, "fallback": "tv_compact" },
			{ "options": ["cooking_line", "cooking_l_shape"], "count": Vector2i(1, 1), "required": true, "fallback": "cooking_compact" },
			{ "options": ["fridge_corner"], "count": Vector2i(1, 1) },
			{ "options": ["dining_set_4", "dining_set_2", "island_stools"], "count": Vector2i(1, 1), "required": true, "fallback": "dining_compact" },
			{ "options": ["reading_nook", "entry_area", "pantry", "plant_corner", "side_table_lamp"], "count": Vector2i(1, 3) },
		],
	},
	"studio": {
		"palettes": [
			{ "wood": WOOD.oak, "fabric": FABRIC.terracotta },
			{ "wood": WOOD.walnut, "fabric": FABRIC.cream },
			{ "wood": WOOD.ash, "fabric": FABRIC.sage },
		],
		"zones": [
			{ "options": ["tv_wall_cozy", "tv_wall_modern"], "count": Vector2i(1, 1), "required": true, "fallback": "tv_compact" },
			{ "options": ["cooking_line", "cooking_l_shape"], "count": Vector2i(1, 1), "required": true, "fallback": "cooking_compact" },
			{ "options": ["bed_single_nightstand", "bed_twin_nightstands"], "count": Vector2i(1, 1), "required": true, "fallback": "bed_compact" },
			{ "options": ["fridge_corner", "dining_set_2", "plant_corner"], "count": Vector2i(0, 2) },
		],
	},
}
