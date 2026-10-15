extends GameTest

## V2 (ticket #54): only the driver's seat drives. A character in a rear seat holds throttle and steer: the car stays put,
## its engine is not started and it has no driver. A driver getting in afterwards drives it (so the stillness is the seat,
## not a car that cannot move).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A rear seat cannot drive",
		"description": "A puppet in the rear-left seat holds W and D: the car does not move, the engine stays off and driver() is null; a puppet then boarding at the front left drives it.",
		"tags": ["vehicle", "car", "seat", "drive"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(350, 300))
	s.actor(&"back", &"puppet", Vector2(100, 520))
	s.actor(&"front", &"puppet", Vector2(100, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"back", &"front"]):
		return
	var car := t.vehicle(&"car") as Node2D
	if not t.require(await Probe.board_by(t, &"back", car, &"rear_left"), "the character gets in at the rear left"):
		return
	t.expect_eq(Probe.seat_of(car, t.actor(&"back")), &"rear_left", "it sits in the rear-left seat")
	var parked := car.global_position
	var heading := car.global_rotation
	t.puppet(&"back").drive(1.0, 1.0, false)
	await t.seconds(2.0)
	t.check(car.speed() < 5.0 and car.global_position.distance_to(parked) < 5.0, "its throttle does not move the car (%.1f px/s, %.1f px)" % [car.speed(), car.global_position.distance_to(parked)])
	t.check(absf(angle_difference(heading, car.global_rotation)) < 0.02, "its steering does not turn the car")
	t.check(not car.engine_state().get("running", false), "the engine is not started from the back seat")
	t.check(car.driver() == null, "the car has no driver")
	t.puppet(&"back").drive(0.0, 0.0, false)

	if not t.require(await Probe.board_by(t, &"front", car, &"front_left"), "a driver gets in at the front left"):
		return
	t.check(await Probe.reach_speed(t, &"front", car, 40.0, 4.0), "the driver's throttle moves the car (%.0f px/s)" % car.speed())
