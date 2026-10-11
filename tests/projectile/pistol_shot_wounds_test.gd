extends GameTest

## A puppet fires the pistol at another puppet across an empty arena: the bullet posts a `hit`
## event naming the shooter and the target, and the target loses health.


func describe() -> Dictionary:
	return {
		"name": "Pistol shot wounds a target",
		"description": "One puppet shoots another across an empty arena; the shot lands and deals damage.",
		"tags": ["pistol", "damage", "hit event"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)  # a character is partial cover; make the shot always land
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(600, 250))


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var target := t.actor(&"target")
	shooter.aim_at(target)
	await t.seconds(0.5)
	shooter.shoot()
	var hit := func(d): return d["victim"] == target and d["attacker"] == t.actor(&"shooter")
	if not t.require(await t.until(func(): return t.happened(&"hit", hit), 2.0), "a hit event names the shooter and the target"):
		return
	t.check(target.health < target.max_health, "the target lost health (%.0f / %.0f)" % [target.health, target.max_health])
	t.check(t.happened(&"hit_landed", func(d): return d["actor"] == &"shooter" and d["hand"] == -1), "the shooter reports the shot (hit_landed, hand -1)")
