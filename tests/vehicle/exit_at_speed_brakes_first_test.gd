extends GameTest

## V4 (ticket #54): above exit_max_speed (20 px/s), E first brakes the vehicle to a stop, then gets out. No door opens and
## the driver stays seated while the car is faster than that, and it comes down to it much sooner than it would coasting
## (the reference: the same car let go at the same speed with no E).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## The speed (px/s) the car is driven up to before it is let go, coasting or with E.
const CRUISE := 70.0


func describe() -> Dictionary:
	return {
		"name": "Exiting at speed brakes first",
		"description": "At 70 px/s, E keeps the driver in until the car is under 20 px/s, which it reaches in well under the coasting time, then the driver gets out.",
		"tags": ["vehicle", "car", "exit", "brake"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3200, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(200, 300))
	s.actor(&"me", &"puppet", Vector2(120, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets in"):
		return

	# --- Reference: let go at CRUISE and coast down to exit_max_speed (or 15 s).
	if not t.require(await Probe.reach_speed(t, &"me", car, CRUISE, 6.0), "the car reaches %.0f px/s" % CRUISE):
		return
	var let_go := t.time
	await t.until(func(): return car.speed() <= Probe.EXIT_MAX_SPEED, 15.0)
	var coast_time := t.time - let_go
	t.trace("coast_time", coast_time)
	t.puppet(&"me").drive(-1.0, 0.0, false)
	await t.until(func(): return Probe.along(car) <= 2.0, 5.0)
	t.puppet(&"me").drive(0.0, 0.0, false)
	await t.seconds(0.5)

	# --- E at CRUISE.
	if not t.require(await Probe.reach_speed(t, &"me", car, CRUISE, 6.0), "the car reaches %.0f px/s again" % CRUISE):
		return
	var pressed := t.time
	t.puppet(&"me").use_vehicle()
	var slow_at := -1.0
	var leave_speed := -1.0
	var deadline := t.time + 20.0
	while t.time < deadline and me.vehicle() != null:
		await t.frames(1)
		if slow_at < 0.0 and car.speed() <= Probe.EXIT_MAX_SPEED:
			slow_at = t.time - pressed
		var leaving: bool = not me.is_in_vehicle()
		for d: Dictionary in car.doors():
			leaving = leaving or float(d.get("open", 0.0)) > 0.02
		if leave_speed < 0.0 and leaving:
			leave_speed = car.speed()
	if not t.require(me.vehicle() == null, "the driver gets out in the end"):
		return
	t.check(leave_speed >= 0.0 and leave_speed <= Probe.EXIT_MAX_SPEED + 2.0, "no door opens and the driver stays seated until the car is under %.0f px/s (it began to leave at %.1f px/s)" % [Probe.EXIT_MAX_SPEED, leave_speed])
	t.check(slow_at >= 0.0 and slow_at < coast_time * 0.6, "E brakes: down to %.0f px/s in %.2f s, against %.2f s coasting" % [Probe.EXIT_MAX_SPEED, slow_at, coast_time])
