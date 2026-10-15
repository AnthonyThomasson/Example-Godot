class_name RipperdocCatalog

## World Generation domain: ripperdoc (chop shop) objects, arrangements and recipe: a room walked through (LayoutRules)
## where implants go in. The surgical chair between two instrument carts, steel shelves of cyberware on the walls.
## Shared pieces (a sink, storage, a lamp) live in GeneralCatalog.

const OBJECTS := {
	"surgical_chair": { "name": "Surgery", "shape": "rect", "size": Vector2(56, 112), "color": Color(0.75, 0.76, 0.78), "material": "metal", "art": "recliner", "art_opts": { "kind": "surgical" }, "weight": 80, "coverage": 45, "penetration": 60, "interactions": [{ "id": "lie", "label": "Lie down", "move_to": true }, { "id": "examine", "label": "Examine" }] },
	"tool_cart": { "name": "Cart", "shape": "rect", "size": Vector2(46, 32), "color": Color(0.72, 0.73, 0.75), "material": "metal", "art": "clinic", "art_opts": { "kind": "tool_cart" }, "weight": 18, "coverage": 45, "penetration": 55, "interactions": [{ "id": "examine", "label": "Examine" }] },
	"cyberware_shelf": { "name": "Cyberware", "shape": "rect", "size": Vector2(100, 34), "color": Color(0.55, 0.56, 0.6), "material": "metal", "art": "clinic", "art_opts": { "kind": "cyberware_shelf" }, "weight": 45, "coverage": 80, "penetration": 70, "interactions": [{ "id": "browse", "label": "Browse cyberware" }, { "id": "examine", "label": "Examine" }] },
}

const ARRANGEMENTS := {
	# The chair free-standing, a cart each side, turned to it.
	"surgery_bay": {
		"placement": "center", "footprint": Vector2(156, 112), "tags": ["surgery"],
		"items": [
			{ "key": "tool_cart", "pos": Vector2(23, 40), "facing": Vector2.RIGHT },
			{ "key": "surgical_chair", "pos": Vector2(78, 56) },
			{ "key": "tool_cart", "pos": Vector2(133, 72), "facing": Vector2.LEFT },
		],
	},
	"surgery_compact": {
		"placement": "wall", "footprint": Vector2(56, 112), "tags": ["surgery"],
		"items": [{ "key": "surgical_chair", "pos": Vector2(28, 56) }],
	},
	"cyberware_wall": {
		"placement": "wall", "footprint": Vector2(100, 34),
		"items": [{ "key": "cyberware_shelf", "pos": Vector2(50, 17) }],
	},
	"cart_corner": {
		"placement": "wall", "footprint": Vector2(46, 32), "prefer_corner": true,
		"items": [{ "key": "tool_cart", "pos": Vector2(23, 16) }],
	},
}

const RECIPES := {
	"ripperdoc": {
		"clutter": [["trash", 3.0], ["puddle", 2.0], ["cables", 1.5], ["cardboard", 1.0]],
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.white, "fabric": GeneralCatalog.FABRIC.aqua, "floor": "white_tile" },
			{ "wood": GeneralCatalog.WOOD.charcoal, "fabric": GeneralCatalog.FABRIC.slate, "floor": "checker" },
			{ "wood": GeneralCatalog.WOOD.ash, "fabric": GeneralCatalog.FABRIC.sage, "floor": "concrete" },
		],
		"zones": [
			{ "options": ["surgery_bay"], "count": Vector2i(1, 1), "required": true, "fallback": "surgery_compact" },
			{ "options": ["cyberware_wall"], "count": Vector2i(1, 2) },
			{ "options": ["cart_corner", "lamp_corner"], "count": Vector2i(0, 1) },
		],
		"fill": { "target": 0.3, "options": ["cyberware_wall", "cyberware_wall", "cart_corner", "storage_wall", "lamp_corner", "shelf_single"] },
	},
}
