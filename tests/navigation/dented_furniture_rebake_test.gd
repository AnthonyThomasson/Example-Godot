extends GameTest

## Shooting a chair dents its collider into a jagged polygon and shoves it against the arena wall; the
## re-bake that follows must produce a map the NavigationServer accepts (any engine error fails the
## test) and a path across the arena still exists.


func describe() -> Dictionary:
	return {
		"name": "Re-baking around a dented chair",
		"description": "A chair is shot and shoved; after the re-bake the nav map syncs without error and still routes across the arena.",
		"tags": ["navigation", "rebake", "deformation", "furniture"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"projectile.flyover", false)
	s.switch(&"nav.rebake", true)
	s.actor(&"shooter", &"puppet", Vector2(120, 200), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(500, 200))


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var chair := t.object(&"chair")
	shooter.aim_at(chair.global_position)
	await t.seconds(0.5)
	shooter.shoot()
	await t.seconds(3.0)  # past two re-bake ticks
	var map := t.world.get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(map, Vector2(60, 100), Vector2(640, 300), false)
	t.check(path.size() >= 2, "the re-baked map still routes across the arena")
