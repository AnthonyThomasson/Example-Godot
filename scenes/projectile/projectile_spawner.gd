class_name ProjectileSpawner

const Projectile = preload("res://scenes/projectile/projectile.gd")
const ProjectileVisuals = preload("res://scenes/projectile/projectile_visuals.gd")

## Spawn a bullet at `position` travelling along `direction`, parented to `parent`
## (the world / Main — bullets live in world space, not under the shooter).
## `ignore` is the shooter's body, skipped in the sweep. The bullet's speed is
## seeded from Config.projectile_speed onto its own `speed` property. `item_damage`
## is the firing item's damage, added on top of the projectile's own base `damage`
## (so the total is "projectile + item"). Returns the node so the caller can wire
## its `hit` signal.
static func spawn(position: Vector2, direction: Vector2, parent: Node, ignore: Node = null, item_damage: float = 0.0) -> Node:
	var proj := Node2D.new()
	proj.name = "Projectile"
	proj.script = Projectile
	proj.position = position
	proj.direction = direction
	proj.ignore = ignore
	proj.speed = Config.projectile_speed
	proj.damage += item_damage  # proj.damage starts at the projectile's own base.

	var visuals := Node2D.new()
	visuals.name = "ProjectileVisuals"
	visuals.script = ProjectileVisuals
	proj.add_child(visuals)

	parent.add_child(proj)
	return proj
