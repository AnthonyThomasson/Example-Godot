extends GameTest

## The same shot as debris_rests_in_a_layer with the `physics.debris` switch off: the chair is still hit,
## but no debris spawns.


func describe() -> Dictionary:
	return {
		"name": "No debris with the debris switch off",
		"description": "physics.debris off: a chair is shot and takes the hit, with no debris spawned.",
		"tags": ["debris", "switch", "chair"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.debris", false)
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
	if not t.require(await t.until(func(): return t.happened(&"hit", func(d): return d["victim"] == chair), 2.0), "a hit event names the chair"):
		return
	await t.seconds(1.0)
	t.expect_eq(_chips(t).size(), 0, "no debris was spawned")
