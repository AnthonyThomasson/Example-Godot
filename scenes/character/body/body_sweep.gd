extends RefCounted

## Character BODY sub-domain: the collide-and-slide a hand or a leg makes from the body centre toward where the
## pose or rig wants it, shared by character_hands.gd and character_legs.gd. A circle is cast along the motion
## on the solid layer; where it first touches a wall, solid piece or another character it rests, and what is
## left of the motion slides along the surface (its normal read off a ray along the approach) up to the next
## contact. Stateless.

## Physics layer a hand or leg meets: walls, solid furniture and living characters.
const MASK := PhysicsLayers.SOLID


## Where a circle of `radius` swept from `centre` (world) along `motion` comes to rest, as a local offset from
## `centre`: `motion` itself when the way is clear. `exclude` is the body's own RID(s).
static func circle(space: PhysicsDirectSpaceState2D, centre: Vector2, motion: Vector2, radius: float,
		exclude: Array) -> Vector2:
	if motion.length_squared() < 0.0001:
		return motion
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = MASK
	params.exclude = exclude
	params.transform = Transform2D(0.0, centre)
	params.motion = motion
	var safe: float = space.cast_motion(params)[0]  # [safe, unsafe] fractions of the motion.
	if safe >= 1.0:
		return motion
	var rest := motion * safe
	var ray := PhysicsRayQueryParameters2D.create(centre, centre + motion, MASK)
	ray.exclude = exclude
	var hit := space.intersect_ray(ray)
	var normal: Vector2 = hit.normal if not hit.is_empty() and hit.normal.length() > 0.001 else -motion.normalized()
	var slide := (motion * (1.0 - safe)).slide(normal)
	params.transform = Transform2D(0.0, centre + rest)
	params.motion = slide
	return rest + slide * float(space.cast_motion(params)[0])
