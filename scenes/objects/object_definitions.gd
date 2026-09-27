class_name ObjectDefinitions

## Object catalogue. Fields:
##   name, shape ("circle" | "square" | "rect"), size, color — required.
##   material — optional; "wood" or "fabric" objects take the room palette's tone.
##   solid    — optional (default true); false = walk-over decor drawn under everything.

const OBJECTS := {
	# --- Living room ---
	"tv": { "name": "TV", "shape": "rect", "size": Vector2(80, 30), "color": Color(0.1, 0.1, 0.1) },
	"sofa": { "name": "Sofa", "shape": "rect", "size": Vector2(120, 50), "color": Color(0.8, 0.4, 0.2), "material": "fabric" },
	"armchair": { "name": "Armchair", "shape": "square", "size": Vector2(50, 50), "color": Color(0.7, 0.45, 0.3), "material": "fabric" },
	"coffee_table": { "name": "Coffee", "shape": "rect", "size": Vector2(70, 40), "color": Color(0.55, 0.35, 0.2), "material": "wood" },
	"side_table": { "name": "Side", "shape": "square", "size": Vector2(30, 30), "color": Color(0.55, 0.35, 0.2), "material": "wood" },
	"bookshelf": { "name": "Books", "shape": "rect", "size": Vector2(40, 80), "color": Color(0.4, 0.2, 0.0), "material": "wood" },
	"lamp": { "name": "Lamp", "shape": "circle", "size": Vector2(20, 20), "color": Color(1.0, 1.0, 0.6) },
	"plant": { "name": "Plant", "shape": "circle", "size": Vector2(26, 26), "color": Color(0.25, 0.6, 0.3) },
	"coat_rack": { "name": "Coats", "shape": "circle", "size": Vector2(24, 24), "color": Color(0.45, 0.3, 0.15), "material": "wood" },
	"shoe_rack": { "name": "Shoes", "shape": "rect", "size": Vector2(60, 25), "color": Color(0.45, 0.3, 0.15), "material": "wood" },
	"rug": { "name": "Rug", "shape": "rect", "size": Vector2(170, 110), "color": Color(0.6, 0.35, 0.35), "material": "fabric", "solid": false },

	# --- Kitchen / dining ---
	"table": { "name": "Table", "shape": "square", "size": Vector2(60, 60), "color": Color(0.6, 0.4, 0.2), "material": "wood" },
	"dining_table": { "name": "Dining", "shape": "rect", "size": Vector2(90, 60), "color": Color(0.6, 0.4, 0.2), "material": "wood" },
	"chair": { "name": "Chair", "shape": "square", "size": Vector2(28, 28), "color": Color(0.5, 0.33, 0.18), "material": "wood" },
	"kitchen_counter": { "name": "Counter", "shape": "rect", "size": Vector2(100, 50), "color": Color(0.8, 0.7, 0.6) },
	"island": { "name": "Island", "shape": "rect", "size": Vector2(110, 55), "color": Color(0.8, 0.7, 0.6) },
	"stove": { "name": "Stove", "shape": "square", "size": Vector2(50, 50), "color": Color(0.2, 0.2, 0.22) },
	"sink": { "name": "Sink", "shape": "square", "size": Vector2(50, 50), "color": Color(0.7, 0.8, 0.9) },
	"fridge": { "name": "Fridge", "shape": "rect", "size": Vector2(60, 70), "color": Color(0.9, 0.9, 0.95) },
	"microwave": { "name": "Micro", "shape": "square", "size": Vector2(40, 40), "color": Color(0.5, 0.5, 0.5) },
	"cabinet": { "name": "Cabinet", "shape": "rect", "size": Vector2(50, 35), "color": Color(0.55, 0.35, 0.2), "material": "wood" },

	# --- Bedroom ---
	"bed": { "name": "Bed", "shape": "rect", "size": Vector2(120, 180), "color": Color(0.7, 0.3, 0.3), "material": "fabric" },
	"nightstand": { "name": "Night", "shape": "square", "size": Vector2(40, 40), "color": Color(0.6, 0.4, 0.2), "material": "wood" },
	"dresser": { "name": "Dresser", "shape": "rect", "size": Vector2(80, 40), "color": Color(0.5, 0.3, 0.1), "material": "wood" },
	"wardrobe": { "name": "Wardrobe", "shape": "rect", "size": Vector2(90, 45), "color": Color(0.45, 0.28, 0.12), "material": "wood" },
	"desk": { "name": "Desk", "shape": "rect", "size": Vector2(120, 50), "color": Color(0.4, 0.25, 0.1), "material": "wood" },

	# --- Bathroom / laundry ---
	"toilet": { "name": "Toilet", "shape": "circle", "size": Vector2(34, 34), "color": Color(0.95, 0.95, 0.95) },
	"bathtub": { "name": "Tub", "shape": "rect", "size": Vector2(100, 150), "color": Color(0.8, 0.8, 1.0) },
	"shower": { "name": "Shower", "shape": "square", "size": Vector2(80, 80), "color": Color(0.75, 0.85, 0.95) },
	"towel_rack": { "name": "Towels", "shape": "rect", "size": Vector2(50, 14), "color": Color(0.6, 0.6, 0.65) },
	"bath_mat": { "name": "Mat", "shape": "rect", "size": Vector2(70, 40), "color": Color(0.5, 0.65, 0.75), "material": "fabric", "solid": false },
	"washing_machine": { "name": "Wash", "shape": "square", "size": Vector2(60, 60), "color": Color(0.9, 0.9, 0.9) },
	"dryer": { "name": "Dryer", "shape": "square", "size": Vector2(60, 60), "color": Color(0.7, 0.7, 0.7) },
	"laundry_sink": { "name": "Sink", "shape": "square", "size": Vector2(45, 45), "color": Color(0.72, 0.8, 0.88) },

	# --- Dining room ---
	"formal_table": { "name": "Table", "shape": "rect", "size": Vector2(110, 70), "color": Color(0.5, 0.32, 0.18), "material": "wood" },
	"buffet": { "name": "Buffet", "shape": "rect", "size": Vector2(120, 40), "color": Color(0.5, 0.32, 0.18), "material": "wood" },
	"china_cabinet": { "name": "China", "shape": "rect", "size": Vector2(70, 40), "color": Color(0.48, 0.3, 0.16), "material": "wood" },

	# --- Home office ---
	"office_chair": { "name": "Chair", "shape": "square", "size": Vector2(30, 30), "color": Color(0.2, 0.2, 0.24) },
	"filing_cabinet": { "name": "Files", "shape": "rect", "size": Vector2(40, 50), "color": Color(0.55, 0.57, 0.6) },

	# --- Kids room ---
	"kids_bed": { "name": "Bed", "shape": "rect", "size": Vector2(80, 140), "color": Color(0.4, 0.6, 0.85), "material": "fabric" },
	"toy_chest": { "name": "Toys", "shape": "rect", "size": Vector2(55, 38), "color": Color(0.9, 0.55, 0.25), "material": "wood" },
	"small_desk": { "name": "Desk", "shape": "rect", "size": Vector2(80, 40), "color": Color(0.45, 0.3, 0.15), "material": "wood" },

	# --- Entry hall ---
	"console_table": { "name": "Console", "shape": "rect", "size": Vector2(90, 28), "color": Color(0.5, 0.34, 0.2), "material": "wood" },
	"bench": { "name": "Bench", "shape": "rect", "size": Vector2(80, 30), "color": Color(0.55, 0.4, 0.25), "material": "wood" },
	"mirror": { "name": "Mirror", "shape": "rect", "size": Vector2(44, 12), "color": Color(0.7, 0.82, 0.85) },

	# --- Garage ---
	"car": { "name": "Car", "shape": "rect", "size": Vector2(130, 220), "color": Color(0.55, 0.12, 0.12) },
	"workbench": { "name": "Bench", "shape": "rect", "size": Vector2(110, 45), "color": Color(0.5, 0.38, 0.25), "material": "wood" },
	"shelving": { "name": "Shelves", "shape": "rect", "size": Vector2(95, 30), "color": Color(0.55, 0.55, 0.58) },
	"tool_chest": { "name": "Tools", "shape": "rect", "size": Vector2(45, 40), "color": Color(0.7, 0.15, 0.15) },
}

static func get_all() -> Array:
	return OBJECTS.keys()

static func get_definition(key: String) -> Dictionary:
	return OBJECTS.get(key, {})
