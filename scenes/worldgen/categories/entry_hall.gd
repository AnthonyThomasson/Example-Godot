class_name EntryHallCatalog

## World Generation domain: entry-hall recipe. Its pieces (console_wall, bench_coats, entry_area, the runner
## rug) are shared with the hallway and live in GeneralCatalog.

const OBJECTS := {}

const ARRANGEMENTS := {}

const RECIPES := {
	"entry_hall": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.terracotta, "floor": "slate_tile" },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.sage, "floor": "terracotta_tile" },
		],
		"zones": [
			{ "options": ["console_wall", "bench_coats"], "count": Vector2i(1, 2), "required": true },
			{ "options": ["plant_corner", "entry_area"], "count": Vector2i(0, 1) },
		],
		"fill": { "target": 0.2, "options": ["plant_corner", "entry_area", "side_table_lamp", "lamp_corner", "console_wall", "runner_hall"] },
	},
}
