extends GameTest

## A pistol shot that strikes a chair sprays debris (Physics.spawn_debris), and the debris stays
## near the impact point.


func describe() -> Dictionary:
	return {
		"name": "A shot sprays debris",
		"description": "A puppet shoots a chair; debris chips spawn and the first one starts within a few pixels of the chair.",
		"tags": ["debris", "hittable", "pistol", "chair"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(120, 200), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(500, 200))


## The debris chips currently in the world (they sit under the arena, not the world root).
func _chips(t: TestContext) -> Array:
	return t.world.find_children("*", "Node2D", true, false).filter(func(n): return String(n.name).begins_with("Debris") and not String(n.name).begins_with("DebrisVisuals"))


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var chair := t.object(&"chair")
	shooter.aim_at(chair.global_position)
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return _chips(t).size() > 0, 2.0), "the shot spawns debris"):
		return
	var chip: Node2D = _chips(t)[0]
	t.expect_near(chip.global_position.x, chair.global_position.x, 40.0, "debris starts at the chair")
