extends GameTest

## V5 (ticket #54): below the grip limit the car goes where its wheels point. A full-steer turn at about 40 px/s turns the
## car round about its rear axle: the pivot (the point on the centre line with no sideways velocity) stays in the rear half
## of the body, and slip() stays under 0.05.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Grip holds a slow turn",
		"description": "Full steer at about 40 px/s for 2.5 s: the car turns, its pivot stays between the tail and the centre, and slip() stays under 0.05.",
		"tags": ["vehicle", "car", "drive", "grip", "steer"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 800), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(400, 250))
	s.actor(&"me", &"puppet", Vector2(150, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var tail := Probe.tail_offset(car).x
	if not t.require(await Probe.board_by(t, &"me", car, &"front_left"), "the driver gets in"):
		return
	await Probe.hold_speed(t, &"me", car, 40.0, 0.0, false, 1.0)
	var heading := car.global_rotation
	# [the most forward pivot, the most rearward, the peak slip(), frames turning] (an Array: a lambda captures plain
	# locals by value).
	var seen := [-INF, INF, 0.0, 0]
	await Probe.hold_speed(t, &"me", car, 40.0, 1.0, false, 0.5)
	await Probe.hold_speed(t, &"me", car, 40.0, 1.0, false, 2.0, func():
		var x := Probe.pivot(car)
		if x != INF:
			seen[0] = maxf(seen[0], x)
			seen[1] = minf(seen[1], x)
			seen[3] += 1
		seen[2] = maxf(seen[2], float(car.slip())))
	t.check(car.speed() > 25.0 and car.speed() < 60.0, "the car is held near 40 px/s (%.0f px/s)" % car.speed())
	t.check(absf(angle_difference(heading, car.global_rotation)) > 0.3, "it turns (%.2f rad)" % angle_difference(heading, car.global_rotation))
	if t.check(seen[3] > 30, "it turns through most of the frames (%d)" % seen[3]):
		t.check(seen[0] <= 2.0 and seen[1] >= tail - 2.0, "it pivots in the rear half of the body: between %.1f and %.1f px off the centre, the tail at %.1f" % [seen[1], seen[0], tail])
	t.check(seen[2] < 0.05, "slip() stays near 0 (%.3f)" % seen[2])
