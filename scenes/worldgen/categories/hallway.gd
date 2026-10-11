class_name HallwayCatalog

## Hallway recipe: the corridor that bedrooms and bathrooms open off, so they are never walked through. It owns
## no pieces of its own — a console, a coat/shoe area, plants and a runner rug, all shared (GeneralCatalog).
## Every zone is optional: a hallway is narrow and must never fail to furnish.

const OBJECTS := {}

const ARRANGEMENTS := {}

const RECIPES := {
	"hallway": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.terracotta, "floor": "ash_planks" },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.sage, "floor": "walnut_planks" },
			{ "wood": GeneralCatalog.WOOD.white, "fabric": GeneralCatalog.FABRIC.navy, "floor": "grey_planks" },
		],
		"zones": [
			{ "options": ["console_wall", "bench_coats", "entry_area"], "count": Vector2i(1, 2) },
			{ "options": ["plant_corner", "lamp_corner"], "count": Vector2i(0, 2) },
		],
		"fill": { "target": 0.16, "options": ["console_wall", "console_wall", "bench_coats", "entry_area", "plant_corner", "plant_corner", "lamp_corner", "lamp_corner", "side_table_lamp", "side_table_lamp", "side_table_lamp", "runner_hall"] },
	},
}
