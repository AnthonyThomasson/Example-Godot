extends GameTest

## A pistol shot that strikes a chair is recorded by its Deformable (the hittable contract): a `hit`
## event names the chair and the chair keeps an impact.


func describe() -> Dictionary:
	return {
		"name": "A shot dents a chair",
		"description": "A puppet shoots a chair across an arena; the chair is the hit's victim and records an impact.",
		"tags": ["deformation", "hittable", "pistol", "chair"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(120, 200), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(500, 200))


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var chair := t.object(&"chair")
	shooter.aim_at(chair.global_position)
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"hit", func(d): return d["victim"] == chair), 2.0), "a hit event names the chair"):
		return
	var deformable: Node = null
	for child in chair.get_children():
		if child is Deformable:
			deformable = child
	if t.require(deformable != null, "the chair composes a Deformable"):
		t.check(deformable.impacts.size() > 0, "the chair recorded the impact")
