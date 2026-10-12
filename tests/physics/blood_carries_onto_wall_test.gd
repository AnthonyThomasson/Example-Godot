extends GameTest

## A round that passes through a character carries its blood onto the wall behind: the wall's hit mark is bloody.


func describe() -> Dictionary:
	return {
		"name": "A round carries blood onto the wall behind its target",
		"description": "A puppet shoots through another toward the arena's east wall; the wall's hit mark is bloody.",
		"tags": ["hit particles", "blood", "wall", "penetration", "pistol"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.switch(&"projectile.flyover", false)
	s.set_static(BallisticsConfig, "blood_carry_distance", 500.0)
	s.actor(&"shooter", &"puppet", Vector2(300, 200), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(600, 200), { "max_health": 400.0 })


## The arena's wall nodes (anything with wall segments).
func _walls(t: TestContext) -> Array:
	return t.world.find_children("*", "Node2D", true, false).filter(func(n): return n.has_method("wall_segments"))


func _marks(t: TestContext) -> Array:
	var marks: Array = []
	for wall in _walls(t):
		marks.append_array(wall.hit_marks())
	return marks


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return not _marks(t).is_empty(), 2.0), "the round reaches the wall"):
		return
	t.check(_marks(t).any(func(m): return m["blood"] > 0.0), "the wall's hit mark is bloody")
