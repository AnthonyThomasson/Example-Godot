extends GameTest

## V5 / F7 (ticket #54, feedback round 3): top speeds a driver really reaches. The car's top speed
## is 1280 px/s (about 92 km/h at ~50 px/m) and the van's 880 px/s (the plan's numbers, not VehicleConfig's).
## A car and a van, each with a driver, hold full throttle
## down a long straight: each reaches at least 95% of its top speed and never goes more than 2% past it (held on for a
## few seconds once there, to see where it settles). The launch and the brakes are `vehicle/launch_and_brake`.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## id -> [driver, new top speed (px/s)].
const KINDS := {
	&"car": [&"c", 1280.0],
	&"van": [&"v", 880.0],
}
## The share of its top speed each must reach, and the most it may go past it.
const REACH := 0.95
const OVERSHOOT := 1.02
## The longest full-throttle run (s); once a vehicle reaches its share it keeps the throttle on this much longer.
const RUN_TIME := 16.0
const HOLD_AFTER := 3.0
## How far short of the far wall (px) a driver lifts off and brakes: more than a stop from 1280 px/s takes (within
## 2 s, so at most ~1280 px on a steady deceleration).
const BRAKE_BEFORE_WALL := 2500.0
## Long enough for the car to reach 95% of 1280 px/s (about 2000 px at the plan's launch), hold it 3 s (3840 px) and
## still lift off before BRAKE_BEFORE_WALL.
const ARENA := Rect2(0, 0, 18000, 900)


func describe() -> Dictionary:
	return {
		"name": "Car and van reach their top speeds",
		"description": "On full throttle down a long straight the car reaches at least 95% of 1280 px/s and the van of 880 px/s, and neither goes more than 2% past it.",
		"tags": ["vehicle", "car", "van", "drive", "speed"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA, { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.vehicle(&"van", &"van", Vector2(300, 620))
	s.actor(&"c", &"puppet", Vector2(150, 120))
	s.actor(&"v", &"puppet", Vector2(150, 820))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"c", &"v"]) or not Probe.ready(t, &"van"):
		return
	for id in KINDS:
		if not t.require(await Probe.board_by(t, KINDS[id][0], t.vehicle(id) as Node2D, &"front_left"), "a driver gets into the %s" % id):
			return
	await t.seconds(0.5)

	# Full throttle, straight ahead, each until it has held its share of the top speed for HOLD_AFTER s, the run ends or
	# its nose nears the far wall; the peak speed of each.
	var peak := { &"car": 0.0, &"van": 0.0 }
	var reached_at := { &"car": -1.0, &"van": -1.0 }
	var lifted := { &"car": false, &"van": false }
	var deadline := t.time + RUN_TIME
	while t.time < deadline and not (lifted[&"car"] and lifted[&"van"]):
		for id in KINDS:
			var v := t.vehicle(id) as Node2D
			if reached_at[id] < 0.0 and v.speed() >= REACH * float(KINDS[id][1]):
				reached_at[id] = t.time
			if reached_at[id] >= 0.0 and t.time > reached_at[id] + HOLD_AFTER:
				lifted[id] = true
			if Probe.edge(v, Probe.forward(v)).x > ARENA.end.x - BRAKE_BEFORE_WALL:
				lifted[id] = true
			t.puppet(KINDS[id][0]).drive(-1.0 if lifted[id] else 1.0, 0.0, false)
		await t.frames(1)
		for id in KINDS:
			peak[id] = maxf(peak[id], float(t.vehicle(id).speed()))
			t.trace("%s speed" % id, t.vehicle(id).speed())
	for id in KINDS:
		t.puppet(KINDS[id][0]).drive(-1.0, 0.0, false)

	for id in KINDS:
		var top: float = KINDS[id][1]
		t.check(peak[id] >= REACH * top, "the %s reaches its top speed (peak %.0f px/s, at least %.0f of %.0f)" % [id, peak[id], REACH * top, top])
		t.check(peak[id] <= OVERSHOOT * top, "and never goes past it (peak %.0f px/s, at most %.0f)" % [peak[id], OVERSHOOT * top])
