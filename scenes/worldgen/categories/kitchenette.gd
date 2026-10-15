class_name KitchenetteCatalog

## World Generation domain: kitchenette objects, arrangements and recipe: the cooking corner of a small flat. A short counter
## with a sink, a hotplate on a crate and a mini fridge, and room for a little table. Shared pieces (a table, chairs, storage)
## live in GeneralCatalog and KitchenCatalog.

const OBJECTS := {
	"kitchenette_counter": { "name": "Counter", "shape": "rect", "size": Vector2(100, 44), "color": Color(0.7, 0.68, 0.64), "material": "stone", "art": "counter", "art_opts": { "basin": "single", "props": [{ "kind": "cutting_board", "at": Vector2(0.22, 0.55) }] }, "weight": 70, "coverage": 55, "penetration": 70, "interactions": [{ "id": "prep", "label": "Prep food" }, { "id": "examine", "label": "Examine" }] },
	"hotplate": { "name": "Hotplate", "shape": "rect", "size": Vector2(40, 32), "color": Color(0.3, 0.3, 0.32), "material": "metal", "art": "hotplate", "weight": 12, "coverage": 40, "penetration": 40, "interactions": [{ "id": "cook", "label": "Cook" }, { "id": "examine", "label": "Examine" }] },
	"mini_fridge": { "name": "Fridge", "shape": "square", "size": Vector2(46, 46), "color": Color(0.85, 0.85, 0.85), "material": "metal", "art": "appliance", "art_opts": { "panel": "fridge" }, "weight": 40, "coverage": 60, "penetration": 70, "interactions": [{ "id": "open", "label": "Open fridge" }, { "id": "examine", "label": "Examine" }] },
}

const ARRANGEMENTS := {
	"kitchenette_line": {
		"placement": "wall", "footprint": Vector2(196, 46), "tags": ["fridge"],
		"items": [
			{ "key": "kitchenette_counter", "pos": Vector2(50, 22) },
			{ "key": "hotplate", "pos": Vector2(122, 16) },
			{ "key": "mini_fridge", "pos": Vector2(173, 23) },
		],
	},
	"kitchenette_compact": {
		"placement": "wall", "footprint": Vector2(144, 44),
		"items": [
			{ "key": "kitchenette_counter", "pos": Vector2(50, 22) },
			{ "key": "hotplate", "pos": Vector2(122, 16) },
		],
	},
	"mini_fridge_corner": {
		"placement": "wall", "footprint": Vector2(46, 46), "prefer_corner": true, "tags": ["fridge"],
		"items": [{ "key": "mini_fridge", "pos": Vector2(23, 23) }],
	},
}

const RECIPES := {
	"kitchenette": {
		"clutter": [["trash", 3.0], ["puddle", 2.0], ["cardboard", 1.0]],
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.mustard, "floor": "checker" },
			{ "wood": GeneralCatalog.WOOD.white, "fabric": GeneralCatalog.FABRIC.sage, "floor": "white_tile" },
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.cream, "floor": "concrete" },
		],
		"zones": [
			{ "options": ["kitchenette_line"], "count": Vector2i(1, 1), "required": true, "fallback": "kitchenette_compact" },
			{ "options": ["mini_fridge_corner"], "count": Vector2i(0, 1) },
			{ "options": ["dining_set_2", "dining_compact"], "count": Vector2i(0, 1) },
		],
		"fill": { "target": 0.3, "options": ["storage_wall", "pantry", "plant_corner", "lamp_corner"] },
	},
}
