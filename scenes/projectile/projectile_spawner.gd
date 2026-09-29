class_name ProjectileSpawner

const Projectile = preload("res://scenes/projectile/projectile.gd")
const ProjectileVisuals = preload("res://scenes/projectile/projectile_visuals.gd")

## Spawn a bullet at `position` travelling along `direction` into `parent` (the world root).
## `ignore` is the shooter's body, skipped in the sweep; `item_damage` adds to the bullet's
## base damage. Returns the node so the caller can connect its `hit` signal.
static func spawn(position: Vector2, direction: Vector2, parent: Node, ignore: Node = null, item_damage: float = 0.0) -> Node:
	var proj := Node2D.new()
	proj.name = "Projectile"
	proj.script = Projectile
	proj.position = position
	proj.direction = direction
	proj.ignore = ignore
	proj.speed = BallisticsConfig.projectile_speed
	proj.damage += item_damage

	var visuals := Node2D.new()
	visuals.name = "ProjectileVisuals"
	visuals.script = ProjectileVisuals
	proj.add_child(visuals)

	parent.add_child(proj)
	return proj
