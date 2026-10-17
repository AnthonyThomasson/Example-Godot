extends GameTest

## The look of a burst (Physics): `Physics.spawn_explosion(world, at, kind)` puts a bright flash, a fireball puff and drifting
## smoke in the world for a frag (a scorch decal stays under it), and only thin smoke for a stun: its white flash is the
## lighting's flash light (S8, ticket #56; `lighting/stun_flash_light`), no drawn disc; with `PhysicsConfig.explosion_fx_enabled`
## off it spawns none of it.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AT := Vector2(300, 250)


func describe() -> Dictionary:
	return {
		"name": "An explosion spawns its effects, and none with the switch off",
		"description": "spawn_explosion for a frag makes a flash, a fireball and smoke plus a scorch decal; for a stun thin smoke only (its flash is a light); with explosion_fx_enabled off, nothing.",
		"tags": ["grenade", "explosion", "fx", "physics"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.set_static(PhysicsConfig, &"explosion_fx_enabled", true)


## The effect nodes named `part` anywhere in the world.
func _nodes(t: TestContext, part: String) -> Array:
	return t.world.find_children("*%s*" % part, "", true, false)


func run(t: TestContext) -> void:
	var physics: GDScript = Physics
	var config: GDScript = PhysicsConfig
	if not t.require(physics.has_method("spawn_explosion") and config.get("explosion_fx_enabled") != null, "Physics.spawn_explosion and PhysicsConfig.explosion_fx_enabled exist"):
		return
	physics.call("spawn_explosion", t.world, AT, &"frag")
	await t.frames(2)
	t.check(not _nodes(t, "ExplosionFlash").is_empty(), "a frag makes a bright flash")
	t.check(not _nodes(t, "ExplosionFireball").is_empty(), "and a fireball puff")
	t.check(not _nodes(t, "ExplosionSmoke").is_empty(), "and smoke")
	t.check(not _nodes(t, "Scorch").is_empty(), "and leaves a scorch decal under it")

	await t.seconds(4.0)
	t.check(not _nodes(t, "Scorch").is_empty(), "the scorch stays after the flash, fireball and smoke have gone")
	t.check(_nodes(t, "ExplosionFlash").is_empty() and _nodes(t, "ExplosionFireball").is_empty(), "the flash and the fireball are short lived")

	var scorch := _nodes(t, "Scorch").size()
	physics.call("spawn_explosion", t.world, AT + Vector2(200, 0), &"stun")
	await t.frames(2)
	t.check(_nodes(t, "ExplosionFlash").is_empty(), "a stun draws no white flash disc: the lighting shows its flash (S8)")
	t.check(not _nodes(t, "ExplosionSmoke").is_empty(), "it makes thin smoke")
	t.check(_nodes(t, "ExplosionFireball").is_empty(), "but no fireball")
	t.expect_eq(_nodes(t, "Scorch").size(), scorch, "and no scorch")

	await t.seconds(4.0)
	config.set("explosion_fx_enabled", false)
	var all := _nodes(t, "Explosion").size() + _nodes(t, "Scorch").size()
	physics.call("spawn_explosion", t.world, AT + Vector2(-200, 0), &"frag")
	physics.call("spawn_explosion", t.world, AT + Vector2(0, 100), &"stun")
	await t.frames(2)
	t.expect_eq(_nodes(t, "Explosion").size() + _nodes(t, "Scorch").size(), all, "with the master switch off no effect is spawned")
	config.set("explosion_fx_enabled", true)
