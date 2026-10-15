extends GameTest

## V1 (ticket #54): E boards by the door whose handle is nearest the character, among those within reach (60 px). A
## character standing just out of the front-left door, with the rear-left handle also in reach, gets in at the front left
## and takes the driver's seat; one at the rear right gets in there and takes the rear-right seat. Only the chosen door opens.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Boards by the nearest door",
		"description": "The car has its four doors; a puppet beside the front-left handle boards by it into the driver's seat, one beside the rear-right handle by that door into the rear-right seat, and no other door opens.",
		"tags": ["vehicle", "car", "board", "door"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"front", &"puppet", Vector2(150, 100))
	s.actor(&"rear", &"puppet", Vector2(750, 520))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"front", &"rear"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var doors := {}
	for d: Dictionary in car.doors():
		doors[d.get("id")] = [d.get("kind"), d.get("seat")]
	t.expect_eq(doors, Probe.CAR_DOORS, "the car has four swing doors, each in front of its seat")
	t.expect_eq(Probe.sorted(car.seats().map(func(s): return s.get("id"))), Probe.sorted(Probe.CAR_SEATS), "the car's seats")
	if not t.require(Probe.door(car, &"front_left").has("handle") and Probe.door(car, &"rear_right").has("handle"), "the doors report their handles"):
		return

	# --- Front left: the rear-left handle is in reach too, but further.
	var at := Probe.stand_point(car, &"front_left")
	var near := Probe.door(car, &"front_left")["handle"] as Vector2
	var other := Probe.door(car, &"rear_left")["handle"] as Vector2
	t.check(at.distance_to(near) < at.distance_to(other), "the front-left handle is the nearest from the stand point")
	await Probe.place(t, &"front", at)
	var front := t.actor(&"front")
	t.puppet(&"front").use_vehicle()
	var watched: Dictionary = await Probe.watch_doors(t, car, func(): return front.is_in_vehicle(), 6.0)
	if not t.require(watched["done"], "the character at the front left gets in"):
		return
	t.expect_eq(Probe.opened(watched), [&"front_left"], "only the front-left door opened")
	t.expect_eq(Probe.seat_of(car, front), &"driver", "it sits in the driver's seat")
	t.check(front.vehicle() == car, "its vehicle() is the car")
	t.check(car.driver() == front, "the car's driver() is it")
	await t.until(func(): return Probe.open_of(car, &"front_left") < 0.05, 2.0, "the front-left door shuts behind it")

	# --- Rear right.
	await Probe.place(t, &"rear", Probe.stand_point(car, &"rear_right"))
	var rear := t.actor(&"rear")
	t.puppet(&"rear").use_vehicle()
	watched = await Probe.watch_doors(t, car, func(): return rear.is_in_vehicle(), 6.0)
	if not t.require(watched["done"], "the character at the rear right gets in"):
		return
	t.expect_eq(Probe.opened(watched), [&"rear_right"], "only the rear-right door opened")
	t.expect_eq(Probe.seat_of(car, rear), &"rear_right", "it sits in the rear-right seat")
	t.expect_eq(Probe.seat_of(car, front), &"driver", "the driver stays where it is")
