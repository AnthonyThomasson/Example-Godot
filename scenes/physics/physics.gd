class_name Physics

## Physics System entry points shared by every hittable object (furniture and walls).
## Stateless `static` helpers — the object's `take_hit()` calls these to turn a HitInfo
## into a shove and a burst of debris. Physics knows nothing of the Projectile, Objects
## or World-Gen domains: it takes a HitInfo + a plain surface Dictionary and returns/acts
## on generic nodes, so it stays a leaf domain other systems depend on but it never
## depends back.

## Impulse a hit imparts to the struck object, before the object's own mass divides it
## (that happens in Knockback.apply_impulse). Follows the striker's travel direction,
## scaled by its speed factor and by whether it penetrated (a pass-through dumps less
## momentum than a ricochet/embed). Tuned by PhysicsConfig.impact_*.
static func impact_impulse(hit: HitInfo) -> Vector2:
	var force_scale := PhysicsConfig.impact_penetration_scale if hit.penetrated else PhysicsConfig.impact_no_penetration_scale
	return hit.direction * PhysicsConfig.impact_impulse * hit.speed_factor * force_scale


## Spray material-styled chips out of a hit, added under `parent` (placed by world position,
## so `parent` may be offset from the origin). `surface` is the struck object's
## `get_surface()` — its `color` and `material` style the chips. Chips fly out along the
## surface normal, or back along the shot when the normal is degenerate.
static func spawn_debris(parent: Node, hit: HitInfo, surface: Dictionary) -> void:
	var base_color: Color = surface.get("color", Color(0.6, 0.6, 0.6))
	var material: String = surface.get("material", "")
	var spray := hit.normal if hit.normal.length() > 0.001 else -hit.direction
	DebrisSpawner.spawn(hit.position, spray, parent, base_color, material)
