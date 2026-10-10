class_name GeneralCatalog

## Shared catalogue: objects and arrangements used by 2+ room categories, the
## combined room-type recipes (kitchen_living, studio) that draw from several
## categories, the WOOD/FABRIC material palettes every recipe shares, the FLOORS a
## palette's `floor` names, and the house WALL style.
##
## Object fields: name, shape ("circle"|"square"|"rect"), size, color (required);
##   material (descriptive tag — "wood"/"fabric" also take the room palette's tone;
##     "metal"/"ceramic"/"glass"/"plastic"/"stone"/"electronics"/"foliage" are
##     descriptive only, never recolored);
##   coverage (0–100, a height/cover proxy); penetration (0–100, resistance to being
##     shot through); weight (mass for knockback — heavier = thrown back less);
##     solid (optional, default true; false = walk-over decor under all);
##   art (optional pixel-art painter id, e.g. "sofa", "cabinet", "appliance"; omitted =
##     flat shape + label) and art_opts (optional painter variant/overrides, e.g.
##     { "front": "drawers", "count": 3 } or { "props": [...] }).
## Arrangements/recipes: see ArrangementDefinitions for the authoring conventions.

const OBJECTS := {
	"chair": { "name": "Chair", "shape": "square", "size": Vector2(28, 28), "color": Color(0.5, 0.33, 0.18), "material": "wood", "art": "chair", "weight": 6, "coverage": 45, "penetration": 50, "interactions": [{ "id": "sit", "label": "Sit", "move_to": true }, { "id": "stand_on", "label": "Stand on it", "move_to": true }] },
	"lamp": { "name": "Lamp", "shape": "circle", "size": Vector2(20, 20), "color": Color(1.0, 1.0, 0.6), "material": "metal", "art": "lamp", "weight": 3, "coverage": 55, "penetration": 30, "interactions": [{ "id": "toggle", "label": "Toggle light" }, { "id": "examine", "label": "Examine" }] },
	"plant": { "name": "Plant", "shape": "circle", "size": Vector2(26, 26), "color": Color(0.25, 0.6, 0.3), "material": "foliage", "art": "plant", "weight": 5, "coverage": 50, "penetration": 10, "interactions": [{ "id": "water", "label": "Water plant" }, { "id": "examine", "label": "Examine" }] },
	"armchair": { "name": "Armchair", "shape": "square", "size": Vector2(50, 50), "color": Color(0.7, 0.45, 0.3), "material": "fabric", "art": "sofa", "art_opts": { "cushion_width": 200.0, "pillows": false, "arm_width": 0.2, "back_depth": 0.3 }, "weight": 22, "coverage": 50, "penetration": 25, "interactions": [{ "id": "sit", "label": "Sit", "move_to": true }, { "id": "lie", "label": "Curl up", "move_to": true }] },
	"side_table": { "name": "Side", "shape": "square", "size": Vector2(30, 30), "color": Color(0.55, 0.35, 0.2), "material": "wood", "art": "table", "art_opts": { "props": [{ "kind": "book", "at": Vector2(0.5, 0.5) }] }, "weight": 8, "coverage": 40, "penetration": 45, "interactions": [{ "id": "examine", "label": "Examine" }] },
	"bookshelf": { "name": "Books", "shape": "rect", "size": Vector2(40, 80), "color": Color(0.4, 0.2, 0.0), "material": "wood", "art": "shelf", "art_opts": { "contents": "books" }, "weight": 30, "coverage": 90, "penetration": 60, "interactions": [{ "id": "browse", "label": "Browse books" }, { "id": "examine", "label": "Examine" }] },
	"coat_rack": { "name": "Coats", "shape": "circle", "size": Vector2(24, 24), "color": Color(0.45, 0.3, 0.15), "material": "wood", "art": "coat_rack", "weight": 6, "coverage": 60, "penetration": 25, "interactions": [{ "id": "examine", "label": "Examine" }] },
	"shoe_rack": { "name": "Shoes", "shape": "rect", "size": Vector2(60, 25), "color": Color(0.45, 0.3, 0.15), "material": "wood", "art": "shelf", "art_opts": { "contents": "shoes" }, "weight": 7, "coverage": 20, "penetration": 35, "interactions": [{ "id": "examine", "label": "Examine" }] },
	"sink": { "name": "Sink", "shape": "square", "size": Vector2(50, 50), "color": Color(0.7, 0.8, 0.9), "material": "ceramic", "art": "counter", "art_opts": { "basin": "single" }, "weight": 20, "coverage": 45, "penetration": 45, "interactions": [{ "id": "use", "label": "Wash up" }, { "id": "examine", "label": "Examine" }] },
	"cabinet": { "name": "Cabinet", "shape": "rect", "size": Vector2(50, 35), "color": Color(0.55, 0.35, 0.2), "material": "wood", "art": "cabinet", "art_opts": { "front": "doors", "count": 2 }, "weight": 22, "coverage": 55, "penetration": 50, "interactions": [{ "id": "open", "label": "Open cabinet" }, { "id": "examine", "label": "Examine" }] },
	"nightstand": { "name": "Night", "shape": "square", "size": Vector2(40, 40), "color": Color(0.6, 0.4, 0.2), "material": "wood", "art": "cabinet", "art_opts": { "front": "drawers", "count": 1, "props": [{ "kind": "clock", "at": Vector2(0.28, 0.45) }, { "kind": "book", "at": Vector2(0.68, 0.5) }] }, "weight": 10, "coverage": 40, "penetration": 45, "interactions": [{ "id": "open", "label": "Open drawer" }, { "id": "examine", "label": "Examine" }] },
	"desk": { "name": "Desk", "shape": "rect", "size": Vector2(120, 50), "color": Color(0.4, 0.25, 0.1), "material": "wood", "art": "table", "art_opts": { "props": [{ "kind": "monitor", "at": Vector2(0.5, 0.22) }, { "kind": "keyboard", "at": Vector2(0.5, 0.62) }, { "kind": "mug", "at": Vector2(0.83, 0.55) }, { "kind": "papers", "at": Vector2(0.15, 0.5) }] }, "weight": 24, "coverage": 45, "penetration": 50, "interactions": [{ "id": "sit_at", "label": "Sit at desk", "move_to": true }, { "id": "examine", "label": "Examine" }] },
	"washing_machine": { "name": "Wash", "shape": "square", "size": Vector2(60, 60), "color": Color(0.9, 0.9, 0.9), "material": "metal", "art": "appliance", "art_opts": { "panel": "washer" }, "weight": 70, "coverage": 55, "penetration": 80 },
	"dryer": { "name": "Dryer", "shape": "square", "size": Vector2(60, 60), "color": Color(0.7, 0.7, 0.7), "material": "metal", "art": "appliance", "art_opts": { "panel": "dryer" }, "weight": 55, "coverage": 55, "penetration": 80 },
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

## Room floors, named by each recipe palette's `floor` (picked to contrast with the palette's
## furniture wood). Definition fields: art (a tiling painter), color, material, art_opts
## (`pattern`: planks/parquet/tiles/checker/mosaic/carpet/concrete; `alt` for checker).
const FLOORS := {
	"oak_planks": { "art": "floor", "color": Color(0.68, 0.52, 0.34), "material": "wood", "art_opts": { "pattern": "planks" } },
	"walnut_planks": { "art": "floor", "color": Color(0.4, 0.27, 0.17), "material": "wood", "art_opts": { "pattern": "planks" } },
	"ash_planks": { "art": "floor", "color": Color(0.8, 0.73, 0.6), "material": "wood", "art_opts": { "pattern": "planks" } },
	"grey_planks": { "art": "floor", "color": Color(0.58, 0.56, 0.52), "material": "wood", "art_opts": { "pattern": "planks" } },
	"parquet": { "art": "floor", "color": Color(0.62, 0.43, 0.26), "material": "wood", "art_opts": { "pattern": "parquet" } },
	"white_tile": { "art": "floor", "color": Color(0.88, 0.88, 0.86), "material": "ceramic", "art_opts": { "pattern": "tiles" } },
	"terracotta_tile": { "art": "floor", "color": Color(0.7, 0.42, 0.3), "material": "ceramic", "art_opts": { "pattern": "tiles" } },
	"slate_tile": { "art": "floor", "color": Color(0.4, 0.42, 0.45), "material": "stone", "art_opts": { "pattern": "tiles" } },
	"checker": { "art": "floor", "color": Color(0.88, 0.87, 0.84), "material": "ceramic", "art_opts": { "pattern": "checker", "alt": Color(0.22, 0.22, 0.24) } },
	"mosaic": { "art": "floor", "color": Color(0.55, 0.72, 0.78), "material": "ceramic", "art_opts": { "pattern": "mosaic" } },
	"beige_carpet": { "art": "floor", "color": Color(0.76, 0.7, 0.6), "material": "fabric", "art_opts": { "pattern": "carpet" } },
	"blue_carpet": { "art": "floor", "color": Color(0.48, 0.58, 0.72), "material": "fabric", "art_opts": { "pattern": "carpet" } },
	"green_carpet": { "art": "floor", "color": Color(0.5, 0.62, 0.5), "material": "fabric", "art_opts": { "pattern": "carpet" } },
	"concrete": { "art": "floor", "color": Color(0.55, 0.55, 0.53), "material": "stone", "art_opts": { "pattern": "concrete" } },
}

## The house wall style handed to WallFactory: a plaster cap (see ObjectArtConfig.wall_*).
const WALL := { "art": "wall", "color": Color(0.86, 0.84, 0.79), "art_opts": { "pattern": "plaster" } }

## Combined room types that pull arrangements from several categories.
const RECIPES := {
	"kitchen_living": {
		"palettes": [
			{ "wood": WOOD.oak, "fabric": FABRIC.terracotta, "floor": "checker" },
			{ "wood": WOOD.walnut, "fabric": FABRIC.cream, "floor": "white_tile" },
			{ "wood": WOOD.ash, "fabric": FABRIC.sage, "floor": "terracotta_tile" },
			{ "wood": WOOD.white, "fabric": FABRIC.navy, "floor": "slate_tile" },
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
			{ "wood": WOOD.oak, "fabric": FABRIC.terracotta, "floor": "walnut_planks" },
			{ "wood": WOOD.walnut, "fabric": FABRIC.cream, "floor": "ash_planks" },
			{ "wood": WOOD.ash, "fabric": FABRIC.sage, "floor": "grey_planks" },
		],
		"zones": [
			{ "options": ["tv_wall_cozy", "tv_wall_modern"], "count": Vector2i(1, 1), "required": true, "fallback": "tv_compact" },
			{ "options": ["cooking_line", "cooking_l_shape"], "count": Vector2i(1, 1), "required": true, "fallback": "cooking_compact" },
			{ "options": ["bed_single_nightstand", "bed_twin_nightstands"], "count": Vector2i(1, 1), "required": true, "fallback": "bed_compact" },
			{ "options": ["fridge_corner", "dining_set_2", "plant_corner"], "count": Vector2i(0, 2) },
		],
	},
}
