class_name BloodSpawner

const BloodPool = preload("res://scenes/physics/blood_pool.gd")
const BloodPoolVisuals = preload("res://scenes/physics/blood_pool_visuals.gd")


## Spawn one blood pool at world point `position`, spilling its burst of particles roughly along
## `direction`, added under `parent` (placed by global position, so `parent` may be offset from the
## world origin). `exclude` is the wounded body's RID(s), so its own collider never traps the blood,
## and `source` is that body — drops emerge from its live position, so a moving body trails blood.
## The pool is Despawner-tracked and persists until the cap frees it.
static func spawn(position: Vector2, direction: Vector2, parent: Node, exclude: Array, source: Node2D) -> void:
	var pool := Node2D.new()
	pool.name = "BloodPool"
	pool.script = BloodPool

	var visuals := Node2D.new()
	visuals.name = "BloodPoolVisuals"
	visuals.script = BloodPoolVisuals
	pool.add_child(visuals)

	parent.add_child(pool)
	# `position` is a world contact point; place the pool there regardless of the parent's
	# transform (a world-root parent may be offset from the origin).
	pool.global_position = position
	Despawner.track(pool)

	# Spread further where blood already sits; a lone wound stays at the base radius. Count scales
	# with area so the wider disc stays a solid puddle rather than thinning into scattered dots.
	var nearby := _nearby_volume(pool, position)
	var spread: float = clampf(BloodConfig.pool_radius_base + nearby * BloodConfig.spread_per_volume,
		BloodConfig.pool_radius_base, BloodConfig.pool_radius_max)
	var area_ratio := (spread * spread) / (BloodConfig.pool_radius_base * BloodConfig.pool_radius_base)
	var count: int = clampi(roundi(BloodConfig.particle_count * area_ratio),
		BloodConfig.particle_count, BloodConfig.particle_count_max)
	pool.seed(direction, count, spread, exclude, source)


## Weighted volume of blood already near `position`: each existing pool within
## BloodConfig.detection_radius adds its drop count, scaled down with distance so nearer blood
## drives more spread. `new_pool` is skipped (it is already in the group but holds no blood yet).
static func _nearby_volume(new_pool: Node2D, position: Vector2) -> float:
	var total := 0.0
	for other in new_pool.get_tree().get_nodes_in_group("blood_pools"):
		if other == new_pool:
			continue
		var dist: float = other.global_position.distance_to(position)
		if dist < BloodConfig.detection_radius:
			total += other.blood_volume() * (1.0 - dist / BloodConfig.detection_radius)
	return total
