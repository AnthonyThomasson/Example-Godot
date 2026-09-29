class_name WorldGen

## The World Generation domain's single entry point. Given a seed, an optional forced
## floorplan, and where the front door should land, it picks a plan, seeds one RNG for the
## whole run (the plan pick is its first draw, so a seed reproduces everything), and builds
## the house via HouseSpawner. Callers (Main) never touch HouseDefinitions/HouseSpawner
## directly — this is the whole surface World-Gen exposes.

## Build a house and return its root Node2D (parented under `parent`). `seed` of 0 picks a
## fresh random layout each run; `force_plan` ("" = random) pins a specific floorplan.
static func generate(seed: int, force_plan: String, front_door_world: Vector2, parent: Node) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else randi()
	var all_plans: Array = HouseDefinitions.get_all()
	var pick: String = all_plans[rng.randi() % all_plans.size()]
	var plan_key: String = force_plan if force_plan != "" else pick
	print("House: ", plan_key, "  seed: ", rng.seed)
	return HouseSpawner.spawn(plan_key, front_door_world, rng, parent)
