extends GameTest

## V6 (ticket #54): the vehicle is a rigid body on the solid layer. Driven into a wall it is stopped there, losing most of
## its speed on the impact, and the impact (above crash_min_speed) posts a `vehicle` crash event with its speed and the
## struck material.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A crash into a wall stops the car",
		"description": "The car is driven flat out into the east wall: it loses most of its speed on impact, stays this side of the wall, and a vehicle crash event carries the impact speed and a material.",
		"tags": ["vehicle", "car", "crash", "collision", "wall"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(250, 300))
	s.actor(&"me", &"puppet", Vector2(120, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var crash_min: Variant = Probe.config_value(&"crash_min_speed")
	if not t.require(crash_min != null, "VehicleConfig.crash_min_speed exists"):
		return
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets in"):
		return
	var crashed := func(): return t.happened(&"vehicle", func(d): return d.get("stage") == &"crash")
	var before := 0.0
	t.puppet(&"me").drive(1.0, 0.0, false)
	var deadline := t.time + 10.0
	while t.time < deadline and not crashed.call():
		before = car.speed()
		await t.frames(1)
	t.puppet(&"me").drive(0.0, 0.0, false)
	if not t.require(crashed.call(), "driving into the wall posts a crash event"):
		return
	await t.frames(3)
	t.check(before > float(crash_min), "it hit the wall faster than crash_min_speed (%.0f against %.0f px/s)" % [before, float(crash_min)])
	t.check(car.speed() < 0.5 * before, "it loses most of its speed on the impact (%.0f -> %.0f px/s)" % [before, car.speed()])
	var crash: Dictionary = t.events_of(&"vehicle", func(d): return d.get("stage") == &"crash")[0]
	t.check(crash.has("material"), "the crash event names the struck material")
	t.expect_eq(crash.get("kind"), &"car", "and the vehicle's kind")
	t.check(absf(float(crash.get("speed", 0.0)) - before) < 0.3 * before, "and the impact speed (%.0f, the car was at %.0f px/s)" % [float(crash.get("speed", 0.0)), before])
	t.check((crash.get("position", Vector2.ZERO) as Vector2).x > 1200.0, "where it hit the east wall (%s)" % crash.get("position"))

	await t.seconds(1.0)
	t.check(car.speed() < 20.0, "the wall has stopped it (%.1f px/s)" % car.speed())
	t.check(Probe.edge(car, Probe.forward(car)).x < 1400.0, "and it stays this side of the wall")
