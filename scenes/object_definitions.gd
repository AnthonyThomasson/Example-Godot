class_name ObjectDefinitions

const OBJECTS := {
	"table": {
		"name": "Table",
		"shape": "square",
		"size": Vector2(60, 60),
		"color": Color(0.6, 0.4, 0.2, 1),
	},
	"tv": {
		"name": "TV",
		"shape": "rect",
		"size": Vector2(80, 40),
		"color": Color(0.1, 0.1, 0.1, 1),
	},
	"sofa": {
		"name": "Sofa",
		"shape": "rect",
		"size": Vector2(120, 50),
		"color": Color(0.8, 0.4, 0.2, 1),
	},
	"lamp": {
		"name": "Lamp",
		"shape": "circle",
		"size": Vector2(20, 20),
		"color": Color(1, 1, 0.6, 1),
	},
	"bookshelf": {
		"name": "Books",
		"shape": "rect",
		"size": Vector2(40, 80),
		"color": Color(0.4, 0.2, 0, 1),
	},
	"sink": {
		"name": "Sink",
		"shape": "square",
		"size": Vector2(50, 50),
		"color": Color(0.7, 0.8, 0.9, 1),
	},
	"fridge": {
		"name": "Fridge",
		"shape": "rect",
		"size": Vector2(60, 100),
		"color": Color(0.9, 0.9, 0.95, 1),
	},
	"microwave": {
		"name": "Microwave",
		"shape": "square",
		"size": Vector2(40, 40),
		"color": Color(0.5, 0.5, 0.5, 1),
	},
	"toilet": {
		"name": "Toilet",
		"shape": "circle",
		"size": Vector2(30, 30),
		"color": Color(0.95, 0.95, 0.95, 1),
	},
	"bed": {
		"name": "Bed",
		"shape": "rect",
		"size": Vector2(120, 180),
		"color": Color(0.7, 0.3, 0.3, 1),
	},
	"nightstand": {
		"name": "Nightstand",
		"shape": "square",
		"size": Vector2(50, 50),
		"color": Color(0.6, 0.4, 0.2, 1),
	},
	"dresser": {
		"name": "Dresser",
		"shape": "rect",
		"size": Vector2(80, 40),
		"color": Color(0.5, 0.3, 0.1, 1),
	},
	"desk": {
		"name": "Desk",
		"shape": "rect",
		"size": Vector2(120, 50),
		"color": Color(0.4, 0.25, 0.1, 1),
	},
	"washing_machine": {
		"name": "Wash",
		"shape": "square",
		"size": Vector2(60, 60),
		"color": Color(0.9, 0.9, 0.9, 1),
	},
	"dryer": {
		"name": "Dryer",
		"shape": "square",
		"size": Vector2(60, 60),
		"color": Color(0.7, 0.7, 0.7, 1),
	},
	"bathtub": {
		"name": "Tub",
		"shape": "rect",
		"size": Vector2(100, 150),
		"color": Color(0.8, 0.8, 1.0, 1),
	},
	"kitchen_counter": {
		"name": "Counter",
		"shape": "rect",
		"size": Vector2(100, 50),
		"color": Color(0.8, 0.7, 0.6, 1),
	},
}

static func get_all() -> Array:
	return OBJECTS.keys()

static func get_definition(key: String) -> Dictionary:
	return OBJECTS.get(key, {})
