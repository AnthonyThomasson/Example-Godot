extends GameTest

## R reloads: it takes MagazineConfig.reload_time, seats the fullest carried magazine and keeps the old one
## (with what is left in it) among the spares.


func describe() -> Dictionary:
	return {
		"name": "Reload swaps in the fullest magazine",
		"description": "A half-spent pistol reloads from the fullest spare after the reload time; the old magazine is kept; switching away cancels a reload.",
		"tags": ["item", "pistol", "ammo", "magazine", "reload"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"gunman", &"puppet", Vector2(200, 250), { "start_slot": 3, "start_rounds": 5, "spare_magazine_types": [&"standard", &"extended"] })
	s.actor(&"dry", &"puppet", Vector2(200, 400), { "start_slot": 3, "start_rounds": 5, "spare_magazine_types": [] })


func run(t: TestContext) -> void:
	var gunman := t.puppet(&"gunman")
	var body := t.actor(&"gunman")
	t.expect_eq(body.spare_magazines(), 2, "two spare magazines are carried")
	t.check(body.can_reload(), "a fuller magazine is carried, so a reload would add rounds")

	gunman.reload()
	await t.seconds(0.2)
	t.check(body.is_reloading(), "the reload is under way")
	t.expect_eq(body.ammo(), 5, "the old magazine is still in until the reload is done")
	await t.seconds(MagazineConfig.reload_time + 0.3)
	t.check(not body.is_reloading(), "the reload finished")
	t.expect_eq(body.ammo(), 20, "the fullest spare (extended, 20 rounds) is seated")
	t.expect_eq(body.ammo_capacity(), 20, "its capacity is the gun's now")
	t.expect_eq(body.spare_magazines(), 2, "the half-spent magazine was kept as a spare")

	# The spares are a 12 and a 5: a reload only helps while one holds more than what is loaded.
	gunman.select_slot(2)
	await t.seconds(0.1)
	gunman.select_slot(3)
	await t.seconds(0.1)
	gunman.reload()
	await t.seconds(0.2)
	t.check(not body.is_reloading(), "20 rounds loaded against spares of 12 and 5: nothing to gain")

	# Spend the pistol down, then start a reload and switch away: the reload is cancelled.
	var shooter := t.puppet(&"gunman")
	shooter.aim_at(Vector2(700, 250))
	await t.seconds(0.3)
	for i in 12:
		shooter.shoot()
		await t.frames(2)
	t.expect_eq(body.ammo(), 8, "twelve shots left 8 rounds")
	gunman.reload()
	await t.seconds(0.2)
	t.check(body.is_reloading(), "a 12-round spare beats 8 loaded: reloading")
	gunman.select_slot(2)
	await t.seconds(0.2)
	t.check(not body.is_reloading(), "switching items cancels the reload")
	t.expect_eq(body.ammo(3), 8, "the pistol kept its rounds")

	# No spares: nothing to reload.
	var dry := t.puppet(&"dry")
	dry.reload()
	await t.seconds(0.3)
	t.check(not t.actor(&"dry").is_reloading(), "no spare magazine, no reload")
