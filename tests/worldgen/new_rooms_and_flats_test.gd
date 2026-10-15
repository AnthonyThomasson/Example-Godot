extends GameTest

## R11 and R12 (ticket #61): the houses become run-down cyberpunk flats. Retired: the floorplans luxury_home,
## family_home, dining_house and cottage, and the room types kids_room, entry_hall and dining_room with their catalogue
## pieces, arrangements, recipes and LayoutRules rows. New: four room types, the netrunner den (a dead-end private room),
## the ripperdoc (a through room), the security vestibule (may carry the front door) and the kitchenette, each with
## LayoutRules rows and links, a recipe and pieces of its own (each spawnable, with sane stats); and three flats, the
## railroad flat, the micro-flat (a studio, a bathroom and a kitchenette) and the corner flat (a short inner hallway
## and a vestibule), which between them use every new room type, and in which every room of a new type is furnished
## with its own pieces. That every floorplan passes LayoutRules and is walkable is house_doorways_connected's check,
## which covers the new flats with every other plan.

## The names the build gives the new room types and flats.
const NEW_TYPES := ["netrunner_den", "ripperdoc", "security_vestibule", "kitchenette"]
const NEW_PLANS := ["railroad_flat", "micro_flat", "corner_flat"]
## What R11 / R12 retire.
const RETIRED_PLANS := ["luxury_home", "family_home", "dining_house", "cottage"]
const RETIRED_TYPES := ["kids_room", "entry_hall", "dining_room"]
const RETIRED_PIECES := ["formal_table", "buffet", "china_cabinet", "kids_bed", "small_desk", "toy_chest"]
const RETIRED_ARRANGEMENTS := ["dining_formal", "buffet_wall", "china_corner", "kids_bed_zone", "kids_bed_compact", "play_area", "play_compact", "kids_books"]
## Every catalogue piece before phase 4 that stays: a piece a new room's recipe names that is not here is one of its own.
const KEPT_PIECES := [
	"armchair", "bath_mat", "bathtub", "bed", "bench", "bookshelf", "cabinet", "car", "chair", "coat_rack", "coffee_table",
	"console_table", "desk", "dining_table", "dresser", "dryer", "filing_cabinet", "fridge", "island", "kitchen_counter",
	"lamp", "laundry_sink", "linen_shelf", "microwave", "mirror", "nightstand", "office_chair", "plant", "rug", "rug_large",
	"runner", "shelving", "shoe_rack", "shower", "side_table", "sink", "sofa", "stove", "table", "toilet", "tool_chest",
	"towel_rack", "tv", "wardrobe", "washing_machine", "workbench", "trash", "cables", "cable_nest", "cardboard", "puddle",
	"neon_tube",
]
const MATERIALS := ["wood", "fabric", "metal", "glass", "ceramic", "stone", "plastic", "electronics", "foliage"]
const SHAPES := ["circle", "square", "rect"]
const SIZE_RANGE := Vector2(8, 400)  ## Each side of a piece's footprint, px.
const SEEDS := [1, 2, 3, 4]
const FAR := Vector2(6000, 6000)  ## Where single pieces are spawned, clear of the arena.


func describe() -> Dictionary:
	return {
		"name": "The new rooms and flats replace the old houses",
		"description": "The retired plans, room types, pieces and arrangements are gone; the netrunner den, ripperdoc, security vestibule and kitchenette have layout rules, links, recipes and pieces of their own (spawnable, sane stats); the railroad, micro and corner flats use every new room type and furnish each with its own pieces.",
		"tags": ["worldgen", "house", "layout", "furniture", "restyle"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## The room types of floorplan `plan` ([] when there is none).
func _types_of(plan: String) -> Array:
	var out: Array = []
	for room: Dictionary in HouseDefinitions.get_plan(plan).get("rooms", []):
		out.append(room["type"])
	return out


## Every arrangement key a recipe can place: its zones' options and fallbacks and its fill's options.
func _arrangements_of(recipe: Dictionary) -> Array:
	var out: Array = []
	for zone: Dictionary in recipe.get("zones", []):
		out.append_array(zone.get("options", []))
		if zone.has("fallback"):
			out.append(zone["fallback"])
	out.append_array((recipe.get("fill", {}) as Dictionary).get("options", []))
	return out


## The catalogue keys of the pieces a room type's recipe can place.
func _pieces_of(room_type: String) -> Array:
	var out: Array = []
	for key: String in _arrangements_of(ArrangementDefinitions.get_recipe(room_type)):
		for item: Dictionary in ArrangementDefinitions.get_arrangement(key).get("items", []):
			if not out.has(item["key"]):
				out.append(item["key"])
	return out


func run(t: TestContext) -> void:
	_check_retired(t)
	_check_rules(t)
	var own := _check_recipes(t)
	_check_pieces(t, own)
	_check_plans(t)
	_check_furnished(t, own)
	await t.frames(1)


## The retired plans, room types, pieces and arrangements are gone everywhere.
func _check_retired(t: TestContext) -> void:
	for plan: String in RETIRED_PLANS:
		t.check(HouseDefinitions.get_plan(plan).is_empty() and not HouseDefinitions.get_all().has(plan), "the %s floorplan is retired" % plan)
	for room_type: String in RETIRED_TYPES:
		t.check(ArrangementDefinitions.get_recipe(room_type).is_empty(), "the %s recipe is retired" % room_type)
		t.check(not LayoutRules.ROOMS.has(room_type), "LayoutRules.ROOMS has no %s row" % room_type)
		t.check(not LayoutRules.LINKS.any(func(pair: Array) -> bool: return pair.has(room_type)), "LayoutRules.LINKS names no %s" % room_type)
		for plan: String in HouseDefinitions.get_all():
			t.check(not _types_of(plan).has(room_type), "the %s floorplan has no %s" % [plan, room_type])
	for key: String in RETIRED_PIECES:
		t.check(WorldGen.object_definition(key).is_empty(), "the %s piece is retired from the catalogue" % key)
	for key: String in RETIRED_ARRANGEMENTS:
		t.check(ArrangementDefinitions.get_arrangement(key).is_empty(), "the %s arrangement is retired" % key)


## Each new room type has its LayoutRules row and links: the vestibule may carry the front door, the den is a private
## dead end, the ripperdoc is walked through.
func _check_rules(t: TestContext) -> void:
	for room_type: String in NEW_TYPES:
		t.check(LayoutRules.ROOMS.has(room_type), "LayoutRules.ROOMS has a %s row" % room_type)
		t.check(LayoutRules.LINKS.any(func(pair: Array) -> bool: return pair.has(room_type)), "LayoutRules.LINKS lets a %s share a door" % room_type)
	t.check(LayoutRules.rule("security_vestibule")["front"], "a security vestibule may carry the front door")
	var den := LayoutRules.rule("netrunner_den")
	t.check(not den["through"] and not den["front"], "a netrunner den is a private dead end (through %s, front %s)" % [den["through"], den["front"]])
	t.check(LayoutRules.rule("ripperdoc")["through"], "a ripperdoc may be walked through")


## Each new room type has a recipe with a required zone, every arrangement and piece it names exists, and some of its
## pieces are its own (not in the catalogue before). Returns room type -> its own piece keys.
func _check_recipes(t: TestContext) -> Dictionary:
	var own := {}
	for room_type: String in NEW_TYPES:
		own[room_type] = []
		var recipe := ArrangementDefinitions.get_recipe(room_type)
		if not t.check(not recipe.is_empty(), "the %s has a recipe" % room_type):
			continue
		t.check((recipe.get("zones", []) as Array).any(func(z: Dictionary) -> bool: return z.get("required", false)), "the %s recipe has a required zone" % room_type)
		for key: String in _arrangements_of(recipe):
			t.check(not ArrangementDefinitions.get_arrangement(key).is_empty(), "the %s recipe's arrangement %s exists" % [room_type, key])
		for key: String in _pieces_of(room_type):
			t.check(not WorldGen.object_definition(key).is_empty(), "the %s recipe's piece %s is in the catalogue" % [room_type, key])
			if not KEPT_PIECES.has(key):
				own[room_type].append(key)
		t.check(not (own[room_type] as Array).is_empty(), "the %s is furnished with pieces of its own (its recipe names %s)" % [room_type, _pieces_of(room_type)])
	return own


## Every new piece is a sane definition and spawns through ObjectFactory into a piece reporting the same surface.
func _check_pieces(t: TestContext, own: Dictionary) -> void:
	var seen := {}
	for room_type: String in own:
		for key: String in own[room_type]:
			if seen.has(key):
				continue
			seen[key] = true
			var def := WorldGen.object_definition(key)
			if def.is_empty():
				continue
			var size: Vector2 = def.get("size", Vector2.ZERO)
			var solid: bool = def.get("solid", true)
			var coverage: float = def.get("coverage", 0.0)
			var penetration: float = def.get("penetration", 0.0)
			t.check(String(def.get("name", "")) != "", "%s has a display name" % key)
			t.check(SHAPES.has(def.get("shape", "")), "%s has a shape (%s)" % [key, def.get("shape", "")])
			t.check(size.x >= SIZE_RANGE.x and size.y >= SIZE_RANGE.x and size.x <= SIZE_RANGE.y and size.y <= SIZE_RANGE.y, "%s has a sane size (%s)" % [key, size])
			t.check(MATERIALS.has(def.get("material", "")), "%s has a known material (%s)" % [key, def.get("material", "")])
			t.check(coverage >= 0.0 and coverage <= 100.0 and penetration >= 0.0 and penetration <= 100.0, "%s has coverage and penetration within 0-100 (%s, %s)" % [key, coverage, penetration])
			t.check(not solid or coverage > 0.0, "%s is solid, so it covers something (coverage %s)" % [key, coverage])
			t.check(float(def.get("weight", 0.0)) > 0.0, "%s has a weight" % key)
			t.check(String(def.get("art", "")) != "", "%s is drawn by a painter (art)" % key)
			var piece := ObjectFactory.spawn(def, FAR, t.world)
			if t.check(piece != null, "%s spawns through ObjectFactory" % key):
				var surface: Dictionary = piece.get_surface()
				t.check(surface["material"] == def.get("material", "") and is_equal_approx(surface["coverage"], coverage) and is_equal_approx(surface["penetration"], penetration),
					"a spawned %s reports its surface (%s)" % [key, surface])
				piece.free()


## The three new flats exist and between them use every new room type; the micro-flat is a studio, a bathroom and a
## kitchenette, the corner flat has an inner hallway and a security vestibule.
func _check_plans(t: TestContext) -> void:
	var used: Array = []
	for plan: String in NEW_PLANS:
		t.check(HouseDefinitions.get_all().has(plan), "the %s floorplan exists" % plan)
		used.append_array(_types_of(plan))
	for room_type: String in NEW_TYPES:
		t.check(used.has(room_type), "a new flat has a %s" % room_type)
	var micro := _types_of("micro_flat")
	for room_type: String in ["studio", "bathroom", "kitchenette"]:
		t.check(micro.has(room_type), "the micro-flat has a %s (it has %s)" % [room_type, micro])
	var corner := _types_of("corner_flat")
	for room_type: String in ["hallway", "security_vestibule"]:
		t.check(corner.has(room_type), "the corner flat has a %s (it has %s)" % [room_type, corner])


## In generated houses of every plan that has a new room type, each such room holds at least one of its own pieces. The
## houses are built under a node that is never in the tree: only the pieces' fields are read.
func _check_furnished(t: TestContext, own: Dictionary) -> void:
	var holder := Node2D.new()
	var rooms_seen := 0
	for plan: String in HouseDefinitions.get_all():
		if not _types_of(plan).any(func(room_type: String) -> bool: return NEW_TYPES.has(room_type)):
			continue
		for house_seed in SEEDS:
			var house := WorldGen.generate(house_seed, plan, FAR, holder)
			for room: Dictionary in WorldGen.get_rooms(house):
				if not NEW_TYPES.has(room["type"]):
					continue
				rooms_seen += 1
				var node := house.get_node_or_null(String(room["key"]).capitalize() + " Furniture")
				var found: Array = []
				if node:
					for piece in node.get_children():
						if piece.solid and _is_one_of(piece, own[room["type"]]):
							found.append(piece.object_name)
				t.check(not found.is_empty(), "%s seed %d: the %s (%s) holds one of its own pieces %s" % [plan, house_seed, room["key"], room["type"], own[room["type"]]])
			house.free()
	holder.free()
	t.check(rooms_seen > 0, "generated houses have rooms of the new types (%d checked)" % rooms_seen)


## Whether placed `piece` was made from one of the catalogue `keys` (its name, and its size either way round).
func _is_one_of(piece: Node, keys: Array) -> bool:
	for key: String in keys:
		var def := WorldGen.object_definition(key)
		var size: Vector2 = def.get("size", Vector2.ZERO)
		var placed: Vector2 = piece.size
		if piece.object_name == def.get("name", "") and (placed.is_equal_approx(size) or placed.is_equal_approx(Vector2(size.y, size.x))):
			return true
	return false
