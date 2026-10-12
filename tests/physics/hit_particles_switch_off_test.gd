extends GameTest

## With the `physics.hit_particles` switch off a shot bursts no particles (it still hits).


func describe() -> Dictionary:
	return {
		"name": "A shot bursts nothing with hit particles off",
		"description": "A puppet shoots a chair with the hit-particles switch off; the chair is hit but no emitter appears.",
		"tags": ["hit particles", "switch", "chair"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.hit_particles", false)
	s.actor(&"shooter", &"puppet", Vector2(120, 200), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(500, 200))


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var chair := t.object(&"chair")
	shooter.aim_at(chair.global_position)
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return not chair.hit_marks().is_empty(), 2.0), "the shot hits the chair"):
		return
	await t.seconds(0.3)
	t.check(t.world.find_children("HitParticles*", "CPUParticles2D", true, false).is_empty(), "no particle burst appeared")
