extends RefCounted

## Realistic layouts for the flanking tests (tests/ai/flank/ and tests/ai/entry/; not a test itself). Three buildings
## with rooms, walls, doorways, corridors and cover pieces in different areas, laid out with
## `TestSetup.layout`. Each map is a `static func` that fills a TestSetup, and its landmarks are consts, so
## a test names a place ("the hall door", "behind the island") instead of a raw coordinate.

# --- Terrace house -----------------------------------------------------------------------------
# Living room (north-west), kitchen (north-east) and a hallway along the south. The living room opens to
# the hall and to the kitchen, the kitchen to the hall and the hall to the garden through the front door,
# so every room can be reached two ways: the doorways make a loop (hall > kitchen > living room). A back
# door in the kitchen's east wall opens onto the back garden.
#
#   x 0 ........ 480 ........ 840
#   +----------+----------+       y 0
#   |  LIVING   )  KITCHEN |
#   |           |          |
#   +--[ ]------+---[ ]----+       y 360
#   [ HALL                 |       y 360-470, front door on the west end
#   +----------------------+

const HOUSE_LIVING := Rect2(0, 0, 480, 360)
const HOUSE_KITCHEN := Rect2(480, 0, 360, 360)
const HOUSE_HALL := Rect2(0, 360, 840, 110)
const HOUSE_BOUNDS := Rect2(0, 0, 840, 470)
## Doorways, on the wall centrelines.
const DOOR_LIVING_KITCHEN := Vector2(480, 150)
const DOOR_HALL_LIVING := Vector2(150, 360)
const DOOR_HALL_KITCHEN := Vector2(690, 360)
const DOOR_FRONT := Vector2(0, 415)
const DOOR_BACK := Vector2(840, 190)    # in the kitchen's east wall, to the back garden
## Places in the living room.
const LIVING_CENTRE := Vector2(260, 190)
## Places in the kitchen and the hall.
const KITCHEN_CENTRE := Vector2(660, 190)
const HALL_MIDDLE := Vector2(420, 415)
const GARDEN := Vector2(-110, 415)


## Lay out the terrace house: three rooms, four doorways and furniture in each room. `furnish` false
## leaves the rooms bare (a test that needs a clean line places its own pieces).
static func house(s: TestSetup, furnish := true) -> void:
	s.layout([
		{ "key": "living_room", "type": "living_room", "rect": HOUSE_LIVING, "floor": "oak_planks" },
		{ "key": "kitchen", "type": "kitchen", "rect": HOUSE_KITCHEN, "floor": "oak_planks" },
		{ "key": "hall", "type": "entry_hall", "rect": HOUSE_HALL, "floor": "oak_planks" },
	], [
		{ "pos": DOOR_LIVING_KITCHEN, "width": 90.0 },
		{ "pos": DOOR_HALL_LIVING, "width": 80.0 },
		{ "pos": DOOR_HALL_KITCHEN, "width": 80.0 },
		{ "pos": DOOR_FRONT, "width": 80.0 },
		{ "pos": DOOR_BACK, "width": 90.0 },
	])
	if not furnish:
		return
	s.object(&"sofa", "sofa", Vector2(330, 40))              # against the north wall
	s.object(&"bookshelf", "bookshelf", Vector2(28, 110))    # tall cover on the west wall
	s.object(&"coffee_table", "coffee_table", Vector2(330, 130))
	s.object(&"armchair", "armchair", Vector2(80, 310))      # south-west corner
	s.object(&"fridge", "fridge", Vector2(810, 45))          # kitchen corner
	s.object(&"island", "island", Vector2(650, 180))         # the kitchen's centre block
	s.object(&"counter", "kitchen_counter", Vector2(560, 36))
	s.object(&"cabinet", "cabinet", Vector2(470, 438))       # in the hall, cover along the south wall


# --- Box room ----------------------------------------------------------------------------------
# A corridor with one small room off its north side: a box 140 px square, barely three bodies across, so a team of
# three cannot take its corners (a "short" room, docs/tactical-entry.md E13). The corridor's west end is an outer door.
#
#        +------+          y 60
#        | BOX  |
#   +----+-[ ]--+--------+ y 200
#   [ CORRIDOR           | y 200-300, entrance on the west end
#   +-------------------+

const BOX_CORRIDOR := Rect2(0, 200, 600, 100)
const BOX_ROOM := Rect2(220, 60, 140, 140)
const DOOR_BOX := Vector2(290, 200)
const BOX_ENTRANCE := Vector2(0, 250)


## Lay out the box room: a bare corridor and the small room off it.
static func box_room(s: TestSetup) -> void:
	s.layout([
		{ "key": "corridor", "type": "entry_hall", "rect": BOX_CORRIDOR },
		{ "key": "box_room", "type": "bedroom", "rect": BOX_ROOM },
	], [
		{ "pos": DOOR_BOX, "width": 70.0 },
		{ "pos": BOX_ENTRANCE, "width": 80.0 },
	])


# --- Corridor spine ----------------------------------------------------------------------------
# One long corridor with three rooms off its north side and a dead end at the east. Left and right of
# anything standing in the corridor are walls; the only way to a side is through a room's door.
#
#   +----------+----------+----------+   y 0
#   |  ROOM A  |  ROOM B  |  ROOM C  |
#   +---[ ]----+---[ ]----+---[ ]----+   y 200
#   [ CORRIDOR                       |   y 200-300, entrance on the west end, dead end east
#   +--------------------------------+

const SPINE_CORRIDOR := Rect2(0, 200, 900, 100)
const SPINE_ROOM_A := Rect2(0, 0, 300, 200)
const SPINE_ROOM_B := Rect2(300, 0, 300, 200)
const SPINE_ROOM_C := Rect2(600, 0, 300, 200)
const DOOR_A := Vector2(150, 200)
const DOOR_B := Vector2(450, 200)
const DOOR_C := Vector2(750, 200)
const SPINE_ENTRANCE := Vector2(0, 250)
const CORRIDOR_DEAD_END := Vector2(850, 250)


## Lay out the corridor spine. `furnish` adds cover: a cabinet in the corridor's south side and a table in
## each room.
static func spine(s: TestSetup, furnish := true) -> void:
	s.layout([
		{ "key": "corridor", "type": "entry_hall", "rect": SPINE_CORRIDOR },
		{ "key": "room_a", "type": "bedroom", "rect": SPINE_ROOM_A },
		{ "key": "room_b", "type": "home_office", "rect": SPINE_ROOM_B },
		{ "key": "room_c", "type": "kitchen", "rect": SPINE_ROOM_C },
	], [
		{ "pos": DOOR_A, "width": 80.0 },
		{ "pos": DOOR_B, "width": 80.0 },
		{ "pos": DOOR_C, "width": 80.0 },
		{ "pos": SPINE_ENTRANCE, "width": 80.0 },
	])
	if not furnish:
		return
	s.object(&"cabinet", "cabinet", Vector2(330, 274))        # a cover piece on the corridor's south side
	s.object(&"desk", "desk", Vector2(450, 80))               # room B
	s.object(&"bed", "bed", Vector2(70, 100))                 # room A
	s.object(&"wardrobe", "wardrobe", Vector2(250, 30))
	s.object(&"island", "island", Vector2(750, 100))          # room C


# --- Warehouse ---------------------------------------------------------------------------------
# One big room with cover scattered in different areas: three shelving rows, a car, a bench, a
# counter and two solid pillars. No walls inside, so sides exist all round; what differs is what stands
# between a point and the target.
#
#   +------------------------------------------+   y 0
#   |  [car]          =====shelves=====   [pil] |
#   |                                  [counter]|
#   |    =====shelves=====                      |
#   |                     [pil]                 |
#   |                  =====shelves=====  [bench]|
#   +------------------------------------------+   y 700

const WAREHOUSE := Rect2(0, 0, 1000, 700)
const PILLAR := { "name": "Pillar", "shape": "circle", "size": Vector2(34, 34), "color": Color(0.5, 0.5, 0.52), "weight": 5000, "coverage": 100, "penetration": 100 }


## Lay out the warehouse. `furnish` false leaves it as an empty hall.
static func warehouse(s: TestSetup, furnish := true) -> void:
	s.layout([{ "key": "warehouse", "type": "garage", "rect": WAREHOUSE, "floor": "oak_planks" }])
	if not furnish:
		return
	s.object(&"car", "car", Vector2(110, 130))
	for i in 3:
		s.object(StringName("shelf_ne_%d" % i), "shelving", Vector2(560 + i * 100, 110))
		s.object(StringName("shelf_w_%d" % i), "shelving", Vector2(180 + i * 100, 270))
		s.object(StringName("shelf_s_%d" % i), "shelving", Vector2(480 + i * 100, 560))
	s.object(&"counter", "island", Vector2(880, 220))
	s.object(&"bench", "workbench", Vector2(880, 600))
	s.object(&"pillar_centre", PILLAR, Vector2(500, 420))
	s.object(&"pillar_east", PILLAR, Vector2(740, 400))
	s.object(&"tool_chest", "tool_chest", Vector2(120, 520))
