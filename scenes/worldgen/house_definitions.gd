class_name HouseDefinitions

## World Generation domain: house floorplans, in house-local coordinates (walls run along the rect edges).
##   rooms: key, type (a recipe in ArrangementDefinitions), rect.
##   openings: `pos` is the doorway center ON a wall line; every room whose wall passes
##          through it gets that gap cut. Exactly one opening is `front` (the exterior
##          entrance the house is positioned by, on the south wall); a house may also have `exit`
##          openings (a back/side/garage door: exterior, on exactly one room's wall).
## What may connect to what (which rooms can hold the front door or an exit, which room types may
## share a door, which must be dead ends) is LayoutRules; HouseSpawner warns about a plan that breaks it
## and tests/worldgen/house_doorways_connected_test.gd fails on it. Bedrooms and bathrooms open off a
## hallway (or a living space); a bedroom-to-bathroom door is a private en-suite. The flats are run-down cyberpunk
## homes: the railroad, micro and corner flats carry the netrunner den, the ripperdoc, the security vestibule and the
## kitchenette between them.

const PLANS := {
	"starter_home": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 0, 520, 350) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(520, 0, 380, 350) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 350, 520, 350) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(520, 350, 380, 350) },
		],
		"openings": [
			{ "pos": Vector2(260, 700), "width": 110.0, "front": true },  # living room, exterior
			{ "pos": Vector2(900, 525), "width": 90.0, "exit": true },  # kitchen, side door
			{ "pos": Vector2(520, 525), "width": 100.0 },  # living room <-> kitchen
			{ "pos": Vector2(400, 350), "width": 100.0 },  # living room <-> bedroom
			{ "pos": Vector2(520, 175), "width": 90.0 },  # bedroom <-> bathroom (en-suite)
		],
	},
	"open_plan_home": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 0, 520, 350) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(520, 0, 380, 350) },
			{ "key": "great_room", "type": "kitchen_living", "rect": Rect2(0, 350, 900, 380) },
		],
		"openings": [
			{ "pos": Vector2(300, 730), "width": 120.0, "front": true },  # great room, exterior
			{ "pos": Vector2(900, 540), "width": 100.0, "exit": true },  # great room, patio door
			{ "pos": Vector2(400, 350), "width": 100.0 },  # great room <-> bedroom
			{ "pos": Vector2(520, 175), "width": 90.0 },  # bedroom <-> bathroom (en-suite)
		],
	},

	"studio_flat": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "studio", "type": "studio", "rect": Rect2(0, 0, 620, 480) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(620, 0, 300, 480) },
		],
		"openings": [
			{ "pos": Vector2(310, 480), "width": 110.0, "front": true },
			{ "pos": Vector2(620, 240), "width": 90.0 },  # studio <-> bathroom
		],
	},

	"one_bed_flat": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 0, 500, 340) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(500, 0, 300, 340) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 340, 400, 320) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(400, 340, 400, 320) },
		],
		"openings": [
			{ "pos": Vector2(200, 660), "width": 110.0, "front": true },  # living room, exterior
			{ "pos": Vector2(400, 500), "width": 100.0 },  # living <-> kitchen
			{ "pos": Vector2(200, 340), "width": 100.0 },  # living <-> bedroom
			{ "pos": Vector2(500, 170), "width": 90.0 },  # bedroom <-> bathroom (en-suite)
		],
	},

	"two_bed_flat": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 0, 300, 340) },
			{ "key": "bedroom_2", "type": "bedroom", "rect": Rect2(300, 0, 300, 340) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(600, 0, 200, 340) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 340, 440, 340) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(440, 340, 360, 340) },
		],
		"openings": [
			{ "pos": Vector2(220, 680), "width": 110.0, "front": true },  # living room, exterior
			{ "pos": Vector2(440, 510), "width": 100.0 },  # living <-> kitchen
			{ "pos": Vector2(150, 340), "width": 100.0 },  # living <-> bedroom
			{ "pos": Vector2(370, 340), "width": 100.0 },  # living <-> bedroom_2
			{ "pos": Vector2(600, 170), "width": 90.0 },  # bedroom_2 <-> bathroom (en-suite)
		],
	},

	"office_loft": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "great_room", "type": "kitchen_living", "rect": Rect2(0, 0, 660, 440) },
			{ "key": "home_office", "type": "home_office", "rect": Rect2(660, 0, 340, 240) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(660, 240, 340, 200) },
		],
		"openings": [
			{ "pos": Vector2(330, 440), "width": 120.0, "front": true },  # great room, exterior
			{ "pos": Vector2(660, 120), "width": 100.0 },  # great <-> office
			{ "pos": Vector2(660, 340), "width": 90.0 },  # great <-> bathroom
		],
	},

	"bungalow": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 0, 360, 320) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(360, 0, 240, 320) },
			{ "key": "laundry_room", "type": "laundry_room", "rect": Rect2(600, 0, 260, 320) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 320, 430, 340) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(430, 320, 430, 340) },
		],
		"openings": [
			{ "pos": Vector2(200, 660), "width": 110.0, "front": true },  # living room, exterior
			{ "pos": Vector2(860, 490), "width": 100.0, "exit": true },  # kitchen, back door
			{ "pos": Vector2(430, 490), "width": 100.0 },  # living <-> kitchen
			{ "pos": Vector2(180, 320), "width": 100.0 },  # living <-> bedroom
			{ "pos": Vector2(360, 160), "width": 90.0 },  # bedroom <-> bathroom (en-suite)
			{ "pos": Vector2(730, 320), "width": 90.0 },  # kitchen <-> laundry
		],
	},

	"garage_home": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "garage", "type": "garage", "rect": Rect2(0, 0, 420, 400) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(420, 0, 300, 400) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(720, 0, 280, 400) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(0, 400, 400, 360) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(400, 400, 600, 360) },
		],
		"openings": [
			{ "pos": Vector2(700, 760), "width": 120.0, "front": true },  # living, exterior
			{ "pos": Vector2(210, 0), "width": 120.0, "exit": true },  # garage, vehicle door
			{ "pos": Vector2(200, 400), "width": 100.0 },  # garage <-> kitchen
			{ "pos": Vector2(400, 580), "width": 100.0 },  # kitchen <-> living
			{ "pos": Vector2(570, 400), "width": 100.0 },  # living <-> bedroom
			{ "pos": Vector2(720, 200), "width": 90.0 },  # bedroom <-> bathroom (en-suite)
		],
	},

	# A railroad flat: four rooms in a row, each opening into the next through doorways that line up along their north
	# side, from the vestibule on the street to the netrunner's den at the far end.
	"railroad_flat": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "security_vestibule", "type": "security_vestibule", "rect": Rect2(0, 0, 260, 340) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(260, 0, 380, 340) },
			{ "key": "ripperdoc", "type": "ripperdoc", "rect": Rect2(640, 0, 360, 340) },
			{ "key": "netrunner_den", "type": "netrunner_den", "rect": Rect2(1000, 0, 340, 340) },
		],
		"openings": [
			{ "pos": Vector2(130, 340), "width": 110.0, "front": true },  # vestibule, exterior
			{ "pos": Vector2(260, 100), "width": 90.0 },  # vestibule <-> living room
			{ "pos": Vector2(640, 100), "width": 90.0 },  # living room <-> ripperdoc
			{ "pos": Vector2(1000, 100), "width": 90.0 },  # ripperdoc <-> den
		],
	},

	# A micro-flat: one studio, a tiny bathroom and a kitchenette off it.
	"micro_flat": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "studio", "type": "studio", "rect": Rect2(0, 0, 560, 460) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(560, 0, 260, 230) },
			{ "key": "kitchenette", "type": "kitchenette", "rect": Rect2(560, 230, 260, 230) },
		],
		"openings": [
			{ "pos": Vector2(280, 460), "width": 110.0, "front": true },  # studio, exterior
			{ "pos": Vector2(560, 115), "width": 90.0 },  # studio <-> bathroom
			{ "pos": Vector2(560, 345), "width": 90.0 },  # studio <-> kitchenette
		],
	},

	# A corner flat: the vestibule on the street opens onto a short inner hallway; the living room, bedroom, bathroom and
	# kitchenette are round it.
	"corner_flat": {
		"wall_thickness": 12.0,
		"rooms": [
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 0, 420, 340) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(420, 0, 340, 340) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(0, 340, 220, 320) },
			{ "key": "hallway", "type": "hallway", "rect": Rect2(220, 340, 540, 130) },
			{ "key": "security_vestibule", "type": "security_vestibule", "rect": Rect2(220, 470, 280, 190) },
			{ "key": "kitchenette", "type": "kitchenette", "rect": Rect2(500, 470, 260, 190) },
		],
		"openings": [
			{ "pos": Vector2(360, 660), "width": 110.0, "front": true },  # vestibule, exterior
			{ "pos": Vector2(360, 470), "width": 100.0 },  # vestibule <-> hallway
			{ "pos": Vector2(320, 340), "width": 90.0 },  # hallway <-> living room
			{ "pos": Vector2(620, 340), "width": 90.0 },  # hallway <-> bedroom
			{ "pos": Vector2(220, 405), "width": 80.0 },  # hallway <-> bathroom
			{ "pos": Vector2(630, 470), "width": 90.0 },  # hallway <-> kitchenette
		],
	},
}

## The floorplan for `key`, or {} if unknown.
static func get_plan(key: String) -> Dictionary:
	return PLANS.get(key, {})

## Every floorplan key.
static func get_all() -> Array:
	return PLANS.keys()
