class_name GarageCatalog

## Garage objects, arrangements, and recipe. All single-category; no shared items.

const OBJECTS := {
	"car": { "name": "Car", "shape": "rect", "size": Vector2(130, 220), "color": Color(0.55, 0.12, 0.12), "material": "metal", "coverage": 65, "penetration": 90 },
	"workbench": { "name": "Bench", "shape": "rect", "size": Vector2(110, 45), "color": Color(0.5, 0.38, 0.25), "material": "wood", "coverage": 45, "penetration": 60 },
	"shelving": { "name": "Shelves", "shape": "rect", "size": Vector2(95, 30), "color": Color(0.55, 0.55, 0.58), "material": "metal", "coverage": 80, "penetration": 70 },
	"tool_chest": { "name": "Tools", "shape": "rect", "size": Vector2(45, 40), "color": Color(0.7, 0.15, 0.15), "material": "metal", "coverage": 40, "penetration": 80 },
}

const ARRANGEMENTS := {
	"car_bay": {
		"placement": "center", "footprint": Vector2(150, 240),
		"items": [{ "key": "car", "pos": Vector2(75, 120) }],
	},
	"workbench_wall": {
		"placement": "wall", "footprint": Vector2(165, 45),
		"items": [
			{ "key": "workbench", "pos": Vector2(55, 23) },
			{ "key": "tool_chest", "pos": Vector2(140, 20) },
		],
	},
	"garage_shelf": {
		"placement": "wall", "footprint": Vector2(95, 30), "prefer_corner": true,
		"items": [{ "key": "shelving", "pos": Vector2(47, 15) }],
	},
}

const RECIPES := {
	"garage": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.charcoal, "fabric": GeneralCatalog.FABRIC.slate },
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.navy },
		],
		"zones": [
			{ "options": ["car_bay"], "count": Vector2i(1, 1), "required": true },
			{ "options": ["workbench_wall"], "count": Vector2i(1, 1), "required": true },
			{ "options": ["garage_shelf"], "count": Vector2i(0, 2) },
		],
	},
}
