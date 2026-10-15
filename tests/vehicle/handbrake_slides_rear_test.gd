extends GameTest

## V5 (ticket #54): each axle cancels its sideways slip up to a grip limit, and the handbrake (the run key) drops the rear
## grip so the back end slides out. At 120 px/s a full-steer handbrake turn swings the tail out: the body's velocity points
## outside its heading (the body slip angle toward the outside of the turn tops 0.2 rad), and slip() rises. The same turn at
## the same speed without the handbrake slides less.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const SPEED := 120.0


func describe() -> Dictionary:
	return {
		"name": "The handbrake slides the rear out",
		"description": "At 120 px/s, full steer with the handbrake: the body slip angle toward the outside of the turn tops 0.2 rad and slip() rises; without the handbrake it slides less.",
		"tags": ["vehicle", "car", "drive", "handbrake", "drift"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2600, 1400), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"slide", &"car", Vector2(300, 400))
	s.vehicle(&"grip", &"car", Vector2(300, 1000))
	s.actor(&"a", &"puppet", Vector2(120, 80))
	s.actor(&"b", &"puppet", Vector2(120, 1320))


## Drive `car` (puppet `id`) up to SPEED, then hold a full right turn (with or without the handbrake) for 1 s.
## Returns `{ reached, out, slip }`: the peak body slip angle toward the outside of the turn, and the peak slip().
func _turn(t: TestContext, id: StringName, car: Node2D, handbrake: bool) -> Dictionary:
	var out := { "reached": await Probe.reach_speed(t, id, car, SPEED, 6.0), "out": -INF, "slip": 0.0 }
	t.puppet(id).drive(0.0, 1.0, handbrake)
	var deadline := t.time + 1.0
	while t.time < deadline:
		await t.frames(1)
		out["out"] = maxf(out["out"], Probe.outward_slip(car))
		out["slip"] = maxf(out["slip"], float(car.slip()))
	t.puppet(id).drive(0.0, 0.0, false)
	return out


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"slide", [&"a", &"b"]) or not Probe.ready(t, &"grip"):
		return
	var slide := t.vehicle(&"slide") as Node2D
	var grip := t.vehicle(&"grip") as Node2D
	if not t.require(await Probe.board_by(t, &"a", slide, &"front_left"), "a driver gets into the first car"):
		return
	if not t.require(await Probe.board_by(t, &"b", grip, &"front_left"), "a driver gets into the second car"):
		return

	var hand: Dictionary = await _turn(t, &"a", slide, true)
	if not t.require(hand["reached"], "the first car reaches %.0f px/s" % SPEED):
		return
	t.check(hand["out"] > 0.2, "with the handbrake the tail slides out: the body moves outside its heading (%.2f rad)" % hand["out"])
	t.check(hand["slip"] > 0.05, "slip() rises with the slide (%.3f)" % hand["slip"])

	var plain: Dictionary = await _turn(t, &"b", grip, false)
	if not t.require(plain["reached"], "the second car reaches %.0f px/s" % SPEED):
		return
	t.check(plain["out"] < hand["out"], "without the handbrake the same turn slides less (%.2f against %.2f rad)" % [plain["out"], hand["out"]])
