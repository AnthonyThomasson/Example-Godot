class_name LivingRoomCatalog

## Living-room objects, arrangements, and recipe. Shared items (lamp, armchair,
## side_table, plant, bookshelf, coat_rack, shoe_rack) live in GeneralCatalog.

const OBJECTS := {
	"tv": { "name": "TV", "shape": "rect", "size": Vector2(80, 30), "color": Color(0.1, 0.1, 0.1) },
	"sofa": { "name": "Sofa", "shape": "rect", "size": Vector2(120, 50), "color": Color(0.8, 0.4, 0.2), "material": "fabric" },
	"coffee_table": { "name": "Coffee", "shape": "rect", "size": Vector2(70, 40), "color": Color(0.55, 0.35, 0.2), "material": "wood" },
	"rug": { "name": "Rug", "shape": "rect", "size": Vector2(170, 110), "color": Color(0.6, 0.35, 0.35), "material": "fabric", "solid": false },
}

const ARRANGEMENTS := {
	"tv_wall_cozy": {
		"placement": "wall", "footprint": Vector2(200, 175),
		"items": [
			{ "key": "tv", "pos": Vector2(100, 15) },
			{ "key": "rug", "pos": Vector2(100, 105) },
			{ "key": "coffee_table", "pos": Vector2(100, 85) },
			{ "key": "sofa", "pos": Vector2(100, 148) },
			{ "key": "lamp", "pos": Vector2(180, 148) },
		],
	},
	"tv_wall_modern": {
		"placement": "wall", "footprint": Vector2(240, 170),
		"items": [
			{ "key": "tv", "pos": Vector2(120, 15) },
			{ "key": "rug", "pos": Vector2(120, 100) },
			{ "key": "coffee_table", "pos": Vector2(120, 85) },
			{ "key": "sofa", "pos": Vector2(120, 145) },
			{ "key": "armchair", "pos": Vector2(25, 90) },
			{ "key": "side_table", "pos": Vector2(215, 145) },
		],
	},
	"tv_compact": {
		"placement": "wall", "footprint": Vector2(124, 60),
		"items": [
			{ "key": "tv", "pos": Vector2(62, 18) },
			{ "key": "sofa", "pos": Vector2(62, 45) },
		],
	},
	"reading_nook": {
		"placement": "wall", "footprint": Vector2(130, 95), "prefer_corner": true,
		"tags": ["reading"],
		"items": [
			{ "key": "bookshelf", "pos": Vector2(40, 20), "rotated": true },
			{ "key": "armchair", "pos": Vector2(100, 68) },
			{ "key": "lamp", "pos": Vector2(60, 70) },
		],
	},
}

const RECIPES := {
	"living_room": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.navy },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.terracotta },
			{ "wood": GeneralCatalog.WOOD.ash, "fabric": GeneralCatalog.FABRIC.sage },
			{ "wood": GeneralCatalog.WOOD.charcoal, "fabric": GeneralCatalog.FABRIC.mustard },
		],
		"zones": [
			{ "options": ["tv_wall_cozy", "tv_wall_modern"], "count": Vector2i(1, 1), "required": true, "fallback": "tv_compact" },
			{ "options": ["reading_nook", "entry_area"], "count": Vector2i(1, 2) },
			{ "options": ["plant_corner", "side_table_lamp"], "count": Vector2i(0, 2) },
		],
	},
}
