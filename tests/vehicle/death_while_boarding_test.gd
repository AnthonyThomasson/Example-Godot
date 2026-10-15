extends GameTest

## V3 (ticket #54): boarding cannot be interrupted, except by death. A character killed half-way into the car falls where it
## is: it is not carried on into the seat, its ride ends (no vehicle, no seat), and the door it was using stays open.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Death while boarding",
		"description": "A puppet is killed once the front-left door is half open: it dies where it stands, takes no seat, its vehicle() is null and the door stays open.",
		"tags": ["vehicle", "car", "board", "death", "door"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	if not t.require(Probe.door(car, &"front_left").has("handle"), "the car reports its front-left handle"):
		return
	await Probe.place(t, &"me", Probe.stand_point(car, &"front_left"))
	t.puppet(&"me").use_vehicle()
	if not t.require(await t.until(func(): return Probe.open_of(car, &"front_left") >= 0.5, 3.0), "the front-left door opens for the boarding"):
		return
	t.check(not me.is_in_vehicle(), "the character is still on its way in")
	t.check(me.vehicle() == car, "with the boarding under way, vehicle() is the car")

	var died_at: Vector2 = me.global_position
	me.take_damage(1.0e6)
	await t.frames(1)
	t.check(me.is_dead, "the character dies")
	await t.seconds(2.0)
	t.check(me.global_position.distance_to(died_at) < 20.0, "it falls where it was (%.1f px off)" % me.global_position.distance_to(died_at))
	t.check(me.vehicle() == null, "its ride has ended (vehicle() is null)")
	t.check(not me.is_in_vehicle(), "it is not in the car")
	t.expect_eq(Probe.seat_of(car, me), &"", "it holds no seat")
	t.check(Probe.occupant(car, &"driver") == null, "the driver's seat is empty")
	t.check(Probe.open_of(car, &"front_left") >= 0.5, "the door stays open (%.2f)" % Probe.open_of(car, &"front_left"))
