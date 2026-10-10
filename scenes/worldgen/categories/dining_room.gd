class_name DiningRoomCatalog

## Dining-room objects, arrangements, and recipe. Shared items (chair, plant,
## side_table_lamp) live in GeneralCatalog.

const OBJECTS := {
	"formal_table": { "name": "Table", "shape": "rect", "size": Vector2(110, 70), "color": Color(0.5, 0.32, 0.18), "material": "wood", "art": "table", "art_opts": { "runner": true }, "weight": 45, "coverage": 45, "penetration": 55, "interactions": [{ "id": "sit_at", "label": "Sit at table", "move_to": true }, { "id": "examine", "label": "Examine" }] },
	"buffet": { "name": "Buffet", "shape": "rect", "size": Vector2(120, 40), "color": Color(0.5, 0.32, 0.18), "material": "wood", "art": "cabinet", "art_opts": { "front": "doors", "count": 3, "props": [{ "kind": "fruit_bowl", "at": Vector2(0.5, 0.5) }, { "kind": "vase", "at": Vector2(0.12, 0.45) }] }, "weight": 50, "coverage": 40, "penetration": 55, "interactions": [{ "id": "open", "label": "Open buffet" }, { "id": "examine", "label": "Examine" }] },
	"china_cabinet": { "name": "China", "shape": "rect", "size": Vector2(70, 40), "color": Color(0.48, 0.3, 0.16), "material": "wood", "art": "cabinet", "art_opts": { "front": "doors", "count": 2, "top": "glass", "crown": true }, "weight": 45, "coverage": 75, "penetration": 50, "interactions": [{ "id": "open", "label": "Open cabinet" }, { "id": "examine", "label": "Examine" }] },
}

const ARRANGEMENTS := {
	"dining_formal": {
		"placement": "center", "footprint": Vector2(190, 150),
		"items": [
			{ "key": "formal_table", "pos": Vector2(95, 75) },
			{ "key": "chair", "pos": Vector2(65, 22) },
			{ "key": "chair", "pos": Vector2(125, 22) },
			{ "key": "chair", "pos": Vector2(65, 128), "facing": Vector2.UP },
			{ "key": "chair", "pos": Vector2(125, 128), "facing": Vector2.UP },
			{ "key": "chair", "pos": Vector2(18, 75), "facing": Vector2.RIGHT },
			{ "key": "chair", "pos": Vector2(172, 75), "facing": Vector2.LEFT },
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
}

const RECIPES := {
	"dining_room": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.cream, "floor": "parquet" },
			{ "wood": GeneralCatalog.WOOD.cherry, "fabric": GeneralCatalog.FABRIC.navy, "floor": "ash_planks" },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.sage, "floor": "walnut_planks" },
		],
		"zones": [
			{ "options": ["dining_formal"], "count": Vector2i(1, 1), "required": true, "fallback": "dining_compact" },
			{ "options": ["buffet_wall", "china_corner"], "count": Vector2i(1, 2) },
			{ "options": ["plant_corner", "side_table_lamp"], "count": Vector2i(0, 2) },
		],
	},
}
