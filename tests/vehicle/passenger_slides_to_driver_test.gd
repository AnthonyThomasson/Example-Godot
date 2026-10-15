extends GameTest

## V2 (ticket #54): the front-right door leads to the passenger seat, and a passenger slides across to the driver's seat
## when that is empty, so it ends up driving: its throttle moves the car. With the driver's seat taken it rides: it stays
## in the passenger seat and its keys do not move the car.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A passenger slides across to an empty driver's seat",
		"description": "A puppet boarding an empty car by the front-right door ends up in the driver's seat and drives it; one boarding by the front right of a car with a driver stays a passenger and cannot drive.",
		"tags": ["vehicle", "car", "board", "seat", "drive"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 700), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"empty", &"car", Vector2(300, 180))
	s.vehicle(&"taken", &"car", Vector2(300, 500))
	s.actor(&"alone", &"puppet", Vector2(80, 60))
	s.actor(&"driver", &"puppet", Vector2(80, 640))
	s.actor(&"rider", &"puppet", Vector2(600, 640))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"empty", [&"alone", &"driver", &"rider"]) or not Probe.ready(t, &"taken"):
		return
	var empty := t.vehicle(&"empty") as Node2D
	var taken := t.vehicle(&"taken") as Node2D
	var alone := t.actor(&"alone")
	var rider := t.actor(&"rider")

	# --- An empty car: in by the front right, across to the wheel.
	if not t.require(await Probe.board_by(t, &"alone", empty, &"front_right"), "the character gets in at the front right"):
		return
	t.check(await t.until(func(): return Probe.seat_of(empty, alone) == &"driver", 3.0), "it slides across to the empty driver's seat (seat %s)" % Probe.seat_of(empty, alone))
	t.check(empty.driver() == alone, "the car's driver() is it")
	t.check(Probe.occupant(empty, &"passenger") == null, "the passenger seat is left empty")
	var start := empty.global_position
	t.puppet(&"alone").drive(1.0, 0.0, false)
	await t.seconds(1.0)
	t.puppet(&"alone").drive(0.0, 0.0, false)
	t.check(empty.speed() > 0.0, "its throttle drives the car (%.0f px/s)" % empty.speed())
	t.check(empty.global_position.distance_to(start) > 15.0, "the car moved")

	# --- A car with a driver: in by the front right, it rides.
	if not t.require(await Probe.board_by(t, &"driver", taken, &"front_left"), "a driver gets into the second car"):
		return
	if not t.require(await Probe.board_by(t, &"rider", taken, &"front_right"), "the rider gets in at the front right"):
		return
	await t.seconds(1.0)
	t.expect_eq(Probe.seat_of(taken, rider), &"passenger", "with the driver's seat taken it stays in the passenger seat")
	t.check(taken.driver() == t.actor(&"driver"), "the driver keeps the wheel")
	var parked := taken.global_position
	t.puppet(&"rider").drive(1.0, 1.0, false)
	await t.seconds(1.5)
	t.puppet(&"rider").drive(0.0, 0.0, false)
	t.check(taken.speed() < 5.0 and taken.global_position.distance_to(parked) < 5.0, "the passenger's keys do not move the car (%.1f px/s, %.1f px)" % [taken.speed(), taken.global_position.distance_to(parked)])
