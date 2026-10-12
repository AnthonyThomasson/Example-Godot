extends GameTest

## A round that goes right through a character throws blood out the far side (BloodWound.record at the exit).


func describe() -> Dictionary:
	return {
		"name": "A shot through a body splatters blood out the far side",
		"description": "A puppet shoots through another; a blood splatter lands just beyond the target, where the round left it.",
		"tags": ["blood", "wound", "penetration", "pistol"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(150, 200), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(450, 200), { "max_health": 400.0 })


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var target := t.actor(&"target")
	shooter.aim_at(target)
	await t.seconds(0.5)
	shooter.shoot()
	var beyond := func() -> bool:
		return t.world.find_children("BloodSplat*", "Node2D", true, false).any(
			func(n): return n.global_position.x > target.global_position.x + 5.0 and n.global_position.x < target.global_position.x + 40.0)
	t.check(await t.until(beyond, 2.0), "a blood splatter lies just beyond the target")
