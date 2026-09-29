class_name BloodSpawner

const BloodPool = preload("res://scenes/physics/blood_pool.gd")
const BloodPoolVisuals = preload("res://scenes/physics/blood_pool_visuals.gd")


## Spawn one blood pool at world point `position`, spilling its fixed burst of particles roughly
## along `direction`, added under `parent` (placed by global position, so `parent` may be offset
## from the world origin). `exclude` is the wounded body's RID(s), so its own collider never traps
## the blood. The pool is Despawner-tracked and persists until the cap frees it.
static func spawn(position: Vector2, direction: Vector2, parent: Node, exclude: Array) -> void:
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

	pool.seed(direction, BloodConfig.particle_count, exclude)
