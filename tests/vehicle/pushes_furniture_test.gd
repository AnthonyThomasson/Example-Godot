extends GameTest

## V6 (ticket #54): furniture is shoved by the physics engine (the pushable contract). The car driven into an armchair
## pushes it on ahead along its path and keeps going (the chair is not a wall), and a crash it posts names the chair's material.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const CHAIR_AT := Vector2(800, 300)


func describe() -> Dictionary:
	return {
		"name": "The car pushes furniture",
		"description": "The car drives into an armchair: the chair is shoved well along the car's path, the car keeps moving, and a crash event on it names fabric.",
		"tags": ["vehicle", "car", "collision", "furniture", "push"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	# Room past the chair: at F4's launch the car meets it near 850 px/s and throws it as far as an 1800 px arena's east wall.
	s.arena(Rect2(0, 0, 3600, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(250, 300))
	s.object(&"chair", "armchair", CHAIR_AT)
	s.actor(&"me", &"puppet", Vector2(120, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var chair := t.object(&"chair") as Node2D
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets in"):
		return
	var start := chair.global_position
	var front := Probe.forward(car)
	var touched := -1.0
	var speed_at_touch := 0.0
	t.puppet(&"me").drive(1.0, 0.0, false)
	var deadline := t.time + 8.0
	while t.time < deadline:
		await t.frames(1)
		if touched < 0.0 and chair.global_position.distance_to(start) > 2.0:
			touched = t.time
			speed_at_touch = car.speed()
		if touched >= 0.0 and t.time > touched + 1.0:
			break
	t.puppet(&"me").drive(0.0, 0.0, false)
	if not t.require(touched >= 0.0, "the car reaches the chair"):
		return
	var shoved := chair.global_position - start
	t.check(shoved.dot(front) > 30.0, "the chair is shoved on along the car's path (%.0f px)" % shoved.dot(front))
	t.check(car.speed() > 0.3 * speed_at_touch, "the car keeps going through it (%.0f px/s, %.0f at the touch)" % [car.speed(), speed_at_touch])
	var crashes := t.events_of(&"vehicle", func(d): return d.get("stage") == &"crash")
	for c: Dictionary in crashes:
		t.expect_eq(c.get("material"), chair.get_surface()["material"], "a crash on the chair names its material")
