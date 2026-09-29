class_name BloodSpawner

const BloodPool = preload("res://scenes/physics/blood_pool.gd")
const BloodPoolVisuals = preload("res://scenes/physics/blood_pool_visuals.gd")


## Add one wound's blood for a body and return the pool it went into (the body keeps this and passes
## it back so its bleeding accumulates). If `active` is still valid, the body is still standing on it
## (within its reach) and it has not hit the per-character cap, the hit grows that pool so a still
## victim pools out wider with each shot; otherwise a fresh pool is spawned at `position`. Drops
## emerge from `source`'s live position (a moving body trails blood), and `exclude` is its RID(s) so
## its own collider never traps the blood. `parent` holds the pool (placed by world position).
static func add_blood(active: Node, position: Vector2, direction: Vector2, parent: Node, exclude: Array, source: Node2D) -> Node:
	if is_instance_valid(active) \
			and active.global_position.distance_to(position) <= active.spread() + BloodConfig.detection_margin \
			and active.blood_volume() < BloodConfig.max_pool_volume:
		active.add_hit(direction)
		return active

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

	pool.seed(direction, exclude, source)
	return pool
