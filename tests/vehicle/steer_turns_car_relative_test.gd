extends GameTest

## V5 (ticket #54): A/D steer relative to the car, like a bicycle: D turns the car to its own right whichever way it faces,
## A to its left, and steering does not turn a car that is not moving. One car faces east and one west; with W+D both turn
## clockwise on screen (each to its own right: the east one heads south, the west one north).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## W is let up above this speed (px/s) and pressed again below it, so the turns stay in the arena and clear of each other
## however hard the car launches (F4: about 1000 px/s after 1.5 s of W).
const CRUISE := 150.0


func describe() -> Dictionary:
	return {
		"name": "Steering is relative to the car",
		"description": "D alone turns neither parked car; W+D turns an east-facing and a west-facing car each to its own right; W+A to its left.",
		"tags": ["vehicle", "car", "drive", "steer"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 1000), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"east", &"car", Vector2(400, 300), 0.0)
	s.vehicle(&"west", &"car", Vector2(1200, 700), PI)
	s.actor(&"e", &"puppet", Vector2(150, 80))
	s.actor(&"w", &"puppet", Vector2(1450, 920))


## Both drivers hold the same keys for `duration` s (the throttle let up above CRUISE); returns each car's turn (rad, + =
## clockwise).
func _hold(t: TestContext, cars: Array, throttle: float, steer: float, duration: float) -> Array:
	var before := cars.map(func(c): return c.global_rotation)
	var deadline := t.time + duration
	while t.time < deadline:
		t.puppet(&"e").drive(throttle if cars[0].speed() < CRUISE else 0.0, steer, false)
		t.puppet(&"w").drive(throttle if cars[1].speed() < CRUISE else 0.0, steer, false)
		await t.frames(1)
	t.puppet(&"e").drive(0.0, 0.0, false)
	t.puppet(&"w").drive(0.0, 0.0, false)
	return [angle_difference(before[0], cars[0].global_rotation), angle_difference(before[1], cars[1].global_rotation)]


## Brake both cars to a stop.
func _stop(t: TestContext, cars: Array) -> void:
	for i in 2:
		var id: StringName = [&"e", &"w"][i]
		var car: Node2D = cars[i]
		t.puppet(id).drive(-1.0 if Probe.along(car) > 0.0 else 1.0, 0.0, false)
		await t.until(func(): return car.speed() < 3.0, 4.0)
		t.puppet(id).drive(0.0, 0.0, false)


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"east", [&"e", &"w"]) or not Probe.ready(t, &"west"):
		return
	var cars := [t.vehicle(&"east"), t.vehicle(&"west")]
	if not t.require(await Probe.board_by(t, &"e", cars[0], &"front_left"), "a driver gets into the east-facing car"):
		return
	if not t.require(await Probe.board_by(t, &"w", cars[1], &"front_left"), "a driver gets into the west-facing car"):
		return
	await t.seconds(0.5)

	var turned: Array = await _hold(t, cars, 0.0, 1.0, 1.0)
	t.check(absf(turned[0]) < 0.02 and absf(turned[1]) < 0.02, "D alone turns neither parked car (%.3f, %.3f rad)" % turned)

	turned = await _hold(t, cars, 1.0, 1.0, 1.5)
	t.check(turned[0] > 0.3, "W+D turns the east-facing car to its right, clockwise (%.2f rad)" % turned[0])
	t.check(turned[1] > 0.3, "and the west-facing car to its own right, clockwise too (%.2f rad)" % turned[1])
	t.check((cars[0].linear_velocity as Vector2).y > 0.0, "the east-facing car heads south")
	t.check((cars[1].linear_velocity as Vector2).y < 0.0, "the west-facing car heads north")
	await _stop(t, cars)

	turned = await _hold(t, cars, 1.0, -1.0, 1.5)
	t.check(turned[0] < -0.3 and turned[1] < -0.3, "W+A turns both to their own left, anticlockwise (%.2f, %.2f rad)" % turned)
