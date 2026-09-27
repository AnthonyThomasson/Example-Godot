extends Node2D

## Projectile CONTROL layer. A bullet fired by a gun: each physics frame it sweeps
## forward along `direction` with a raycast (robust at high speed — an overlap
## check would tunnel through walls between frames) and, on hitting a solid body,
## snaps to the contact point, reports it, and frees itself. Drawing lives in
## projectile_visuals.gd. Spawned at runtime by ProjectileSpawner into the world
## (Main), not under the player.

## Travel speed in px/s. Set on the projectile itself; ProjectileSpawner seeds it
## from Config.projectile_speed, and it can be overridden per-instance.
@export var speed: float = 1600.0
## Max distance before the bullet gives up and frees itself (px).
@export var max_distance: float = 2000.0
## The projectile's own base damage. ProjectileSpawner adds the firing item's damage
## on top at spawn; the value dealt on impact is further scaled by how square the hit is.
@export var damage: float = 10.0
## Physics layers the bullet can hit (walls + solid furniture default to layer 1).
@export_flags_2d_physics var collision_mask: int = 1
## Streak color (read by projectile_visuals.gd).
@export var color: Color = Color(1.0, 0.9, 0.4)
## Streak length in px (read by projectile_visuals.gd).
@export var length: float = 12.0

## Unit travel vector, set by the spawner before add_child.
var direction := Vector2.RIGHT
## Body to skip in the sweep (the shooter) — everything is on layer 1.
var ignore: Node
## Distance travelled so far.
var _traveled := 0.0

## Emitted when the bullet hits a body, just before it frees itself. `damage` is the
## value actually dealt (base + item, scaled by how square the impact was).
signal hit(body: Node, damage: float)


func _ready() -> void:
	# The player is never rotated, so `direction` is already a world-space unit
	# vector; orient the streak along it.
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	var step := speed * delta
	var next_pos := position + direction * step

	# Sweep from the current position to the next one so nothing is skipped.
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(position, next_pos, collision_mask)
	query.hit_from_inside = true  # Register even a point-blank shot against a wall.
	if ignore is CollisionObject2D:
		query.exclude = [ignore.get_rid()]

	var result := space.intersect_ray(query)
	if result:
		var body: Node = result.collider
		position = result.position  # Snap to the contact point.
		# Scale damage by how square the hit was: full head-on, less at a glancing
		# angle. `s` is the alignment of travel with the surface normal (both unit
		# vectors). A zero-length normal (point-blank hit_from_inside) counts as square.
		var n: Vector2 = result.normal
		var squareness := 1.0 if n.length() < 0.001 else absf(direction.dot(n))
		var dealt := damage * squareness
		print("Shot hit: %s for %.0f damage (%.0f%% square)" % [body.name, dealt, squareness * 100.0])
		hit.emit(body, dealt)
		queue_free()
		return

	position = next_pos
	_traveled += step
	if _traveled > max_distance:
		queue_free()
