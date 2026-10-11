extends GameTest

## A one-hit target is shot dead: it dies, its body falls and comes to rest, and once at rest it
## bleeds out a pool beside the wound's splatter (Physics.bleed_out). Pair: death_without_blood.


func describe() -> Dictionary:
	return {
		"name": "Dead body bleeds out",
		"description": "A 1 hp target is shot; it dies, falls, and once its body rests a bleed-out pool spreads.",
		"tags": ["death", "ragdoll", "blood", "bleed out"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.blood", true)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(560, 250), { "max_health": 1.0 })


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.4)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"died", func(d): return d["actor"] == &"target"), 2.0), "the target dies"):
		return
	t.check(t.actor(&"target").is_dead, "is_dead is set")
	t.check(not t.spawned("BloodSplat").is_empty(), "the wound left a splatter")
	await t.until(func(): return not t.spawned("BloodPool").is_empty(), 8.0, "a bleed-out pool spreads once the body rests")
