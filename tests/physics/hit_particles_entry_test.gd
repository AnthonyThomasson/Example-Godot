extends GameTest

## A pistol shot that strikes a chair bursts particles at the entry point (HitParticles), styled by the chair's
## material; the burst frees itself once its particles have died.


func describe() -> Dictionary:
	return {
		"name": "A shot bursts particles at the entry",
		"description": "A puppet shoots a chair; a one-shot particle emitter appears at the chair's near face and frees itself afterwards.",
		"tags": ["hit particles", "hittable", "pistol", "chair"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"projectile.flyover", false)
	s.set_static(BallisticsConfig, "exit_probe_distance", 0.0)  # no exit is found: the round just lands in the chair
	s.actor(&"shooter", &"puppet", Vector2(120, 200), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(500, 200))


## The hit-particle emitters currently in the world.
func _bursts(t: TestContext) -> Array:
	return t.world.find_children("HitParticles*", "CPUParticles2D", true, false)


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var chair := t.object(&"chair")
	shooter.aim_at(chair.global_position)
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return _bursts(t).size() > 0, 2.0), "the shot bursts particles"):
		return
	var burst: CPUParticles2D = _bursts(t)[0]
	# No exit is found, so the round stays in the chair: one burst, at the full (exit-level) strength.
	t.expect_eq(_bursts(t).size(), 1, "a hit that stays in the object gets a single burst")
	t.check(burst.amount >= 8, "a lone impact bursts at full strength (%d particles)" % burst.amount)
	t.check(burst.one_shot, "the burst is one-shot")
	t.expect_near(burst.global_position.x, chair.global_position.x, 40.0, "the burst starts at the chair")
	t.check(await t.until(func(): return _bursts(t).is_empty(), 3.0), "the burst frees itself after its particles die")
