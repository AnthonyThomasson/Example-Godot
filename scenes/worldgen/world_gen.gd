class_name WorldGen

## The World Generation domain's single entry point. Given a seed, an optional forced
## floorplan, and where the front entrance should land, it picks a plan, seeds one RNG for the
## whole run (the plan pick is its first draw, so a seed reproduces everything), and builds
## the house via HouseSpawner. Callers (Main) never touch HouseDefinitions/HouseSpawner
## directly — this is the whole surface World-Gen exposes (plus read-only catalogue lookups).

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
