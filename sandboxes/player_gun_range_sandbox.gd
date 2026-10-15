extends GameTest

## A sandbox to play: you are the player in a furnished arena with every gun — pistol (3), SMG (5) and assault rifle
## (6) — plus fists (2), a few target dummies, and walls and furniture to press the barrel against. Nothing is
## asserted — compare the guns' fire rate (hold LMB for the automatics), damage and penetration (the rifle shoots
## through the east wall at the dummy behind it), see how each is held, and walk the rifle or SMG up to a wall or
## the chair to watch it come up and stop firing.
##
## South of that is the armour range (docs/outfits.md): a firing line of nine numbered lanes, each ending at a dummy
## dressed in one outfit — plain clothes, a helmet, the tactical vest, the plate carrier empty and with each plate, the
## invaders' whole kit turned away and a ceramic carrier turned side on. Stand on a lane's mark and shoot its dummy to
## see what each outfit stops and lets through, watch a plate wear down, and compare a plate's front with its back
## (lane 8) and with a shot that takes it in the flank (lane 9). The label on the floor under each dummy keeps its
## outfit (the debug panel's wording), plate condition and health current. A shoved dummy walks back to its spot.

const OutfitLines := preload("res://scenes/ui/hud/outfit_lines.gd")

const ARENA := Rect2(-680, 0, 1680, 1300)
## The firing line's y, and the y of the dummies at the end of its lanes (the labels sit under them, by the south wall).
const FIRE_Y := 780.0
const DUMMY_Y := 1120.0
## The first lane's x and the gap between lanes: wide enough that no label runs into the next.
const LANE_X := -560.0
const LANE_GAP := 180.0
const DUMMY_HEALTH := 1000.0

## The lineup, lane by lane: what it is, what it wears and which way it faces (the firing line is north of it).
const LANES := [
	{ "title": "Plain clothes", "facing": Vector2.UP,
		"outfit": { "body": &"tshirt", "pants": &"jeans", "feet": &"shoes" } },
	{ "title": "Helmet + t-shirt", "facing": Vector2.UP,
		"outfit": { "head": &"helmet", "body": &"tshirt", "pants": &"jeans", "feet": &"shoes" } },
	{ "title": "Tactical vest", "facing": Vector2.UP,
		"outfit": { "body": &"tshirt", "vest": &"tactical_vest", "pants": &"jeans", "feet": &"shoes" } },
	{ "title": "Carrier, no plates", "facing": Vector2.UP,
		"outfit": { "body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes" } },
	{ "title": "Carrier + soft IIIA", "facing": Vector2.UP,
		"outfit": { "body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
			"front_plate": &"soft_iiia", "back_plate": &"soft_iiia" } },
	{ "title": "Carrier + steel III", "facing": Vector2.UP,
		"outfit": { "body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
			"front_plate": &"steel_iii", "back_plate": &"steel_iii" } },
	{ "title": "Carrier + ceramic IV", "facing": Vector2.UP,
		"outfit": { "body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
			"front_plate": &"ceramic_iv", "back_plate": &"ceramic_iv" } },
	{ "title": "Invader kit, back turned", "note": "shots strike the back plate", "facing": Vector2.DOWN,
		"outfit": { "head": &"helmet", "body": &"shirt", "vest": &"plate_carrier", "pants": &"tactical_pants", "feet": &"boots",
			"front_plate": &"steel_iii", "back_plate": &"steel_iii" } },
	{ "title": "Ceramic IV, side on", "note": "shots strike the flank", "facing": Vector2.RIGHT,
		"outfit": { "body": &"tshirt", "vest": &"plate_carrier", "pants": &"jeans", "feet": &"shoes",
			"front_plate": &"ceramic_iv", "back_plate": &"ceramic_iv" } },
]


func describe() -> Dictionary:
	return {
		"name": "Gun range",
		"description": "Player-controlled sandbox: WASD to move, mouse to aim, LMB to fire (hold it for the SMG and rifle), R to reload, F to punch, V to kick, 2 fists, 3 pistol, 5 SMG, 6 rifle. Press a long gun against a wall or a chair to see it raised. South of it, the armour range: nine lanes off a firing line, each dummy (1000 health) in one outfit — plain clothes, helmet, tactical vest, plate carrier empty and with soft IIIA, steel III or ceramic IV, the invader kit turned away (back plate) and a ceramic carrier side on (flank). Shoot each from its lane mark, watch its plates wear on the floor label and compare front, back and flank.",
		"tags": ["sandbox", "player", "gun", "pistol", "smg", "rifle", "outfit", "armour", "plate"],
		"manual": true,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA, { "floor": "concrete" })
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })
	s.actor(&"dummy_a", &"puppet", Vector2(700, 200), { "max_health": 200.0, "faction": &"dummy" })
	s.actor(&"dummy_b", &"puppet", Vector2(760, 440), { "max_health": 200.0, "faction": &"dummy" })
	# Just outside the east wall: only the rifle's rounds reach it.
	s.actor(&"dummy_behind_wall", &"puppet", Vector2(1040, 320), { "max_health": 200.0, "faction": &"dummy" })
	s.object(&"chair", "chair", Vector2(420, 200))
	s.object(&"armchair", "armchair", Vector2(460, 460))
	for i in LANES.size():
		var home := _home(i)
		var facing: Vector2 = LANES[i]["facing"]
		s.actor(_lane_id(i), &"puppet", home, { "max_health": DUMMY_HEALTH, "faction": &"dummy",
			"facing": facing, "aim_point": home + facing * 300.0 })
	s.camera_follow([&"you"])


## Dress the lineup, hold each dummy's facing with its puppet's aim, and lay a station (lane mark and floor label) under each.
func run(t: TestContext) -> void:
	for i in LANES.size():
		var lane: Dictionary = LANES[i]
		var dummy := t.actor(_lane_id(i))
		dummy.set_outfit(lane["outfit"])
		var home := _home(i)
		var puppet := t.puppet(_lane_id(i))
		puppet.aim_at(home + (lane["facing"] as Vector2) * 300.0)
		var station := Station.new()
		station.name = "Lane%dStation" % (i + 1)
		station.setup(dummy, puppet, i + 1, lane)
		t.world.add_child(station)
		station.global_position = home


## Where lane `i`'s dummy stands.
static func _home(i: int) -> Vector2:
	return Vector2(LANE_X + LANE_GAP * i, DUMMY_Y)


## The actor id of lane `i`'s dummy.
static func _lane_id(i: int) -> StringName:
	return StringName("lane_%d" % (i + 1))


## One lane's floor markings, drawn at its dummy's spot: the lane's mark on the firing line, and under the dummy its number
## and title, its outfit (`OutfitLines`, the debug panel's wording, the slots worn), its plate condition and its health, kept
## current. It also walks the dummy back to its spot once a hit has shoved it off.
class Station extends Node2D:
	const FONT_SIZE := 8
	const SHARP := 2.0          ## The text is rasterised this many times larger and drawn scaled down, so it stays crisp zoomed in.
	const LINE := 10.0          ## px between lines.
	const TEXT_TOP := 26.0      ## px under the dummy's centre where the label starts.
	const DRIFT := 8.0          ## px off its spot before a dummy walks back.
	const TEXT := Color(0.92, 0.92, 0.86)
	const MUTED := Color(0.72, 0.74, 0.70)
	const MARK := Color(0.95, 0.80, 0.30)

	var _dummy: Node2D
	var _puppet: Node
	var _number := 0
	var _lane: Dictionary
	var _lines: Array[String] = []

	func setup(dummy: Node2D, puppet: Node, number: int, lane: Dictionary) -> void:
		_dummy = dummy
		_puppet = puppet
		_number = number
		_lane = lane
		z_index = -1  # on the floor, under the bodies

	func _physics_process(_delta: float) -> void:
		if not is_instance_valid(_dummy):
			return
		var lines := _text()
		if lines != _lines:
			_lines = lines
			queue_redraw()
		if not _dummy.is_dead and _puppet.has_arrived() and _dummy.global_position.distance_to(global_position) > DRIFT:
			_puppet.walk_to(global_position)

	## The label's lines: the lane's number and title, its note, the outfit worn and the dummy's health.
	func _text() -> Array[String]:
		var out: Array[String] = ["%d. %s" % [_number, _lane["title"]]]
		if _lane.has("note"):
			out.append("(%s)" % _lane["note"])
		for line in OutfitLines.of(_dummy.outfit_view()):
			if not line.ends_with(": —"):
				out.append(line)
		out.append("Dead" if _dummy.is_dead else "Health: %d / %d" % [ceili(_dummy.health), roundi(_dummy.max_health)])
		return out

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		# The lane's mark on the firing line, straight up the lane from the dummy.
		var mark := Vector2(0, FIRE_Y - global_position.y)
		draw_line(mark + Vector2(-14, 0), mark + Vector2(14, 0), MARK, 2.0)
		draw_line(mark + Vector2(0, -6), mark + Vector2(0, 6), MARK, 2.0)
		_say(font, mark + Vector2(0, -10), str(_number), MARK, FONT_SIZE + 4)
		for i in _lines.size():
			_say(font, Vector2(0, TEXT_TOP + LINE * i), _lines[i], TEXT if i == 0 or _lines[i].begins_with("Health") else MUTED, FONT_SIZE)

	## Draw `text` centred across `at` (its baseline at `at.y`), outlined, rasterised `SHARP` times larger and scaled down so it stays crisp zoomed in.
	func _say(font: Font, at: Vector2, text: String, color: Color, size: int) -> void:
		var big := roundi(size * SHARP)
		var left := at * SHARP - Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x * 0.5, 0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / SHARP)
		draw_string_outline(font, left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, roundi(3 * SHARP), Color(0, 0, 0, 0.85))
		draw_string(font, left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, color)
		draw_set_transform(Vector2.ZERO)
