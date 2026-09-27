class_name EntryHallCatalog

## Entry-hall objects, arrangements, and recipe. Shared items (coat_rack via
## bench_coats, plant, and the entry_area arrangement) live in GeneralCatalog.

const OBJECTS := {
	"console_table": { "name": "Console", "shape": "rect", "size": Vector2(90, 28), "color": Color(0.5, 0.34, 0.2), "material": "wood", "coverage": 30, "penetration": 45 },
	"bench": { "name": "Bench", "shape": "rect", "size": Vector2(80, 30), "color": Color(0.55, 0.4, 0.25), "material": "wood", "coverage": 30, "penetration": 50 },
	"mirror": { "name": "Mirror", "shape": "rect", "size": Vector2(44, 12), "color": Color(0.7, 0.82, 0.85), "material": "glass", "coverage": 40, "penetration": 20 },
}

const ARRANGEMENTS := {
	"console_wall": {
		"placement": "wall", "footprint": Vector2(90, 42),
		"items": [
			{ "key": "mirror", "pos": Vector2(45, 6) },
			{ "key": "console_table", "pos": Vector2(45, 26) },
		],
	},
	"bench_coats": {
		"placement": "wall", "footprint": Vector2(125, 32),
		"items": [
			{ "key": "bench", "pos": Vector2(40, 16) },
			{ "key": "coat_rack", "pos": Vector2(95, 14) },
		],
	},
}

const RECIPES := {
	"entry_hall": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.terracotta },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.sage },
		],
		"zones": [
			{ "options": ["console_wall", "bench_coats"], "count": Vector2i(1, 2), "required": true },
			{ "options": ["plant_corner", "entry_area"], "count": Vector2i(0, 1) },
		],
	},
}
