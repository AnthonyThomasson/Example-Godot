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


## Show a hit: a particle burst at the entry point (weak, with a much stronger one at the exit when the striker passed
## through, `hit.has_exit`; a hit that stays in the object gets one full-strength burst) plus chips knocked off the entry, all styled by the struck object's
## `get_surface()` (`color`, `material`) and added under `parent` (placed by world position, so
## `parent` may be offset from the origin). Entry particles and chips fly out along the surface
## normal, or back along the shot when the normal is degenerate; the exit burst follows the shot. A
## hit that carries blood (`hit.blood > 0`, a bullet that just left a character) also throws a few
## red droplets and chips from the entry. Particles need PhysicsConfig.hit_particles_enabled, chips
## PhysicsConfig.debris_enabled, and the blood bits BloodConfig.enabled.
static func spawn_debris(parent: Node, hit: HitInfo, surface: Dictionary) -> void:
	var spray := hit.normal if hit.normal.length() > 0.001 else -hit.direction
	var strength := clampf(hit.speed_factor, 0.4, 1.5) * clampf(0.7 + hit.damage / 50.0, 0.7, 1.4)
	# Through the object: a weak burst going in, the strong one coming out. Otherwise one full-strength burst.
	var through := hit.has_exit
	HitParticles.spawn(hit.position, spray, parent, surface, HitParticles.Kind.ENTRY if through else HitParticles.Kind.IMPACT, strength)
	if through:
		var out := hit.exit_normal if hit.exit_normal.length() > 0.001 else hit.direction
		HitParticles.spawn(hit.exit_position, (out + hit.direction).normalized(), parent, surface, HitParticles.Kind.EXIT, strength)
	if hit.blood > 0.0 and BloodConfig.enabled:
		HitParticles.spawn(hit.position, spray, parent, { "material": "blood" }, HitParticles.Kind.IMPACT, hit.blood * 0.7)
		if PhysicsConfig.debris_enabled:
			DebrisSpawner.spawn(hit.position, spray, parent, PhysicsConfig.blood_mark_color, "flesh")
	if not PhysicsConfig.debris_enabled:
		return
	var base_color: Color = surface.get("color", Color(0.6, 0.6, 0.6))
	var material: String = surface.get("material", "")
	DebrisSpawner.spawn(hit.position, spray, parent, base_color, material)


## Start a dead body's bleed-out: one slow, flowing pool (BloodConfig.bleed_out_*) spreading from where
## its blood leaves it — `source.blood_origin()` if it has one (where it lies), else its position —
## added under `parent`. `exclude` is the body's RID(s). Returns the pool (null while
## BloodConfig.enabled is off).
static func bleed_out(parent: Node, source: Node2D, exclude: Array) -> Node:
	if not BloodConfig.enabled:
		return null
	return BloodSpawner.bleed(parent, source, exclude)


## Show a grenade's burst of `kind` (`&"frag"` or `&"stun"`) at world point `at` under `world`: a bright flash, for a frag a
## fireball puff and, with smoke drifting off, a scorch left on the floor under it; a stun is a white flash and thin smoke.
## Looks and timings are `PhysicsConfig.explosion_looks`; spawns nothing while `PhysicsConfig.explosion_fx_enabled` is off.
static func spawn_explosion(world: Node, at: Vector2, kind: StringName) -> void:
	if PhysicsConfig.explosion_fx_enabled:
		ExplosionFx.spawn(world, at, kind)
