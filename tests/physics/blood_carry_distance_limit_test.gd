extends GameTest

## The blood a round carries out of a character runs out: past `BallisticsConfig.blood_carry_distance` the
## surface it hits is marked, but not with blood.


func describe() -> Dictionary:
	return {
		"name": "A round's blood runs out with distance",
		"description": "A puppet shoots through another with a tiny carry distance; the chair behind is hit but its mark is clean.",
		"tags": ["hit particles", "blood", "penetration", "pistol"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.switch(&"projectile.flyover", false)
	s.set_static(BallisticsConfig, "blood_carry_distance", 40.0)
	s.actor(&"shooter", &"puppet", Vector2(100, 200), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(300, 200), { "max_health": 400.0 })
	s.object(&"chair", "chair", Vector2(460, 200))


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.5)
	shooter.shoot()
	var chair := t.object(&"chair")
	if not t.require(await t.until(func(): return not chair.hit_marks().is_empty(), 2.0), "the round reaches the chair"):
		return
	t.check(chair.hit_marks().all(func(i): return i["blood"] == 0.0), "the chair's hit mark is clean")
