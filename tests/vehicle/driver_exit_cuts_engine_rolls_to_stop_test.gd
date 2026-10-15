extends GameTest

## V4 (ticket #54): a driver sitting down starts the engine; a driver leaving cuts it, and the car, rolling when it got out,
## rolls to a stop under rolling friction: never speeding up, at rest within a few seconds, and staying there.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A driver leaving cuts the engine and the car rolls to a stop",
		"description": "The engine runs once the driver sits; the driver gets out while the car rolls at under 20 px/s: the engine stops and the car slows to rest without speeding up.",
		"tags": ["vehicle", "car", "exit", "engine"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(250, 300))
	s.actor(&"me", &"puppet", Vector2(120, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	t.check(not car.engine_state().get("running", false), "a parked car's engine is off")
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets in"):
		return
	t.check(await t.until(func(): return car.engine_state().get("running", false), 2.0), "the engine starts once the driver sits")

	if not t.require(await Probe.reach_speed(t, &"me", car, 40.0, 5.0), "the car reaches 40 px/s"):
		return
	if not t.require(await t.until(func(): return car.speed() <= Probe.EXIT_MAX_SPEED - 2.0, 15.0), "it coasts down under %.0f px/s" % Probe.EXIT_MAX_SPEED):
		return
	var rolling: float = car.speed()
	t.puppet(&"me").use_vehicle()
	# [the most speed gained in one frame, last frame's speed] (an Array: a lambda captures plain locals by value).
	var speeds := [0.0, rolling]
	var sample := func() -> void:
		speeds[0] = maxf(speeds[0], car.speed() - speeds[1])
		speeds[1] = car.speed()
	if not t.require(await t.until(func():
		sample.call()
		return me.vehicle() == null, 8.0), "the driver gets out (at %.1f px/s)" % rolling):
		return
	t.check(not car.engine_state().get("running", true), "the engine is cut once the driver has left")
	var stopped := await t.until(func():
		sample.call()
		return car.speed() < 1.0, 6.0)
	t.check(stopped, "the car rolls to a stop (%.2f px/s)" % car.speed())
	t.check(speeds[0] < 0.5, "it never speeds up on its own (most gained in a frame %.2f px/s)" % speeds[0])
	var rest := car.global_position
	await t.seconds(1.0)
	t.check(car.global_position.distance_to(rest) < 1.0, "and stays at rest")
	t.check(not car.engine_state().get("running", true), "with the engine off")
