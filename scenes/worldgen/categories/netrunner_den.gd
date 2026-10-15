class_name NetrunnerDenCatalog

## World Generation domain: netrunner-den objects, arrangements and recipe: a dead-end private room (LayoutRules) where a
## netrunner jacks in. A bank of monitors on the wall with the rig reclined in front of it, server racks humming in a
## corner, and cable nests strewn over the floor (its clutter). Shared pieces (shelves, a lamp, a rug) live in GeneralCatalog.

const OBJECTS := {
	"monitor_wall": { "name": "Monitors", "shape": "rect", "size": Vector2(150, 40), "color": Color(0.22, 0.22, 0.25), "material": "electronics", "art": "tech", "art_opts": { "kind": "monitor_wall" }, "weight": 40, "coverage": 60, "penetration": 40, "interactions": [{ "id": "hack", "label": "Hack in" }, { "id": "examine", "label": "Examine" }] },
	"recliner_rig": { "name": "Rig", "shape": "rect", "size": Vector2(56, 100), "color": Color(0.3, 0.2, 0.3), "material": "fabric", "art": "recliner", "art_opts": { "kind": "rig" }, "weight": 45, "coverage": 45, "penetration": 30, "interactions": [{ "id": "lie", "label": "Jack in", "move_to": true }, { "id": "examine", "label": "Examine" }] },
	"server_rack": { "name": "Servers", "shape": "rect", "size": Vector2(44, 60), "color": Color(0.3, 0.3, 0.34), "material": "metal", "art": "tech", "art_opts": { "kind": "server_rack" }, "weight": 120, "coverage": 95, "penetration": 85, "interactions": [{ "id": "examine", "label": "Examine" }] },
}

const ARRANGEMENTS := {
	# The screens on the wall and the rig reclined in front of them, its head toward the room (it faces the screens).
	"netrunner_station": {
		"placement": "wall", "footprint": Vector2(150, 146), "tags": ["station"],
		"items": [
			{ "key": "monitor_wall", "pos": Vector2(75, 20) },
			{ "key": "recliner_rig", "pos": Vector2(75, 96), "facing": Vector2.UP },
		],
	},
	"monitor_compact": {
		"placement": "wall", "footprint": Vector2(150, 40), "tags": ["station"],
		"items": [{ "key": "monitor_wall", "pos": Vector2(75, 20) }],
	},
	"server_pair": {
		"placement": "wall", "footprint": Vector2(94, 60), "prefer_corner": true, "tags": ["servers"],
		"items": [
			{ "key": "server_rack", "pos": Vector2(22, 30) },
			{ "key": "server_rack", "pos": Vector2(72, 30) },
		],
	},
	"server_single": {
		"placement": "wall", "footprint": Vector2(44, 60), "prefer_corner": true,
		"items": [{ "key": "server_rack", "pos": Vector2(22, 30) }],
	},
}

const RECIPES := {
	"netrunner_den": {
		"clutter": [["cable_nest", 4.0], ["cables", 3.0], ["trash", 1.5], ["cardboard", 1.0]],
		"palettes": [
			{ "wood": GeneralCatalog.WOOD.charcoal, "fabric": GeneralCatalog.FABRIC.slate, "floor": "blue_carpet" },
			{ "wood": GeneralCatalog.WOOD.walnut, "fabric": GeneralCatalog.FABRIC.navy, "floor": "concrete" },
			{ "wood": GeneralCatalog.WOOD.oak, "fabric": GeneralCatalog.FABRIC.terracotta, "floor": "grey_planks" },
		],
		"zones": [
			{ "options": ["netrunner_station"], "count": Vector2i(1, 1), "required": true, "fallback": "monitor_compact" },
			{ "options": ["server_pair", "server_single"], "count": Vector2i(1, 1), "required": true, "fallback": "server_single" },
			{ "options": ["shelf_single", "lamp_corner"], "count": Vector2i(0, 1) },
		],
		"fill": { "target": 0.3, "options": ["server_single", "server_single", "shelf_single", "storage_wall", "lamp_corner", "rug_small"] },
	},
}
