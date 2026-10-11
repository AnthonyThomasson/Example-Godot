class_name ProjectileSpawner

const Projectile = preload("res://scenes/projectile/projectile.gd")
const ProjectileVisuals = preload("res://scenes/projectile/projectile_visuals.gd")

## Spawn a bullet at `position` travelling along `direction` into `parent` (the world root).
## `ignore` is the shooter's body, skipped in the sweep; `item_damage` adds to the bullet's
## base damage. `muzzle_speed` is the speed it leaves at (negative = `BallisticsConfig.projectile_speed`);
## `penetration` its power to punch through what it hits (1 = a pistol round, higher goes further).
## Returns the node so the caller can connect its `hit` signal.
static func spawn(position: Vector2, direction: Vector2, parent: Node, ignore: Node = null, item_damage: float = 0.0,
		muzzle_speed: float = -1.0, penetration: float = 1.0) -> Node:
	var proj := Node2D.new()
	proj.name = "Projectile"
	proj.script = Projectile
	proj.position = position
	proj.direction = direction
	proj.ignore = ignore
	proj.muzzle_speed = muzzle_speed if muzzle_speed > 0.0 else BallisticsConfig.projectile_speed
	proj.speed = proj.muzzle_speed
	proj.penetration_power = maxf(penetration, 0.05)
	proj.damage += item_damage

	var visuals := Node2D.new()
	visuals.name = "ProjectileVisuals"
	visuals.script = ProjectileVisuals
	proj.add_child(visuals)

	parent.add_child(proj)
	return proj
