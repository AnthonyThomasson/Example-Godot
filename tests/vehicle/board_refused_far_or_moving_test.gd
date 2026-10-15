extends GameTest

## V1 (ticket #54): E does nothing when no door is usable: with every handle out of reach (more than 60 px), or while the
## vehicle moves at board_max_speed (20 px/s) or faster. Nothing opens and the character stays on foot. Then, in reach of a
## stopped car, the same press boards (so the refusals are the rule, not a car that never takes anyone).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Boarding is refused out of reach or while rolling",
		"description": "E 75 px from the nearest handle, and E beside a car rolling at 80 px/s, open nothing and leave the puppet on foot; beside the stopped car E boards.",
		"tags": ["vehicle", "car", "board", "door", "reach"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(400, 300))
	s.actor(&"me", &"puppet", Vector2(150, 520))


## Press E and watch 1.5 s: true when nothing opened and the character stayed on foot.
func _refused(t: TestContext, car: Node2D, me: Node) -> bool:
	t.puppet(&"me").use_vehicle()
	var watched: Dictionary = await Probe.watch_doors(t, car, func(): return false, 1.5)
	return Probe.opened(watched, 0.05).is_empty() and me.vehicle() == null and not me.is_in_vehicle()


## The distance from `at` to the nearest door handle of `car`.
func _nearest_handle(car: Node2D, at: Vector2) -> float:
	var best := INF
	for d: Dictionary in car.doors():
		best = minf(best, at.distance_to(d["handle"]))
	return best


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	if not t.require(Probe.door(car, &"front_left").has("handle"), "the car reports its front-left handle"):
		return

	# --- Out of reach: 75 px straight out from the front-left handle.
	var far := Probe.stand_point(car, &"front_left", 75.0)
	t.check(_nearest_handle(car, far) > Probe.DOOR_REACH, "the spot is out of reach of every handle (%.0f px)" % _nearest_handle(car, far))
	await Probe.place(t, &"me", far)
	t.check(await _refused(t, car, me), "out of reach, E opens nothing and the character stays on foot")

	# --- Rolling: beside the front-left handle while the car rolls forward at 80 px/s.
	await Probe.place(t, &"me", Probe.stand_point(car, &"front_left"))
	car.set("linear_velocity", Probe.forward(car) * 80.0)
	await t.frames(1)
	t.check(car.speed() > Probe.BOARD_MAX_SPEED, "the car is rolling faster than board_max_speed when E is pressed (%.0f px/s)" % car.speed())
	t.check(await _refused(t, car, me), "while the car rolls, E opens nothing and the character stays on foot")

	# --- Stopped and in reach: E boards.
	if not t.require(await t.until(func(): return car.speed() < 1.0, 10.0), "the car rolls to a stop"):
		return
	t.check(await Probe.board_by(t, &"me", car, &"front_left"), "beside the stopped car, E boards")
