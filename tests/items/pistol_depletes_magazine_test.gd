extends GameTest

## Every shot spends a round from the loaded magazine; an empty pistol does not fire.


func describe() -> Dictionary:
	return {
		"name": "A pistol runs dry",
		"description": "A pistol loaded with 3 rounds runs down 3, 2, 1, 0; further trigger pulls spend nothing.",
		"tags": ["item", "pistol", "ammo", "magazine"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3, "start_rounds": 3 })


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var body := t.actor(&"shooter")
	t.expect_eq(body.ammo(), 3, "the pistol starts with 3 rounds")
	shooter.aim_at(Vector2(700, 250))
	await t.seconds(0.4)
	var left := []
	for i in 5:
		shooter.shoot()
		await t.seconds(0.15)
		left.append(body.ammo())
	t.expect_eq(left, [2, 1, 0, 0, 0], "each shot spends a round and the empty pistol spends nothing")
