extends GameTest

## V1 (ticket #54): a door that cannot open is skipped for the next nearest that can. The car is parked in the open with an
## armchair standing just off its left side, in the rear-left door's swing, so that door cannot open. A character on the
## car's left side between the rear-left and front-left handles, nearer the rear-left, with both in reach: E boards by the
## front-left door into the driver's seat, and the rear-left door never opens.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const CAR_AT := Vector2(450, 300)
## Where the armchair stands, off the car's rear-left corner: its near corner reaches into the rear-left door's swing.
const CHAIR_AT := CAR_AT + Vector2(-90, -90)


func describe() -> Dictionary:
	return {
		"name": "Boarding skips a blocked door",
		"description": "An armchair stands in the rear-left door's swing; a puppet on the car's left side with the rear-left handle nearest boards by the front-left door instead, into the driver's seat, and the rear-left door never opens.",
		"tags": ["vehicle", "car", "board", "door", "blocked"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.object(&"chair", "armchair", CHAIR_AT)
	s.actor(&"me", &"puppet", Vector2(150, 500))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var chair := t.object(&"chair") as Node2D
	if not t.require(Probe.door(car, &"rear_left").has("handle") and Probe.door(car, &"front_left").has("handle"), "the car reports its left doors' handles"):
		return
	var rear := Probe.door(car, &"rear_left")
	var rear_handle := rear["handle"] as Vector2
	var front_handle := Probe.door(car, &"front_left")["handle"] as Vector2

	# The armchair is in the rear-left door's swing: its nearest point to the hinge is within the door's length of it, out
	# from the car's left side.
	var hinge := rear["hinge"] as Vector2
	var half := (chair.get("size") as Vector2) / 2.0
	var nearest := hinge.clamp(chair.global_position - half, chair.global_position + half)
	var out := -Probe.right(car)
	if not t.require(nearest.distance_to(hinge) < hinge.distance_to(rear_handle) and (nearest - hinge).dot(out) > 2.0,
			"the armchair stands in the rear-left door's swing (%.0f px from its hinge, the door %.0f px long)" % [nearest.distance_to(hinge), hinge.distance_to(rear_handle)]):
		return

	# On the left side between the two handles, nearer the rear-left: both in reach.
	var at := rear_handle.lerp(front_handle, 0.44) + out * 17.0
	if not t.require(at.distance_to(rear_handle) < at.distance_to(front_handle), "between the left handles the rear-left one is the nearest"):
		return
	if not t.require(at.distance_to(front_handle) <= Probe.DOOR_REACH, "and the front-left handle is in reach too (%.0f px)" % at.distance_to(front_handle)):
		return
	await Probe.place(t, &"me", at)
	var me := t.actor(&"me")
	t.puppet(&"me").use_vehicle()
	var watched: Dictionary = await Probe.watch_doors(t, car, func(): return me.is_in_vehicle(), 8.0)
	if not t.require(watched["done"], "the character gets in"):
		return
	t.expect_eq(Probe.opened(watched, 0.05), [&"front_left"], "only the front-left door opened (the armchair blocks the rear-left one)")
	t.expect_eq(Probe.seat_of(car, me), &"driver", "it sits in the driver's seat")
