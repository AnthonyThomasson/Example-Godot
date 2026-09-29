class_name HomeOfficeCatalog

## Home-office objects, arrangements, and recipe. Shared items (desk, bookshelf,
## plant, and the reading_chair arrangement) live in GeneralCatalog.

const OBJECTS := {
	"office_chair": { "name": "Chair", "shape": "square", "size": Vector2(30, 30), "color": Color(0.2, 0.2, 0.24), "material": "plastic", "weight": 8, "coverage": 45, "penetration": 30, "interactions": [{ "id": "sit", "label": "Sit", "move_to": true }, { "id": "spin", "label": "Spin around", "move_to": true }] },
	"filing_cabinet": { "name": "Files", "shape": "rect", "size": Vector2(40, 50), "color": Color(0.55, 0.57, 0.6), "material": "metal", "weight": 30, "coverage": 55, "penetration": 75, "interactions": [{ "id": "open", "label": "Open files" }, { "id": "examine", "label": "Examine" }] },
}

const ARRANGEMENTS := {
	"desk_setup": {
		"placement": "wall", "footprint": Vector2(120, 95),
		"items": [
			{ "key": "desk", "pos": Vector2(60, 25) },
			{ "key": "office_chair", "pos": Vector2(60, 72) },
		],
	},
	"desk_compact": {
		"placement": "wall", "footprint": Vector2(124, 54),
		"items": [{ "key": "desk", "pos": Vector2(62, 27) }],
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
}

const RECIPES := {
	"home_office": {
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.slate },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.navy },
			{ "wood": GeneralCatalog.WOOD.charcoal, "fabric": GeneralCatalog.FABRIC.sage },
		],
		"zones": [
			{ "options": ["desk_setup"], "count": Vector2i(1, 1), "required": true, "fallback": "desk_compact" },
			{ "options": ["bookshelf_wall", "filing_corner"], "count": Vector2i(1, 2) },
			{ "options": ["reading_chair", "plant_corner"], "count": Vector2i(0, 1) },
		],
	},
}
