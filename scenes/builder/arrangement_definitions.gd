class_name ArrangementDefinitions

## Furniture arrangements ("zones") and per-room-type recipes used by RoomFurnisher.
##
## An arrangement is authored in a local frame AS IF PLACED AGAINST THE TOP WALL:
##   x runs along the wall (0..footprint.x), y is depth into the room (0..footprint.y).
## Item `pos` is the item's center. `rotated` swaps an item's width/height (90° turn).
## The furnisher rotates the whole frame onto whichever wall it picks, and may mirror it.
##
##   placement:     "wall" (backed against a wall) or "center" (free-standing).
##   prefer_corner: try the ends of a wall first.
##   tags:          an arrangement is skipped if a room already placed one with a
##                  shared tag (e.g. only one "fridge" per kitchen).

const ARRANGEMENTS := {
	# ---------------- Living room ----------------
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
	"reading_nook": {
		"placement": "wall", "footprint": Vector2(130, 95), "prefer_corner": true,
		"tags": ["reading"],
		"items": [
			{ "key": "bookshelf", "pos": Vector2(40, 20), "rotated": true },
			{ "key": "armchair", "pos": Vector2(100, 68) },
			{ "key": "lamp", "pos": Vector2(60, 70) },
		],
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
	"plant_corner": {
		"placement": "wall", "footprint": Vector2(30, 30), "prefer_corner": true,
		"items": [{ "key": "plant", "pos": Vector2(15, 15) }],
	},

	# ---------------- Kitchen ----------------
	"cooking_line": {
		"placement": "wall", "footprint": Vector2(306, 50),
		"items": [
			{ "key": "kitchen_counter", "pos": Vector2(50, 25) },
			{ "key": "stove", "pos": Vector2(127, 25) },
			{ "key": "sink", "pos": Vector2(179, 25) },
			{ "key": "kitchen_counter", "pos": Vector2(256, 25) },
		],
	},
	"cooking_l_shape": {
		"placement": "wall", "footprint": Vector2(275, 70), "prefer_corner": true,
		"tags": ["fridge"],
		"items": [
			{ "key": "fridge", "pos": Vector2(30, 35) },
			{ "key": "kitchen_counter", "pos": Vector2(115, 25) },
			{ "key": "stove", "pos": Vector2(195, 25) },
			{ "key": "sink", "pos": Vector2(250, 25) },
		],
	},
	"dining_set_4": {
		"placement": "center", "footprint": Vector2(110, 130),
		"items": [
			{ "key": "dining_table", "pos": Vector2(55, 65) },
			{ "key": "chair", "pos": Vector2(32, 15) },
			{ "key": "chair", "pos": Vector2(78, 15) },
			{ "key": "chair", "pos": Vector2(32, 115) },
			{ "key": "chair", "pos": Vector2(78, 115) },
		],
	},
	"dining_set_2": {
		"placement": "center", "footprint": Vector2(70, 120),
		"items": [
			{ "key": "table", "pos": Vector2(35, 60) },
			{ "key": "chair", "pos": Vector2(35, 14) },
			{ "key": "chair", "pos": Vector2(35, 106) },
		],
	},
	"island_stools": {
		"placement": "center", "footprint": Vector2(110, 90),
		"items": [
			{ "key": "island", "pos": Vector2(55, 28) },
			{ "key": "chair", "pos": Vector2(30, 75) },
			{ "key": "chair", "pos": Vector2(80, 75) },
		],
	},
	"fridge_corner": {
		"placement": "wall", "footprint": Vector2(60, 70), "prefer_corner": true,
		"tags": ["fridge"],
		"items": [{ "key": "fridge", "pos": Vector2(30, 35) }],
	},
	"pantry": {
		"placement": "wall", "footprint": Vector2(95, 40),
		"items": [
			{ "key": "cabinet", "pos": Vector2(25, 18) },
			{ "key": "microwave", "pos": Vector2(73, 20) },
		],
	},

	# ---------------- Bedroom ----------------
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
	"wardrobe_wall": {
		"placement": "wall", "footprint": Vector2(180, 45),
		"items": [
			{ "key": "wardrobe", "pos": Vector2(45, 23) },
			{ "key": "dresser", "pos": Vector2(135, 20) },
		],
	},
	"work_desk": {
		"placement": "wall", "footprint": Vector2(150, 95),
		"items": [
			{ "key": "desk", "pos": Vector2(60, 25) },
			{ "key": "chair", "pos": Vector2(60, 72) },
			{ "key": "lamp", "pos": Vector2(140, 15) },
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

	# ---------------- Bathroom ----------------
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
	"toilet_zone": {
		"placement": "wall", "footprint": Vector2(90, 40),
		"items": [
			{ "key": "toilet", "pos": Vector2(20, 20) },
			{ "key": "towel_rack", "pos": Vector2(65, 7) },
		],
	},
	"vanity": {
		"placement": "wall", "footprint": Vector2(110, 50),
		"items": [
			{ "key": "sink", "pos": Vector2(25, 25) },
			{ "key": "cabinet", "pos": Vector2(82, 18) },
		],
	},
	"laundry_pair": {
		"placement": "wall", "footprint": Vector2(125, 60), "prefer_corner": true,
		"items": [
			{ "key": "washing_machine", "pos": Vector2(30, 30) },
			{ "key": "dryer", "pos": Vector2(95, 30) },
		],
	},
	"laundry_sink": {
		"placement": "wall", "footprint": Vector2(100, 45),
		"items": [
			{ "key": "laundry_sink", "pos": Vector2(23, 23) },
			{ "key": "cabinet", "pos": Vector2(74, 18) },
		],
	},

	# ---------------- Dining room ----------------
	"dining_formal": {
		"placement": "center", "footprint": Vector2(190, 150),
		"items": [
			{ "key": "formal_table", "pos": Vector2(95, 75) },
			{ "key": "chair", "pos": Vector2(65, 22) },
			{ "key": "chair", "pos": Vector2(125, 22) },
			{ "key": "chair", "pos": Vector2(65, 128) },
			{ "key": "chair", "pos": Vector2(125, 128) },
			{ "key": "chair", "pos": Vector2(18, 75) },
			{ "key": "chair", "pos": Vector2(172, 75) },
		],
	},
	"buffet_wall": {
		"placement": "wall", "footprint": Vector2(120, 40),
		"items": [{ "key": "buffet", "pos": Vector2(60, 20) }],
	},
	"china_corner": {
		"placement": "wall", "footprint": Vector2(70, 40), "prefer_corner": true,
		"items": [{ "key": "china_cabinet", "pos": Vector2(35, 20) }],
	},

	# ---------------- Home office ----------------
	"desk_setup": {
		"placement": "wall", "footprint": Vector2(120, 95),
		"items": [
			{ "key": "desk", "pos": Vector2(60, 25) },
			{ "key": "office_chair", "pos": Vector2(60, 72) },
		],
	},
	"bookshelf_wall": {
		"placement": "wall", "footprint": Vector2(170, 40),
		"items": [
			{ "key": "bookshelf", "pos": Vector2(45, 20), "rotated": true },
			{ "key": "bookshelf", "pos": Vector2(125, 20), "rotated": true },
		],
	},
	"filing_corner": {
		"placement": "wall", "footprint": Vector2(40, 50), "prefer_corner": true,
		"items": [{ "key": "filing_cabinet", "pos": Vector2(20, 25) }],
	},

	# ---------------- Kids room ----------------
	"kids_bed_zone": {
		"placement": "wall", "footprint": Vector2(130, 140), "prefer_corner": true,
		"items": [
			{ "key": "kids_bed", "pos": Vector2(40, 70) },
			{ "key": "nightstand", "pos": Vector2(110, 20) },
		],
	},
	"play_area": {
		"placement": "wall", "footprint": Vector2(160, 75),
		"items": [
			{ "key": "toy_chest", "pos": Vector2(30, 19) },
			{ "key": "small_desk", "pos": Vector2(110, 20) },
			{ "key": "chair", "pos": Vector2(110, 55) },
		],
	},
	"kids_books": {
		"placement": "wall", "footprint": Vector2(80, 40), "prefer_corner": true,
		"items": [{ "key": "bookshelf", "pos": Vector2(40, 20), "rotated": true }],
	},

	# ---------------- Entry hall ----------------
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

	# ---------------- Garage ----------------
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

	# ---------------- Compact fallbacks (used only when a required zone can't fit) ----------------
	"bed_compact": {
		"placement": "wall", "footprint": Vector2(124, 184), "prefer_corner": true,
		"items": [{ "key": "bed", "pos": Vector2(62, 92) }],
	},
	"wardrobe_compact": {
		"placement": "wall", "footprint": Vector2(94, 49), "prefer_corner": true,
		"items": [{ "key": "wardrobe", "pos": Vector2(47, 24) }],
	},
	"vanity_compact": {
		"placement": "wall", "footprint": Vector2(54, 54), "prefer_corner": true,
		"items": [{ "key": "sink", "pos": Vector2(27, 27) }],
	},
	"toilet_compact": {
		"placement": "wall", "footprint": Vector2(40, 40), "prefer_corner": true,
		"items": [{ "key": "toilet", "pos": Vector2(20, 20) }],
	},
	"shower_compact": {
		"placement": "wall", "footprint": Vector2(84, 84), "prefer_corner": true,
		"items": [{ "key": "shower", "pos": Vector2(42, 42) }],
	},
	"kids_bed_compact": {
		"placement": "wall", "footprint": Vector2(84, 144), "prefer_corner": true,
		"items": [{ "key": "kids_bed", "pos": Vector2(42, 72) }],
	},
	"play_compact": {
		"placement": "wall", "footprint": Vector2(59, 42), "prefer_corner": true,
		"items": [{ "key": "toy_chest", "pos": Vector2(29, 20) }],
	},
	"dining_compact": {
		"placement": "wall", "footprint": Vector2(64, 64), "prefer_corner": true,
		"items": [{ "key": "table", "pos": Vector2(32, 32) }],
	},
	"desk_compact": {
		"placement": "wall", "footprint": Vector2(124, 54),
		"items": [{ "key": "desk", "pos": Vector2(62, 27) }],
	},
	"cooking_compact": {
		"placement": "wall", "footprint": Vector2(108, 54),
		"items": [
			{ "key": "stove", "pos": Vector2(27, 27) },
			{ "key": "sink", "pos": Vector2(81, 27) },
		],
	},
	"tv_compact": {
		"placement": "wall", "footprint": Vector2(124, 60),
		"items": [
			{ "key": "tv", "pos": Vector2(62, 18) },
			{ "key": "sofa", "pos": Vector2(62, 45) },
		],
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

## Recipes: `zones` are filled in order. Each zone picks `count` (min..max) distinct
## arrangements from `options`; `required` zones warn if nothing could be placed.
## One palette is picked per room and applied to every "wood"/"fabric" object.
const RECIPES := {
	"living_room": {
		"palettes": [
			{ "wood": WOOD.walnut, "fabric": FABRIC.navy },
			{ "wood": WOOD.oak, "fabric": FABRIC.terracotta },
			{ "wood": WOOD.ash, "fabric": FABRIC.sage },
			{ "wood": WOOD.charcoal, "fabric": FABRIC.mustard },
		],
		"zones": [
			{ "options": ["tv_wall_cozy", "tv_wall_modern"], "count": Vector2i(1, 1), "required": true, "fallback": "tv_compact" },
			{ "options": ["reading_nook", "entry_area"], "count": Vector2i(1, 2) },
			{ "options": ["plant_corner", "side_table_lamp"], "count": Vector2i(0, 2) },
		],
	},
	"kitchen": {
		"palettes": [
			{ "wood": WOOD.oak, "fabric": FABRIC.cream },
			{ "wood": WOOD.white, "fabric": FABRIC.sage },
			{ "wood": WOOD.walnut, "fabric": FABRIC.terracotta },
		],
		"zones": [
			{ "options": ["cooking_line", "cooking_l_shape"], "count": Vector2i(1, 1), "required": true, "fallback": "cooking_compact" },
			{ "options": ["fridge_corner"], "count": Vector2i(1, 1) },
			{ "options": ["dining_set_4", "dining_set_2", "island_stools"], "count": Vector2i(1, 1), "required": true, "fallback": "dining_compact" },
			{ "options": ["pantry", "plant_corner"], "count": Vector2i(0, 2) },
		],
	},
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
	"bedroom": {
		"palettes": [
			{ "wood": WOOD.white, "fabric": FABRIC.blush },
			{ "wood": WOOD.cherry, "fabric": FABRIC.cream },
			{ "wood": WOOD.oak, "fabric": FABRIC.slate },
			{ "wood": WOOD.walnut, "fabric": FABRIC.sage },
		],
		"zones": [
			{ "options": ["bed_twin_nightstands", "bed_single_nightstand"], "count": Vector2i(1, 1), "required": true, "fallback": "bed_compact" },
			{ "options": ["wardrobe_wall"], "count": Vector2i(1, 1), "required": true, "fallback": "wardrobe_compact" },
			{ "options": ["work_desk", "reading_chair"], "count": Vector2i(1, 2) },
			{ "options": ["plant_corner"], "count": Vector2i(0, 1) },
		],
	},
	"bathroom": {
		"palettes": [
			{ "wood": WOOD.white, "fabric": FABRIC.aqua },
			{ "wood": WOOD.ash, "fabric": FABRIC.slate },
			{ "wood": WOOD.charcoal, "fabric": FABRIC.cream },
		],
		"zones": [
			{ "options": ["bath_tub_zone", "shower_zone"], "count": Vector2i(1, 1), "required": true, "fallback": "shower_compact" },
			{ "options": ["toilet_zone"], "count": Vector2i(1, 1), "required": true, "fallback": "toilet_compact" },
			{ "options": ["vanity"], "count": Vector2i(1, 1), "required": true, "fallback": "vanity_compact" },
			{ "options": ["laundry_pair", "plant_corner"], "count": Vector2i(0, 1) },
		],
	},
	"dining_room": {
		"palettes": [
			{ "wood": WOOD.walnut, "fabric": FABRIC.cream },
			{ "wood": WOOD.cherry, "fabric": FABRIC.navy },
			{ "wood": WOOD.oak, "fabric": FABRIC.sage },
		],
		"zones": [
			{ "options": ["dining_formal"], "count": Vector2i(1, 1), "required": true, "fallback": "dining_compact" },
			{ "options": ["buffet_wall", "china_corner"], "count": Vector2i(1, 2) },
			{ "options": ["plant_corner", "side_table_lamp"], "count": Vector2i(0, 2) },
		],
	},
	"home_office": {
		"palettes": [
			{ "wood": WOOD.walnut, "fabric": FABRIC.slate },
			{ "wood": WOOD.oak, "fabric": FABRIC.navy },
			{ "wood": WOOD.charcoal, "fabric": FABRIC.sage },
		],
		"zones": [
			{ "options": ["desk_setup"], "count": Vector2i(1, 1), "required": true, "fallback": "desk_compact" },
			{ "options": ["bookshelf_wall", "filing_corner"], "count": Vector2i(1, 2) },
			{ "options": ["reading_chair", "plant_corner"], "count": Vector2i(0, 1) },
		],
	},
	"kids_room": {
		"palettes": [
			{ "wood": WOOD.ash, "fabric": FABRIC.aqua },
			{ "wood": WOOD.white, "fabric": FABRIC.mustard },
			{ "wood": WOOD.oak, "fabric": FABRIC.blush },
		],
		"zones": [
			{ "options": ["kids_bed_zone"], "count": Vector2i(1, 1), "required": true, "fallback": "kids_bed_compact" },
			{ "options": ["play_area"], "count": Vector2i(1, 1), "required": true, "fallback": "play_compact" },
			{ "options": ["kids_books", "plant_corner"], "count": Vector2i(0, 1) },
		],
	},
	"entry_hall": {
		"palettes": [
			{ "wood": WOOD.walnut, "fabric": FABRIC.terracotta },
			{ "wood": WOOD.oak, "fabric": FABRIC.sage },
		],
		"zones": [
			{ "options": ["console_wall", "bench_coats"], "count": Vector2i(1, 2), "required": true },
			{ "options": ["plant_corner", "entry_area"], "count": Vector2i(0, 1) },
		],
	},
	"laundry_room": {
		"palettes": [
			{ "wood": WOOD.white, "fabric": FABRIC.slate },
			{ "wood": WOOD.ash, "fabric": FABRIC.aqua },
		],
		"zones": [
			{ "options": ["laundry_pair"], "count": Vector2i(1, 1), "required": true },
			{ "options": ["laundry_sink"], "count": Vector2i(1, 1) },
			{ "options": ["plant_corner"], "count": Vector2i(0, 1) },
		],
	},
	"garage": {
		"palettes": [
			{ "wood": WOOD.charcoal, "fabric": FABRIC.slate },
			{ "wood": WOOD.walnut, "fabric": FABRIC.navy },
		],
		"zones": [
			{ "options": ["car_bay"], "count": Vector2i(1, 1), "required": true },
			{ "options": ["workbench_wall"], "count": Vector2i(1, 1), "required": true },
			{ "options": ["garage_shelf"], "count": Vector2i(0, 2) },
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

static func get_arrangement(key: String) -> Dictionary:
	return ARRANGEMENTS.get(key, {})

static func get_recipe(room_type: String) -> Dictionary:
	return RECIPES.get(room_type, {})
