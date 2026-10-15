extends GameTest

## V4 (ticket #54): with no clear door, E leaves the character in: characters stand in all four doors' swing, the driver
## presses E and nothing opens. Once one door is cleared, E gets it out by that door.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const BLOCKERS := { &"block_fl": &"front_left", &"block_fr": &"front_right", &"block_rl": &"rear_left", &"block_rr": &"rear_right" }


func describe() -> Dictionary:
	return {
		"name": "With every door blocked the character stays in",
		"description": "Four puppets stand in the swing of the car's four doors: the driver's E opens nothing and it stays seated; with the front-right blocker gone, E gets it out there.",
		"tags": ["vehicle", "car", "exit", "door", "blocked"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))
	var x := 80.0
	for id in BLOCKERS:
		s.actor(id, &"puppet", Vector2(x, 540), { "max_health": 100000.0 })
		x += 80.0


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the character gets in at the front left"):
		return
	await t.until(func(): return Probe.open_of(car, &"front_left") < 0.05, 2.0, "the door shuts behind it")
	for id in BLOCKERS:
		await Probe.place(t, id, Probe.stand_point(car, BLOCKERS[id], 18.0))

	t.puppet(&"me").use_vehicle()
	var watched: Dictionary = await Probe.watch_doors(t, car, func(): return false, 2.0)
	t.expect_eq(Probe.opened(watched, 0.05), [], "no door opens")
	t.check(me.is_in_vehicle() and me.vehicle() == car, "the character stays in")
	t.expect_eq(Probe.seat_of(car, me), &"driver", "in its seat")

	await Probe.place(t, &"block_fr", Vector2(820, 560))
	t.puppet(&"me").use_vehicle()
	watched = await Probe.watch_doors(t, car, func(): return me.vehicle() == null, 8.0)
	if not t.require(watched["done"], "with the front right cleared, E gets the character out"):
		return
	t.expect_eq(Probe.opened(watched, 0.05), [&"front_right"], "by the front-right door")
