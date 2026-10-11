extends GameTest

## A reload is refused while running and cancelled by running or dying; a reloading character cannot shoot.


func describe() -> Dictionary:
	return {
		"name": "Reload is blocked by running and cancelled by death",
		"description": "R is ignored while running; a reload stops when the character runs or dies; shooting is ignored mid-reload.",
		"tags": ["reload", "run", "death", "pistol"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.actor(&"a", &"puppet", Vector2(200, 150), { "start_slot": 3, "start_rounds": 2 })
	s.actor(&"b", &"puppet", Vector2(200, 300), { "start_slot": 3, "start_rounds": 2 })
	s.actor(&"c", &"puppet", Vector2(200, 450), { "start_slot": 3, "start_rounds": 2 })


func run(t: TestContext) -> void:
	# Running: the reload is refused.
	var a := t.puppet(&"a")
	a.set_run(true)
	a.walk_to(Vector2(700, 150))
	await t.seconds(0.3)
	a.reload()
	await t.seconds(0.1)
	t.check(not t.actor(&"a").is_reloading(), "a running character does not start a reload")
	a.stop()

	# Mid-reload: shooting is ignored, and starting to run cancels the reload.
	var b := t.puppet(&"b")
	var body := t.actor(&"b")
	b.aim_at(Vector2(700, 300))
	await t.seconds(0.3)
	b.reload()
	await t.seconds(0.2)
	t.check(body.is_reloading(), "b is reloading")
	var shots := t.spawned("Projectile").size()
	b.shoot()
	await t.seconds(0.2)
	t.expect_eq(t.spawned("Projectile").size(), shots, "a reloading pistol does not fire")
	b.set_run(true)
	b.walk_to(Vector2(700, 300))
	await t.seconds(0.4)
	t.check(not body.is_reloading(), "running cancels the reload")
	t.expect_eq(body.ammo(), 2, "the cancelled reload left the pistol as it was")

	# Death mid-reload.
	var c := t.puppet(&"c")
	var corpse := t.actor(&"c")
	c.reload()
	await t.seconds(0.2)
	t.check(corpse.is_reloading(), "c is reloading")
	corpse.take_damage(1000.0)
	await t.frames(2)
	t.check(corpse.is_dead and not corpse.is_reloading(), "dying ends the reload")
