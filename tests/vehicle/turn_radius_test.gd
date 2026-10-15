extends GameTest

## V5 / F5 (ticket #54, feedback round 2): arcade-tight turning. At low speed (about 100 px/s) full lock turns the body's
## centre on a radius of about one car length: the car's at most 220 px, the van's at most 260 px. Steering is kept at
## speed: at car 800 px/s / van 550 px/s (above half of their tops of 1280 / 880), full lock without the handbrake
## still turns on a radius of at most four car lengths (car 4 x 220 = 880 px, van 4 x 260 = 1040 px) and does not spin
## out: the body's slip angle (heading against the direction it moves) stays under 0.5 rad. The plan's numbers, not
## VehicleConfig's.
##
## The radius is measured, not read from the tuning: the centre's positions over a steady stretch of the turn (after the
## steering and the yaw have settled) are fitted with a circle (least squares). The fast turns start from the speed set
## straight ahead through `linear_velocity` (as `vehicle/launch_and_brake` sets its brake runs going), so this test
## measures the steering alone, not the launch (`vehicle/top_speed`); the driver then holds the speed with the throttle.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## Lanes: id -> [driver, kind, speed held (px/s), largest radius allowed (px), start (px), set the speed at once].
const LANES := {
	&"car_slow": [&"cs", &"car", 100.0, 220.0, Vector2(900, 700), false],
	&"van_slow": [&"vs", &"van", 100.0, 260.0, Vector2(900, 2200), false],
	&"car_fast": [&"cf", &"car", 800.0, 880.0, Vector2(2400, 600), true],
	&"van_fast": [&"vf", &"van", 550.0, 1040.0, Vector2(2400, 2400), true],
}
## Slow lanes: straight up to the speed for this long (s), then full lock to settle, then the stretch the circle is fitted to.
const SLOW_RUN_UP := 1.5
const SLOW_SETTLE := 1.5
const SLOW_FIT := 2.5
## Fast lanes: full lock from the set speed, settle, then the fitted stretch (shorter: the path is long at these speeds).
const FAST_SETTLE := 0.6
const FAST_FIT := 1.2
## The most the body may slip (rad): beyond it the car is spinning out, not turning.
const MAX_SLIP_ANGLE := 0.5
## Over the fitted stretch the speed must average at least this share of the speed held, or a slower car would turn
## tighter for that reason alone.
const MIN_SPEED_SHARE := 0.85
## Big enough for a fast car that barely turns (a radius near 2000 px) to cover its 1.8 s of path inside the walls.
const ARENA := Rect2(0, 0, 5600, 4000)


func describe() -> Dictionary:
	return {
		"name": "Car and van turn tight",
		"description": "Full lock: at about 100 px/s the centre's path has a radius of at most 220 px (car) / 260 px (van); at 800 / 550 px/s (above half the top speed, no handbrake) at most 880 / 1040 px, with the body slip angle under 0.5 rad.",
		"tags": ["vehicle", "car", "van", "drive", "steer", "turn"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA, { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	for id in LANES:
		s.vehicle(id, LANES[id][1], LANES[id][4])
		s.actor(LANES[id][0], &"puppet", LANES[id][4] + Vector2(-200, -150))


## The least-squares circle through `points` (Kasa: x² + y² + D x + E y + F = 0 solved for D, E, F):
## `{ centre, radius, rms }` (`rms` the points' root-mean-square distance off it), or {} for too few or collinear points.
static func fit_circle(points: Array) -> Dictionary:
	if points.size() < 3:
		return {}
	# Centre the points on their mean so the normal equations stay well conditioned.
	var mean := Vector2.ZERO
	for p: Vector2 in points:
		mean += p
	mean /= points.size()
	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0
	var sxz := 0.0
	var syz := 0.0
	for p: Vector2 in points:
		var q := p - mean
		var z := q.length_squared()
		sxx += q.x * q.x
		sxy += q.x * q.y
		syy += q.y * q.y
		sxz += q.x * z
		syz += q.y * z
	# With centred points the sums of x and y are 0, so D and E come from a 2x2 system: [sxx sxy; sxy syy] [D E] = -[sxz syz].
	var det := sxx * syy - sxy * sxy
	if absf(det) < 1e-6:
		return {}
	var d := (-sxz * syy + syz * sxy) / det
	var e := (-syz * sxx + sxz * sxy) / det
	var centre := Vector2(-d / 2.0, -e / 2.0)
	var r2 := 0.0
	for p: Vector2 in points:
		r2 += (p - mean - centre).length_squared()
	var radius := sqrt(r2 / points.size())
	var err := 0.0
	for p: Vector2 in points:
		err += pow((p - mean - centre).length() - radius, 2.0)
	return { "centre": centre + mean, "radius": radius, "rms": sqrt(err / points.size()) }


## The body slip angle (rad, unsigned): between where the vehicle heads and where it moves. 0 below 5 px/s.
static func slip_angle(v: Node2D) -> float:
	var lv := Probe.local_velocity(v)
	if lv.length() < 5.0:
		return 0.0
	return absf(atan2(lv.y, lv.x))


## Full lock to the right in lane `id` for `settle` then `fit` s, holding its speed. Returns `{ fit, slip, speed }`: the
## circle fitted to the centre's path over the `fit` stretch, the largest body slip angle over the whole turn, and the
## mean speed over the stretch.
func _turn(t: TestContext, id: StringName, settle: float, fit: float) -> Dictionary:
	var v := t.vehicle(id) as Node2D
	var driver: StringName = LANES[id][0]
	var target: float = LANES[id][2]
	var points: Array = []
	# [the largest slip angle, the speed summed over the stretch] (an Array: a lambda captures plain locals by value).
	var seen := [0.0, 0.0]
	await Probe.hold_speed(t, driver, v, target, 1.0, false, settle, func():
		seen[0] = maxf(seen[0], slip_angle(v))
		t.trace("%s slip angle" % id, slip_angle(v)))
	await Probe.hold_speed(t, driver, v, target, 1.0, false, fit, func():
		points.append(v.global_position)
		seen[0] = maxf(seen[0], slip_angle(v))
		seen[1] += v.speed()
		t.trace("%s slip angle" % id, slip_angle(v))
		t.trace("%s speed" % id, v.speed()))
	t.puppet(driver).drive(-1.0, 0.0, false)
	return { "fit": fit_circle(points), "slip": seen[0], "speed": seen[1] / maxf(points.size(), 1.0) }


## Check one lane's turn `turned`: it held about its speed, turned within its radius and did not spin out.
func _judge(t: TestContext, id: StringName, turned: Dictionary) -> void:
	var kind: StringName = LANES[id][1]
	var target: float = LANES[id][2]
	var most: float = LANES[id][3]
	t.check(turned["speed"] >= MIN_SPEED_SHARE * target, "the %s holds about %.0f px/s through the turn (averaged %.0f)" % [kind, target, turned["speed"]])
	var fit: Dictionary = turned["fit"]
	if not t.check(not fit.is_empty(), "the %s's path at %.0f px/s can be fitted with a circle" % [kind, target]):
		return
	t.check(fit["radius"] <= most, "at %.0f px/s full lock turns the %s on a radius of at most %.0f px (measured %.0f px, fit off by %.1f px rms)" % [target, kind, most, fit["radius"], fit["rms"]])
	t.check(turned["slip"] < MAX_SLIP_ANGLE, "without spinning out (largest body slip angle %.2f rad, under %.1f)" % [turned["slip"], MAX_SLIP_ANGLE])


func run(t: TestContext) -> void:
	for id in LANES:
		if not Probe.ready(t, id, [LANES[id][0]]):
			return
	for id in LANES:
		if not t.require(await Probe.board_by(t, LANES[id][0], t.vehicle(id) as Node2D, &"front_left"), "a driver gets into %s" % id):
			return
	await t.seconds(0.5)

	for id in LANES:
		var v := t.vehicle(id) as Node2D
		var fast: bool = LANES[id][5]
		if fast:
			v.set("linear_velocity", Probe.forward(v) * float(LANES[id][2]))
		else:
			await Probe.hold_speed(t, LANES[id][0], v, float(LANES[id][2]), 0.0, false, SLOW_RUN_UP)
		var turned: Dictionary = await _turn(t, id, FAST_SETTLE if fast else SLOW_SETTLE, FAST_FIT if fast else SLOW_FIT)
		_judge(t, id, turned)
