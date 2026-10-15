extends GameTest

## V1 (ticket #54): a door whose seat is taken cannot open, so E skips it for the next nearest that can. One character
## boards at the front left and drives; a second one at the same spot gets the rear-left door and seat instead, and the
## front-left door stays shut while it boards.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Boarding skips a door whose seat is taken",
		"description": "With the driver's seat taken, a puppet at the front-left door boards by the rear-left door into the rear-left seat; the front-left door does not open.",
		"tags": ["vehicle", "car", "board", "door", "seat"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"driver", &"puppet", Vector2(150, 100))
	s.actor(&"second", &"puppet", Vector2(150, 520))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"driver", &"second"]):
		return
	var car := t.vehicle(&"car") as Node2D
	if not t.require(Probe.door(car, &"front_left").has("handle"), "the car reports its front-left handle"):
		return
	var at := Probe.stand_point(car, &"front_left")
	if not t.require(await Probe.board_by(t, &"driver", car, &"front_left"), "the first character gets in at the front left"):
		return
	t.expect_eq(Probe.seat_of(car, t.actor(&"driver")), &"driver", "and drives")
	await t.until(func(): return Probe.open_of(car, &"front_left") < 0.05, 2.0, "the front-left door shuts")

	var rear_handle := Probe.door(car, &"rear_left")["handle"] as Vector2
	if not t.require(at.distance_to(rear_handle) <= Probe.DOOR_REACH, "the rear-left handle is in reach of the front-left stand point (%.0f px)" % at.distance_to(rear_handle)):
		return
	await Probe.place(t, &"second", at)
	var second := t.actor(&"second")
	t.puppet(&"second").use_vehicle()
	var watched: Dictionary = await Probe.watch_doors(t, car, func(): return second.is_in_vehicle(), 8.0)
	if not t.require(watched["done"], "the second character gets in"):
		return
	t.check(watched["max"].get(&"front_left", 0.0) < 0.05, "the front-left door stayed shut (its seat is taken)")
	t.expect_eq(Probe.opened(watched), [&"rear_left"], "the rear-left door opened instead")
	t.expect_eq(Probe.seat_of(car, second), &"rear_left", "it sits in the rear-left seat")
	t.expect_eq(Probe.seat_of(car, t.actor(&"driver")), &"driver", "the driver keeps its seat")
