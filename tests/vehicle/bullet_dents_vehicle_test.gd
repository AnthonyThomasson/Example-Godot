extends GameTest

## V6 (ticket #54): bullets hit a vehicle like furniture: get_surface() reports metal with high coverage and a high
## resistance to being shot through, and take_hit dents it (a Deformable records the impact) and throws debris. There is no
## vehicle destruction: after more rounds it is still there.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A bullet dents a vehicle",
		"description": "A pistol puppet shoots the car: the hit names the car, its surface is metal (coverage 60+, penetration 80+), its Deformable records the impact, debris flies, and six more rounds leave it standing.",
		"tags": ["vehicle", "car", "hittable", "deformation", "pistol"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.switch(&"projectile.flyover", false)
	s.vehicle(&"car", &"car", Vector2(560, 250))
	s.actor(&"shooter", &"puppet", Vector2(150, 250), { "start_slot": 3 })


## The debris chips spawned under the world so far.
func _debris(t: TestContext) -> Array:
	return t.events_of(&"spawned", func(d): return String(d["name"]).contains("Debris") \
			and not String(d["name"]).contains("Layer") and not String(d["name"]).contains("Visuals"))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car"):
		return
	var car := t.vehicle(&"car") as Node2D
	if not Probe.has_reads(t, car, [&"take_hit"], "the car"):
		return
	var surface: Dictionary = car.get_surface()
	t.expect_eq(surface.get("material"), "metal", "the car's surface is metal")
	t.check(float(surface.get("coverage", 0.0)) >= 60.0, "with high coverage (%s)" % surface.get("coverage"))
	t.check(float(surface.get("penetration", 0.0)) >= 80.0, "and a high resistance to being shot through (%s)" % surface.get("penetration"))

	var shooter := t.puppet(&"shooter")
	shooter.aim_at(car.global_position)
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"hit", func(d): return d["victim"] == car), 2.0), "a hit event names the car"):
		return
	await t.frames(2)
	var deformable: Deformable = null
	for child in car.get_children():
		if child is Deformable:
			deformable = child
	if t.require(deformable != null, "the car composes a Deformable"):
		t.check(deformable.impacts.size() > 0, "the car keeps a dent where the round struck")
	t.check(not _debris(t).is_empty(), "debris flies off the car")

	for i in 6:
		shooter.shoot()
		await t.seconds(0.4)
	await t.seconds(0.5)
	t.check(is_instance_valid(car) and car.is_inside_tree(), "after six more rounds the car is still there")
	if deformable != null:
		t.check(deformable.impacts.size() > 1, "with more dents (%d)" % deformable.impacts.size())
