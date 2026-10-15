extends GameTest

## V5 / F4, F7 (ticket #54, feedback rounds 2 and 3): an arcade-punchy launch and brakes to match. On full throttle from
## rest the car reaches 640 px/s (half its 1280 top) within 1.1 s and the van 440 px/s (half its 880 top) within 1.4 s; from its top speed S stops the car within 2.0 s and the van within 2.5 s (about as long as the
## launch to it). The plan's numbers, not VehicleConfig's.
##
## Four vehicles, one driver each, in lanes of their own. Two launch from rest. The other two are set rolling at the
## plan's top speed straight ahead (through `linear_velocity`, as `vehicle/hits_character_damage_by_speed` sets an empty
## car going) and braked at once: the brake check then measures the brakes alone, not whether the engine gets there
## (that is `vehicle/top_speed`).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## Launch lanes: id -> [driver, kind, target speed (px/s), within (s)].
const LAUNCH := {
	&"car_go": [&"cg", &"car", 640.0, 1.1],
	&"van_go": [&"vg", &"van", 440.0, 1.4],
}
## Brake lanes: id -> [driver, kind, top speed (px/s), stop within (s)].
const BRAKE := {
	&"car_stop": [&"cs", &"car", 1280.0, 2.0],
	&"van_stop": [&"vs", &"van", 880.0, 2.5],
}
## The longest a launch is held (s): past the plan's 1.1 / 1.4 s, so a slow launch is measured, not cut off.
const LAUNCH_RUN := 3.0
## The longest a brake is held (s).
const BRAKE_RUN := 6.0
## Stopped: rolling forward no faster than this (px/s).
const STOPPED := 2.0
## Room for a stop from 1280 px/s (about 1.5 s, ~1000 px) and from the launch lanes' 3 s run.
const ARENA := Rect2(0, 0, 4400, 1600)


func describe() -> Dictionary:
	return {
		"name": "Car and van launch and brake hard",
		"description": "Full throttle from rest: the car reaches 640 px/s within 1.1 s and the van 440 px/s within 1.4 s. S from the top speed: the car (1280 px/s) stops within 2.0 s, the van (880 px/s) within 2.5 s.",
		"tags": ["vehicle", "car", "van", "drive", "speed", "brake"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA, { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	var y := 200.0
	for id in LAUNCH:
		s.vehicle(id, LAUNCH[id][1], Vector2(300, y))
		s.actor(LAUNCH[id][0], &"puppet", Vector2(120, y - 120))
		y += 400.0
	for id in BRAKE:
		s.vehicle(id, BRAKE[id][1], Vector2(300, y))
		s.actor(BRAKE[id][0], &"puppet", Vector2(120, y - 120))
		y += 400.0


func run(t: TestContext) -> void:
	for id in LAUNCH:
		if not Probe.ready(t, id, [LAUNCH[id][0]]):
			return
	for id in BRAKE:
		if not Probe.ready(t, id, [BRAKE[id][0]]):
			return
	for lanes in [LAUNCH, BRAKE]:
		for id in lanes:
			if not t.require(await Probe.board_by(t, lanes[id][0], t.vehicle(id) as Node2D, &"front_left"), "a driver gets into %s" % id):
				return
	await t.seconds(0.5)

	# --- The launch: full throttle from rest; when each reaches its target, and how fast it was at its deadline.
	var reached := {}
	var at_deadline := {}
	for id in LAUNCH:
		t.puppet(LAUNCH[id][0]).drive(1.0, 0.0, false)
	var start := t.time
	while t.time < start + LAUNCH_RUN and reached.size() < LAUNCH.size():
		await t.frames(1)
		for id in LAUNCH:
			var v := t.vehicle(id) as Node2D
			t.trace("%s speed" % id, v.speed())
			if not at_deadline.has(id) and t.time - start >= float(LAUNCH[id][3]):
				at_deadline[id] = v.speed()
			if not reached.has(id) and v.speed() >= float(LAUNCH[id][2]):
				reached[id] = t.time - start
				t.puppet(LAUNCH[id][0]).drive(-1.0, 0.0, false)
	for id in LAUNCH:
		t.puppet(LAUNCH[id][0]).drive(-1.0, 0.0, false)
		var target: float = LAUNCH[id][2]
		var within: float = LAUNCH[id][3]
		if reached.has(id):
			t.check(reached[id] <= within, "the %s reaches %.0f px/s within %.1f s (took %.2f s)" % [LAUNCH[id][1], target, within, reached[id]])
		else:
			t.check(false, "the %s reaches %.0f px/s within %.1f s (only %.0f px/s at %.1f s, under %.0f after %.1f s)" % [LAUNCH[id][1], target, within, float(at_deadline.get(id, 0.0)), within, target, LAUNCH_RUN])

	# --- The brakes: each set rolling at its top speed straight ahead, S held at once until it stops.
	for id in BRAKE:
		var v := t.vehicle(id) as Node2D
		v.set("linear_velocity", Probe.forward(v) * float(BRAKE[id][2]))
		t.puppet(BRAKE[id][0]).drive(-1.0, 0.0, false)
	start = t.time
	var stopped := {}
	var first := {}
	while t.time < start + BRAKE_RUN and stopped.size() < BRAKE.size():
		await t.frames(1)
		for id in BRAKE:
			var v := t.vehicle(id) as Node2D
			t.trace("%s speed" % id, v.speed())
			if not first.has(id):
				first[id] = v.speed()  # what it rolled at once the brakes were on (a premise: it really started at the top)
			if not stopped.has(id) and Probe.along(v) <= STOPPED:
				stopped[id] = t.time - start
				t.puppet(BRAKE[id][0]).drive(0.0, 0.0, false)
	for id in BRAKE:
		t.puppet(BRAKE[id][0]).drive(0.0, 0.0, false)
		var top: float = BRAKE[id][2]
		var within: float = BRAKE[id][3]
		t.check(float(first.get(id, 0.0)) >= 0.97 * top, "the %s starts its stop at its top speed (%.0f px/s on the first frame, %.0f set)" % [BRAKE[id][1], float(first.get(id, 0.0)), top])
		if stopped.has(id):
			t.check(stopped[id] <= within, "S stops the %s from %.0f px/s within %.1f s (took %.2f s)" % [BRAKE[id][1], top, within, stopped[id]])
		else:
			var v := t.vehicle(id) as Node2D
			t.check(false, "S stops the %s from %.0f px/s within %.1f s (still at %.0f px/s after %.1f s)" % [BRAKE[id][1], top, within, v.speed(), BRAKE_RUN])
