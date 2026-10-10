class_name BedroomCatalog

## Bedroom objects, arrangements, and recipe. Shared items (nightstand, desk, chair,
## lamp, armchair via reading_chair) live in GeneralCatalog.

const OBJECTS := {
	"bed": { "name": "Bed", "shape": "rect", "size": Vector2(120, 180), "color": Color(0.7, 0.3, 0.3), "material": "fabric", "weight": 50, "coverage": 35, "penetration": 30, "interactions": [{ "id": "lie", "label": "Lie down", "move_to": true }, { "id": "hide", "label": "Hide under bed", "move_to": true }, { "id": "make", "label": "Make the bed" }] },
	"wardrobe": { "name": "Wardrobe", "shape": "rect", "size": Vector2(90, 45), "color": Color(0.45, 0.28, 0.12), "material": "wood", "weight": 60, "coverage": 95, "penetration": 55, "interactions": [{ "id": "hide", "label": "Hide inside", "move_to": true }, { "id": "rummage", "label": "Rummage (needs Key)", "requires_item": 4 }] },
	"dresser": { "name": "Dresser", "shape": "rect", "size": Vector2(80, 40), "color": Color(0.5, 0.3, 0.1), "material": "wood", "weight": 35, "coverage": 45, "penetration": 55, "interactions": [{ "id": "open", "label": "Open drawer" }, { "id": "examine", "label": "Examine" }] },
}

const ARRANGEMENTS := {
	"bed_twin_nightstands": {
		"placement": "wall", "footprint": Vector2(212, 180),
		"items": [
			{ "key": "nightstand", "pos": Vector2(20, 20) },
			{ "key": "bed", "pos": Vector2(106, 90) },
			{ "key": "nightstand", "pos": Vector2(192, 20) },
		],
	},
	"bed_single_nightstand": {
		"placement": "wall", "footprint": Vector2(170, 180), "prefer_corner": true,
		"items": [
			{ "key": "bed", "pos": Vector2(60, 90) },
			{ "key": "nightstand", "pos": Vector2(150, 20) },
		],
	},
	"bed_compact": {
		"placement": "wall", "footprint": Vector2(124, 184), "prefer_corner": true,
		"items": [{ "key": "bed", "pos": Vector2(62, 92) }],
	},
	"wardrobe_wall": {
		"placement": "wall", "footprint": Vector2(180, 45),
		"items": [
			{ "key": "wardrobe", "pos": Vector2(45, 23) },
			{ "key": "dresser", "pos": Vector2(135, 20) },
		],
	},
	"wardrobe_compact": {
		"placement": "wall", "footprint": Vector2(94, 49), "prefer_corner": true,
		"items": [{ "key": "wardrobe", "pos": Vector2(47, 24) }],
	},
	"work_desk": {
		"placement": "wall", "footprint": Vector2(150, 95),
		"items": [
			{ "key": "desk", "pos": Vector2(60, 25) },
			{ "key": "chair", "pos": Vector2(60, 72), "facing": Vector2.UP },
			{ "key": "lamp", "pos": Vector2(140, 15) },
		],
	},
}

const RECIPES := {
	"bedroom": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.white, "fabric": GeneralCatalog.FABRIC.blush },
			{ "wood": GeneralCatalog.WOOD.cherry, "fabric": GeneralCatalog.FABRIC.cream },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.slate },
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.sage },
		],
		"zones": [
			{ "options": ["bed_twin_nightstands", "bed_single_nightstand"], "count": Vector2i(1, 1), "required": true, "fallback": "bed_compact" },
			{ "options": ["wardrobe_wall"], "count": Vector2i(1, 1), "required": true, "fallback": "wardrobe_compact" },
			{ "options": ["work_desk", "reading_chair"], "count": Vector2i(1, 2) },
			{ "options": ["plant_corner"], "count": Vector2i(0, 1) },
		],
	},
}
