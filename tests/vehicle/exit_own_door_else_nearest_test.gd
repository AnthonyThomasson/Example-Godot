extends GameTest

## V4 (ticket #54): E while seated gets out by the character's own door when that is clear, stepping out beside it on its
## side. With its own door blocked (here both left doors, by characters standing in their swing), it gets out by the
## nearest clear door instead: the front right, across the car.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Exits by its own door, else the nearest clear one",
		"description": "The driver gets out by the front-left door and stands beside it; with both left doors blocked by characters it gets out by the front-right door onto the right side.",
		"tags": ["vehicle", "car", "exit", "door"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))
	s.actor(&"block_front", &"puppet", Vector2(80, 540), { "max_health": 100000.0 })
	s.actor(&"block_rear", &"puppet", Vector2(160, 540), { "max_health": 100000.0 })


## Press E for the seated character and watch the doors until it is out. Returns the `watch_doors` result.
func _get_out(t: TestContext, car: Node2D) -> Dictionary:
	var me := t.actor(&"me")
	t.puppet(&"me").use_vehicle()
	return await Probe.watch_doors(t, car, func(): return me.vehicle() == null, 8.0)


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the character gets in at the front left"):
		return
	await t.until(func(): return Probe.open_of(car, &"front_left") < 0.05, 2.0, "the door shuts behind it")

	# --- Its own door is clear.
	var out: Dictionary = await _get_out(t, car)
	if not t.require(out["done"], "E gets the character out"):
		return
	t.expect_eq(Probe.opened(out), [&"front_left"], "by its own door, the front left")
	var handle := Probe.door(car, &"front_left")["handle"] as Vector2
	t.check(me.global_position.distance_to(handle) <= Probe.DOOR_REACH, "it stands beside that door (%.0f px from the handle)" % me.global_position.distance_to(handle))
	t.check((me.global_position - car.global_position).dot(Probe.right(car)) < 0.0, "on the car's left side")
	t.check(not me.is_in_vehicle() and Probe.seat_of(car, me) == &"", "it holds no seat")
	await t.until(func(): return Probe.open_of(car, &"front_left") < 0.05, 2.0, "the door shuts behind it")

	# --- Both left doors blocked by characters standing in their swing.
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the character gets back in at the front left"):
		return
	await t.until(func(): return Probe.open_of(car, &"front_left") < 0.05, 2.0, "the door shuts behind it")
	await Probe.place(t, &"block_front", Probe.stand_point(car, &"front_left", 18.0))
	await Probe.place(t, &"block_rear", Probe.stand_point(car, &"rear_left", 18.0))
	out = await _get_out(t, car)
	if not t.require(out["done"], "E still gets the character out"):
		return
	t.expect_eq(Probe.opened(out, 0.05), [&"front_right"], "by the nearest clear door, the front right")
	handle = Probe.door(car, &"front_right")["handle"] as Vector2
	t.check(me.global_position.distance_to(handle) <= Probe.DOOR_REACH, "it stands beside that door (%.0f px from the handle)" % me.global_position.distance_to(handle))
	t.check((me.global_position - car.global_position).dot(Probe.right(car)) > 0.0, "on the car's right side")
