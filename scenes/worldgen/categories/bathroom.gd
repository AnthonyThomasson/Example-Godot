class_name BathroomCatalog

## Bathroom objects, arrangements, and recipe. Shared items (sink, cabinet, and the
## laundry_pair arrangement with its washing_machine/dryer) live in GeneralCatalog.

const OBJECTS := {
	"toilet": { "name": "Toilet", "shape": "circle", "size": Vector2(34, 34), "color": Color(0.95, 0.95, 0.95), "material": "ceramic", "art": "toilet", "weight": 35, "coverage": 40, "penetration": 55 },
	"bathtub": { "name": "Tub", "shape": "rect", "size": Vector2(100, 150), "color": Color(0.8, 0.8, 1.0), "material": "ceramic", "art": "bath", "art_opts": { "style": "tub" }, "weight": 120, "coverage": 45, "penetration": 60 },
	"shower": { "name": "Shower", "shape": "square", "size": Vector2(80, 80), "color": Color(0.75, 0.85, 0.95), "material": "glass", "art": "bath", "art_opts": { "style": "shower" }, "weight": 80, "coverage": 95, "penetration": 25 },
	"towel_rack": { "name": "Towels", "shape": "rect", "size": Vector2(50, 14), "color": Color(0.6, 0.6, 0.65), "material": "metal", "art": "fixture", "art_opts": { "kind": "towels" }, "weight": 4, "coverage": 25, "penetration": 30 },
	"bath_mat": { "name": "Mat", "shape": "rect", "size": Vector2(70, 40), "color": Color(0.5, 0.65, 0.75), "material": "fabric", "art": "rug", "art_opts": { "pattern": "plush" }, "weight": 2, "solid": false, "coverage": 0, "penetration": 5 },
}

const ARRANGEMENTS := {
	"bath_tub_zone": {
		"placement": "wall", "footprint": Vector2(150, 106), "prefer_corner": true,
		"items": [
			{ "key": "bathtub", "pos": Vector2(75, 53), "rotated": true },
		],
	},
	"shower_zone": {
		"placement": "wall", "footprint": Vector2(80, 125), "prefer_corner": true,
		"items": [
			{ "key": "shower", "pos": Vector2(40, 40) },
			{ "key": "bath_mat", "pos": Vector2(40, 103) },
		],
	},
	"shower_compact": {
		"placement": "wall", "footprint": Vector2(84, 84), "prefer_corner": true,
		"items": [{ "key": "shower", "pos": Vector2(42, 42) }],
	},
	"toilet_zone": {
		"placement": "wall", "footprint": Vector2(90, 40),
		"items": [
			{ "key": "toilet", "pos": Vector2(20, 20) },
			{ "key": "towel_rack", "pos": Vector2(65, 7) },
		],
	},
	"toilet_compact": {
		"placement": "wall", "footprint": Vector2(40, 40), "prefer_corner": true,
		"items": [{ "key": "toilet", "pos": Vector2(20, 20) }],
	},
	"vanity": {
		"placement": "wall", "footprint": Vector2(110, 50),
		"items": [
			{ "key": "sink", "pos": Vector2(25, 25) },
			{ "key": "cabinet", "pos": Vector2(82, 18) },
		],
	},
	"vanity_compact": {
		"placement": "wall", "footprint": Vector2(54, 54), "prefer_corner": true,
		"items": [{ "key": "sink", "pos": Vector2(27, 27) }],
	},
}

const RECIPES := {
	"bathroom": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.white, "fabric": GeneralCatalog.FABRIC.aqua, "floor": "mosaic" },
			{ "wood": GeneralCatalog.WOOD.ash, "fabric": GeneralCatalog.FABRIC.slate, "floor": "slate_tile" },
			{ "wood": GeneralCatalog.WOOD.charcoal, "fabric": GeneralCatalog.FABRIC.cream, "floor": "white_tile" },
		],
		"zones": [
			{ "options": ["bath_tub_zone", "shower_zone"], "count": Vector2i(1, 1), "required": true, "fallback": "shower_compact" },
			{ "options": ["toilet_zone"], "count": Vector2i(1, 1), "required": true, "fallback": "toilet_compact" },
			{ "options": ["vanity"], "count": Vector2i(1, 1), "required": true, "fallback": "vanity_compact" },
			{ "options": ["laundry_pair", "plant_corner"], "count": Vector2i(0, 1) },
		],
	},
}
