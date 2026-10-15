extends GameTest

## V5 (ticket #54): W is throttle, S brakes and then reverses once the car is nearly stopped. Held W drives the car forward
## along its own front; S slows it much harder than letting go does, brings it through a stop (never flipping straight from
## forward to backward), then backs it up.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Throttle, brake, then reverse",
		"description": "W drives the car forward along its front; S brakes harder than coasting, passes through a stop and then reverses.",
		"tags": ["vehicle", "car", "drive", "brake", "reverse"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	# Room for 2 s of F4's launch (about 1400 px), the 0.5 s coast at that speed and the stop from it.
	s.arena(Rect2(0, 0, 5000, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(400, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var p := t.puppet(&"me")
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets in"):
		return
	await t.seconds(0.5)

	# --- W: forward along the car's front.
	var start := car.global_position
	var front := Probe.forward(car)
	p.drive(1.0, 0.0, false)
	await t.seconds(2.0)
	var moved := car.global_position - start
	t.check(car.speed() > 50.0, "W drives the car (%.0f px/s after 2 s)" % car.speed())
	t.check(Probe.along(car) > 0.0, "forward")
	t.check(moved.dot(front) > 40.0, "along its front (%.0f px)" % moved.dot(front))
	t.check(absf(moved.dot(Probe.right(car))) < 0.1 * maxf(moved.dot(front), 1.0), "and straight (%.1f px sideways)" % moved.dot(Probe.right(car)))

	# --- Let go for 0.5 s: the coasting deceleration.
	p.drive(0.0, 0.0, false)
	var v0 := Probe.along(car)
	await t.seconds(0.5)
	var v1 := Probe.along(car)
	var coast_decel := (v0 - v1) / 0.5

	# --- S: brake through a stop, then reverse.
	p.drive(-1.0, 0.0, false)
	var series: Array[float] = []
	var stop_time := -1.0
	var pressed := t.time
	var deadline := t.time + 6.0
	while t.time < deadline:
		await t.frames(1)
		series.append(Probe.along(car))
		if stop_time < 0.0 and series[-1] <= 1.0:
			stop_time = t.time - pressed
		if series[-1] < -30.0:
			break
	p.drive(0.0, 0.0, false)
	t.check(series.size() > 1 and series[0] < v1 + 0.5, "S slows the car at once (%.1f -> %.1f px/s)" % [v1, series[0] if series.size() > 0 else 0.0])
	if t.check(stop_time > 0.0, "S brings the car to a stop"):
		var brake_decel := v1 / stop_time
		t.check(brake_decel > 2.0 * coast_decel, "braking is much harder than coasting (%.0f against %.0f px/s²)" % [brake_decel, coast_decel])
	var nearest_stop := INF
	for v in series:
		nearest_stop = minf(nearest_stop, absf(v))
	t.check(nearest_stop < 3.0, "it passes through a stop on the way to reversing (slowest %.1f px/s)" % nearest_stop)
	t.check(series.size() > 0 and series[-1] < -30.0, "held S then reverses (%.0f px/s along its front)" % (series[-1] if series.size() > 0 else 0.0))
