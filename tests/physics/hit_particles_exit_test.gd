extends GameTest

## A pistol round that goes through a character bursts particles at both the entry and the exit: one on the
## side the round came from, one on the far side, thrown onward.


func describe() -> Dictionary:
	return {
		"name": "A shot through a body bursts at entry and exit",
		"description": "A puppet shoots through another; one emitter sits on the near side of the target and another on the far side.",
		"tags": ["hit particles", "penetration", "pistol", "blood"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(150, 200), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(450, 200), { "max_health": 400.0 })


func _bursts(t: TestContext) -> Array:
	return t.world.find_children("HitParticles*", "CPUParticles2D", true, false)


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var target := t.actor(&"target")
	shooter.aim_at(target)
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return _bursts(t).size() >= 2, 2.0), "the shot bursts particles twice"):
		return
	var xs: Array = _bursts(t).map(func(b): return b.global_position.x).filter(func(x): return x < target.global_position.x + 60.0)
	t.check(xs.min() < target.global_position.x, "one burst is on the near side of the target (%s)" % str(xs))
	var near: CPUParticles2D = _bursts(t).filter(func(b): return b.global_position.x < target.global_position.x)[0]
	var far: CPUParticles2D = _bursts(t).filter(func(b): return b.global_position.x > target.global_position.x and b.global_position.x < target.global_position.x + 60.0)[0]
	t.check(far.amount >= near.amount * 2, "the exit burst is much stronger than the entry (%d vs %d particles)" % [far.amount, near.amount])
	t.check(far.initial_velocity_max > near.initial_velocity_max, "the exit burst is thrown harder than the entry")
	t.check(xs.max() > target.global_position.x, "one burst is on the far side of the target (%s)" % str(xs))
