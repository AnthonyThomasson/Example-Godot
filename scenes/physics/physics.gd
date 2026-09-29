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


## Add a flesh hit's blood to the body's persistent pool, added under `parent` (placed by world
## position), and return the pool so the caller can pass it back on its next hit to accumulate. Pass
## the body's current pool as `active`, or null for its first wound; hits that land on the active
## pool grow it (a still victim pools out wider), while moving off it starts a new one. Blood spreads
## out the wound face (the surface normal), or back along the shot when the normal is degenerate.
## `exclude` is the wounded body's RID(s), so its own collider never traps the blood, and `source` is
## that body, whose live position drops emerge from. This is a self-contained reaction, independent
## of the debris and deformation a hit also produces.
static func spawn_blood(parent: Node, hit: HitInfo, exclude: Array, source: Node2D, active: Node) -> Node:
	var spill := hit.normal if hit.normal.length() > 0.001 else -hit.direction
	return BloodSpawner.add_blood(active, hit.position, spill, parent, exclude, source)
