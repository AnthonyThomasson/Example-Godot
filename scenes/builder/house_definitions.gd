class_name HouseDefinitions

## House floorplans, in house-local coordinates (walls run along the rect edges).
##   rooms: key, type (a recipe in ArrangementDefinitions), rect.
##   doors: `pos` is the doorway center ON a wall line; every room whose wall passes
##          through it gets that gap cut. Exactly one door is `front` (the exterior
##          entrance the house is positioned by).

const PLANS := {
	"starter_home": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 0, 520, 350) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(520, 0, 380, 350) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 350, 520, 350) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(520, 350, 380, 350) },
		],
		"doors": [
			{ "pos": Vector2(260, 700), "width": 110.0, "front": true },  # living room, exterior
			{ "pos": Vector2(520, 525), "width": 100.0 },  # living room <-> kitchen
			{ "pos": Vector2(400, 350), "width": 100.0 },  # living room <-> bedroom
			{ "pos": Vector2(520, 175), "width": 90.0 },  # bedroom <-> bathroom (en-suite)
		],
	},
	"open_plan_home": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 0, 520, 350) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(520, 0, 380, 350) },
			{ "key": "great_room", "type": "kitchen_living", "rect": Rect2(0, 350, 900, 380) },
		],
		"doors": [
			{ "pos": Vector2(300, 730), "width": 120.0, "front": true },  # great room, exterior
			{ "pos": Vector2(400, 350), "width": 100.0 },  # great room <-> bedroom
			{ "pos": Vector2(520, 175), "width": 90.0 },  # bedroom <-> bathroom (en-suite)
		],
	},

	"studio_flat": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "studio", "type": "studio", "rect": Rect2(0, 0, 620, 480) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(620, 0, 300, 480) },
		],
		"doors": [
			{ "pos": Vector2(310, 480), "width": 110.0, "front": true },
			{ "pos": Vector2(620, 240), "width": 90.0 },  # studio <-> bathroom
		],
	},

	"one_bed_flat": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 0, 400, 340) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(400, 0, 400, 340) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 340, 400, 320) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(400, 340, 400, 320) },
		],
		"doors": [
			{ "pos": Vector2(200, 660), "width": 110.0, "front": true },  # bedroom, exterior
			{ "pos": Vector2(400, 170), "width": 100.0 },  # living <-> kitchen
			{ "pos": Vector2(200, 340), "width": 100.0 },  # living <-> bedroom
			{ "pos": Vector2(400, 500), "width": 100.0 },  # bedroom <-> bathroom
			{ "pos": Vector2(600, 340), "width": 100.0 },  # kitchen <-> bathroom
		],
	},

	"two_bed_flat": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 0, 440, 340) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(440, 0, 360, 340) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 340, 300, 340) },
			{ "key": "bedroom_2", "type": "bedroom", "rect": Rect2(300, 340, 300, 340) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(600, 340, 200, 340) },
		],
		"doors": [
			{ "pos": Vector2(150, 680), "width": 110.0, "front": true },  # bedroom, exterior
			{ "pos": Vector2(440, 170), "width": 100.0 },  # living <-> kitchen
			{ "pos": Vector2(150, 340), "width": 100.0 },  # living <-> bedroom
			{ "pos": Vector2(520, 340), "width": 100.0 },  # kitchen <-> bedroom_2
			{ "pos": Vector2(700, 340), "width": 90.0 },  # kitchen <-> bathroom
			{ "pos": Vector2(300, 510), "width": 90.0 },  # bedroom <-> bedroom_2
			{ "pos": Vector2(600, 510), "width": 90.0 },  # bedroom_2 <-> bathroom
		],
	},

	"family_home": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "entry_hall", "type": "entry_hall", "rect": Rect2(0, 0, 260, 300) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(260, 0, 380, 300) },
			{ "key": "bedroom_2", "type": "bedroom", "rect": Rect2(640, 0, 360, 300) },
			{ "key": "great_room", "type": "kitchen_living", "rect": Rect2(0, 300, 640, 420) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(640, 300, 360, 210) },
			{ "key": "kids_room", "type": "kids_room", "rect": Rect2(640, 510, 360, 210) },
		],
		"doors": [
			{ "pos": Vector2(300, 720), "width": 120.0, "front": true },  # great room, exterior
			{ "pos": Vector2(130, 300), "width": 100.0 },  # entry <-> great
			{ "pos": Vector2(260, 150), "width": 100.0 },  # entry <-> bedroom
			{ "pos": Vector2(640, 150), "width": 100.0 },  # bedroom <-> bedroom_2
			{ "pos": Vector2(640, 405), "width": 100.0 },  # great <-> bathroom
			{ "pos": Vector2(820, 300), "width": 90.0 },  # bedroom_2 <-> bathroom
			{ "pos": Vector2(820, 510), "width": 90.0 },  # bathroom <-> kids_room
		],
	},

	"office_loft": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "great_room", "type": "kitchen_living", "rect": Rect2(0, 0, 660, 440) },
			{ "key": "home_office", "type": "home_office", "rect": Rect2(660, 0, 340, 240) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(660, 240, 340, 200) },
		],
		"doors": [
			{ "pos": Vector2(330, 440), "width": 120.0, "front": true },  # great room, exterior
			{ "pos": Vector2(660, 120), "width": 100.0 },  # great <-> office
			{ "pos": Vector2(660, 340), "width": 90.0 },  # great <-> bathroom
			{ "pos": Vector2(830, 240), "width": 90.0 },  # office <-> bathroom
		],
	},

	"dining_house": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 0, 450, 340) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(450, 0, 450, 340) },
			{ "key": "dining_room", "type": "dining_room", "rect": Rect2(0, 340, 340, 360) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(340, 340, 340, 360) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(680, 340, 220, 360) },
		],
		"doors": [
			{ "pos": Vector2(170, 700), "width": 110.0, "front": true },  # dining, exterior
			{ "pos": Vector2(450, 170), "width": 100.0 },  # living <-> kitchen
			{ "pos": Vector2(170, 340), "width": 100.0 },  # living <-> dining
			{ "pos": Vector2(565, 340), "width": 100.0 },  # kitchen <-> bedroom
			{ "pos": Vector2(790, 340), "width": 90.0 },  # kitchen <-> bathroom
			{ "pos": Vector2(340, 520), "width": 90.0 },  # dining <-> bedroom
			{ "pos": Vector2(680, 520), "width": 90.0 },  # bedroom <-> bathroom
		],
	},

	"bungalow": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "living_room", "type": "living_room", "rect": Rect2(0, 0, 430, 340) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(430, 0, 430, 340) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(0, 340, 360, 320) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(360, 340, 260, 320) },
			{ "key": "laundry_room", "type": "laundry_room", "rect": Rect2(620, 340, 240, 320) },
		],
		"doors": [
			{ "pos": Vector2(180, 660), "width": 110.0, "front": true },  # bedroom, exterior
			{ "pos": Vector2(430, 170), "width": 100.0 },  # living <-> kitchen
			{ "pos": Vector2(180, 340), "width": 100.0 },  # living <-> bedroom
			{ "pos": Vector2(525, 340), "width": 100.0 },  # kitchen <-> bathroom
			{ "pos": Vector2(740, 340), "width": 90.0 },  # kitchen <-> laundry
			{ "pos": Vector2(360, 500), "width": 90.0 },  # bedroom <-> bathroom
			{ "pos": Vector2(620, 500), "width": 90.0 },  # bathroom <-> laundry
		],
	},

	"garage_home": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "garage", "type": "garage", "rect": Rect2(0, 0, 420, 400) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(420, 0, 300, 400) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(720, 0, 280, 400) },
			{ "key": "kitchen", "type": "kitchen", "rect": Rect2(0, 400, 400, 360) },
			{ "key": "living_room", "type": "living_room", "rect": Rect2(400, 400, 600, 360) },
		],
		"doors": [
			{ "pos": Vector2(700, 760), "width": 120.0, "front": true },  # living, exterior
			{ "pos": Vector2(200, 400), "width": 100.0 },  # garage <-> kitchen
			{ "pos": Vector2(420, 200), "width": 90.0 },  # garage <-> bedroom
			{ "pos": Vector2(720, 200), "width": 90.0 },  # bedroom <-> bathroom
			{ "pos": Vector2(570, 400), "width": 100.0 },  # living <-> bedroom
			{ "pos": Vector2(860, 400), "width": 90.0 },  # living <-> bathroom
			{ "pos": Vector2(400, 580), "width": 100.0 },  # kitchen <-> living
		],
	},

	"cottage": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "great_room", "type": "kitchen_living", "rect": Rect2(0, 0, 600, 440) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(600, 0, 340, 240) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(600, 240, 340, 200) },
		],
		"doors": [
			{ "pos": Vector2(300, 440), "width": 120.0, "front": true },  # great room, exterior
			{ "pos": Vector2(600, 120), "width": 100.0 },  # great <-> bedroom
			{ "pos": Vector2(600, 340), "width": 90.0 },  # great <-> bathroom
			{ "pos": Vector2(770, 240), "width": 90.0 },  # bedroom <-> bathroom
		],
	},

	"luxury_home": {
		"wall_thickness": 24.0,
		"rooms": [
			{ "key": "entry_hall", "type": "entry_hall", "rect": Rect2(0, 0, 260, 340) },
			{ "key": "bedroom", "type": "bedroom", "rect": Rect2(260, 0, 360, 340) },
			{ "key": "bedroom_2", "type": "bedroom", "rect": Rect2(620, 0, 360, 340) },
			{ "key": "bathroom", "type": "bathroom", "rect": Rect2(980, 0, 220, 340) },
			{ "key": "great_room", "type": "kitchen_living", "rect": Rect2(0, 340, 620, 440) },
			{ "key": "dining_room", "type": "dining_room", "rect": Rect2(620, 340, 300, 440) },
			{ "key": "home_office", "type": "home_office", "rect": Rect2(920, 340, 280, 200) },
			{ "key": "bathroom_2", "type": "bathroom", "rect": Rect2(920, 540, 280, 240) },
		],
		"doors": [
			{ "pos": Vector2(310, 780), "width": 120.0, "front": true },  # great room, exterior
			{ "pos": Vector2(130, 340), "width": 100.0 },  # entry <-> great
			{ "pos": Vector2(260, 170), "width": 100.0 },  # entry <-> bedroom
			{ "pos": Vector2(620, 170), "width": 100.0 },  # bedroom <-> bedroom_2
			{ "pos": Vector2(980, 170), "width": 90.0 },  # bedroom_2 <-> bathroom
			{ "pos": Vector2(620, 560), "width": 100.0 },  # great <-> dining
			{ "pos": Vector2(780, 340), "width": 100.0 },  # bedroom_2 <-> dining
			{ "pos": Vector2(920, 440), "width": 90.0 },  # dining <-> office
			{ "pos": Vector2(1060, 540), "width": 90.0 },  # office <-> bathroom_2
		],
	},
}

static func get_plan(key: String) -> Dictionary:
	return PLANS.get(key, {})

static func get_all() -> Array:
	return PLANS.keys()
