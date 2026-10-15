class_name WorldGen

## The World Generation domain's single entry point. Given a seed, an optional forced
## floorplan, and where the front entrance should land, it picks a plan, seeds one RNG for the
## whole run (the plan pick is its first draw, so a seed reproduces everything), and builds
## the house via HouseSpawner. Callers (Main) never touch HouseDefinitions/HouseSpawner
## directly — `generate`, `get_rooms`, `get_openings`, `get_wear`, `get_clutter`, `get_street`, `get_streetlights`,
## `annotate_layout` and the read-only catalogue lookups are the whole surface World-Gen exposes.

## Build a house and return its root Node2D (parented under `parent`). `rng_seed` of 0 picks a
## fresh random layout each run; `force_plan` ("" = random) pins a specific floorplan. Every
## doorway is an open archway; the house has one front entrance (on its south wall) and, in most
## floorplans, a back/side/garage exit.
static func generate(rng_seed: int, force_plan: String, front_entrance_world: Vector2, parent: Node) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else randi()
	var all_plans: Array = HouseDefinitions.get_all()
	var pick: String = all_plans[rng.randi() % all_plans.size()]
	var plan_key: String = force_plan if force_plan != "" else pick
	GameLog.say("House: %s  seed: %s" % [plan_key, rng.seed])
	return HouseSpawner.spawn(plan_key, front_entrance_world, rng, parent)


## Describe a hand-laid layout `root` the way a generated house describes itself, so `get_rooms`, `get_openings` and the
## nav builder read it unchanged. `rooms` are `{ key, type, rect }` in WORLD space; `doors` are `{ pos, width }` in world
## space, and a door on one room's wall only is the front entrance. For the Testing domain's arenas and room layouts.
static func annotate_layout(root: Node2D, rooms: Array, doors: Array = []) -> void:
	root.set_meta("rooms", rooms)
	var openings: Array = []
	for door in doors:
		var keys := HouseSpawner.room_keys_on(rooms, door)
		openings.append({ "pos": door["pos"], "width": door["width"], "front": keys.size() == 1, "exit": false, "rooms": keys })
	root.set_meta("openings", openings)


## The generated house's rooms as an Array of { key, type, rect } with `rect` in WORLD
## space. For callers (Main) that place entities into rooms; empty for a null house.
static func get_rooms(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("rooms", [])


## The generated house's doorways as an Array of { pos, width, front, exit, rooms } in WORLD space
## (`rooms` = keys of the rooms the doorway joins: two for an interior door, one for the front
## entrance or an `exit`). Empty for a null house.
static func get_openings(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("openings", [])


## The generated house's wear as an Array of { room, pos, layer }: one entry per wear cluster, `room` its room's key, `pos`
## its centre in WORLD space and `layer` the node drawing that room's wear (one per room). Empty for a null house or a
## hand-laid layout.
static func get_wear(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("wear", [])


## The generated house's clutter as an Array of { room, key, node }: one entry per walk-over piece its rooms were strewn
## with, `key` its catalogue key and `node` the placed piece. Empty for a null house or a hand-laid layout.
static func get_clutter(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("clutter", [])


## The street ring round a generated house as an Array of { kind, rect, node }: `kind` `street` or `sidewalk`, `rect` the
## piece's WORLD rect and `node` the floor that draws it (none of them a sound surface). Empty for a null house or a
## hand-laid layout.
static func get_street(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("street", [])


## The street lamps along the front of a generated house as an Array of { pos, node }: `pos` a lamp's centre in WORLD space,
## `node` the placed piece (a solid, anchored metal post, carved into the nav map, its arm and head overhead). None stands
## within the clearance of a front or exit doorway nor in the strip straight out of one. Empty for a null house or a
## hand-laid layout.
static func get_streetlights(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("streetlights", [])


## The catalogue object definition for `key` (a plain dict for ObjectFactory.spawn), or {} if
## unknown. For callers outside World-Gen (the Testing domain) that place single catalogue pieces.
static func object_definition(key: String) -> Dictionary:
	return ObjectDefinitions.get_definition(key)


## The catalogue floor definition for `key` (a plain dict for FloorFactory.spawn), or {} if unknown.
static func floor_definition(key: String) -> Dictionary:
	return GeneralCatalog.FLOORS.get(key, {})


## The house wall style (the `style` dict for WallFactory.spawn), so other builders match the house.
static func wall_style() -> Dictionary:
	return GeneralCatalog.WALL
