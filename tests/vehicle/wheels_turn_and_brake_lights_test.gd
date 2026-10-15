extends GameTest

## V5 (ticket #54): the front wheels are drawn turned by the steering angle, and the brake lights show while braking.
## wheel_angle() (the drawn front-wheel angle, + to the right) eases toward the input: D turns it right, A left, letting go
## centres it, and at speed full steer turns it less than at rest. brake_lights() is on while S slows a car rolling
## forward, and off while coasting or on the throttle.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The front wheels turn and the brake lights show",
		"description": "wheel_angle() eases right on D, left on A, back to centre, and less far at speed; brake_lights() shows while braking only.",
		"tags": ["vehicle", "car", "drive", "visuals", "steer", "brake"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2600, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.actor(&"me", &"puppet", Vector2(120, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"], [&"wheel_angle", &"brake_lights"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var p := t.puppet(&"me")
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets in"):
		return
	await t.seconds(0.5)
	t.check(absf(car.wheel_angle()) < 0.02, "the wheels start straight (%.3f rad)" % car.wheel_angle())

	# --- At rest: D, A, centre.
	p.drive(0.0, 1.0, false)
	await t.frames(2)
	var early: float = car.wheel_angle()
	await t.seconds(0.6)
	var right_lock: float = car.wheel_angle()
	t.check(right_lock > 0.1, "D turns the front wheels right (%.2f rad)" % right_lock)
	t.check(early < right_lock * 0.8, "easing toward it, not snapping (%.2f two frames in)" % early)
	p.drive(0.0, -1.0, false)
	await t.seconds(0.8)
	t.check(car.wheel_angle() < -0.1, "A turns them left (%.2f rad)" % car.wheel_angle())
	p.drive(0.0, 0.0, false)
	await t.seconds(0.8)
	t.check(absf(car.wheel_angle()) < 0.02, "letting go centres them (%.3f rad)" % car.wheel_angle())

	# --- Brake lights: off on the throttle and coasting, on while S slows the car.
	p.drive(1.0, 0.0, false)
	await t.seconds(1.0)
	t.check(not car.brake_lights(), "no brake lights on the throttle")
	if not t.require(await Probe.reach_speed(t, &"me", car, 150.0, 6.0), "the car reaches 150 px/s"):
		return
	await t.frames(3)
	t.check(not car.brake_lights(), "none while coasting")
	p.drive(-1.0, 0.0, false)
	await t.frames(3)
	t.check(car.brake_lights() and Probe.along(car) > 0.0, "the brake lights show while S slows the car")
	p.drive(1.0, 0.0, false)
	await t.frames(3)
	t.check(not car.brake_lights(), "and go off again on the throttle")

	# --- At speed full steer turns the wheels less far.
	await Probe.reach_speed(t, &"me", car, 150.0, 4.0)
	p.drive(1.0, 1.0, false)
	await t.seconds(0.6)
	var at_speed: float = car.wheel_angle()
	p.drive(0.0, 0.0, false)
	t.check(at_speed > 0.0 and at_speed < right_lock * 0.8, "at speed full steer turns the wheels less (%.2f against %.2f rad at rest)" % [at_speed, right_lock])
