extends RefCounted

## Vehicles domain: the driving model, a bicycle. Stepped by the vehicle inside `_integrate_forces`, it turns the drive
## intent into the rigid body's velocities for the next physics step (the engine then moves the body and resolves its
## collisions):
##  - the steering eases toward the input; full lock is the kind's `steer_angle` while slow, and at speed the angle whose
##    turn asks the front tyres for `steer_demand` of the sideways grip they hold, so full lock at any speed turns as hard
##    as the tyres allow and no harder;
##  - the engine pushes along the front, tapering to just what holds the top speed against rolling resistance and air
##    drag, so full throttle settles at the top speed (S brakes, then reverses once nearly stopped); rolling resistance
##    and drag slow it, the brakes and handbrake harder, and none of them ever turns it round;
##  - each axle cancels its sideways slip with an impulse up to its grip limit (the handbrake drops the rear's), solved
##    for both axles together, so a turn within the grip goes where the wheels point and pivots about the rear axle, and
##    past it the axle slides. The rear holds more than the front (`grip_rear` over `grip_front`, weighed by where the
##    axles sit), so at the limit the front lets go first and the vehicle runs wide instead of spinning; the handbrake
##    drops the rear's grip and swings the tail out. What is left sliding is `slip`.
## All tuning is the kind's `VehicleConfig.kinds` row.

## The front wheels' steering angle (rad, + = to the right).
var wheel_angle := 0.0
## How far the steering is turned, as a share of full lock (-1..1): it eases toward the input, and the wheels turn by it
## times the lock at the speed (`lock`), so a full turn takes as long at any speed.
var steer_share := 0.0
## True while the brakes slow the vehicle (the brake lights).
var braking := false
## The slide amount: what the tyres could not cancel sideways, over the speed (0 while gripping .. 1).
var slip := 0.0
## The engine's revs (0..1 of the redline) and load (0..1), for its sound.
var rpm := 0.0
var engine_load := 0.0


## Step the model one physics step on `state`, for a vehicle of `row` driven by `intent` (`{ throttle, steer,
## handbrake, brake }`: `brake` holds the brakes to a stop and never reverses). `running` is whether the engine runs.
func step(state: PhysicsDirectBodyState2D, row: Dictionary, intent: Dictionary, running: bool) -> void:
	var dt := state.step
	var fwd := state.transform.x.normalized()
	var right := state.transform.y.normalized()
	var v := state.linear_velocity
	var w := state.angular_velocity
	var vx := v.dot(fwd)
	var vy := v.dot(right)
	var speed := v.length()
	var mass := 1.0 / maxf(state.inverse_mass, 0.0001)
	var inertia := 1.0 / maxf(state.inverse_inertia, 0.000001)
	var throttle: float = clampf(intent["throttle"], -1.0, 1.0) if running else 0.0
	var hold: bool = intent["brake"]
	var handbrake: bool = intent["handbrake"]

	# Steering: the share eased toward the input (full lock in steer_angle / steer_rate s), times the lock at this speed.
	var rate: float = float(row["steer_rate"]) / float(row["steer_angle"])
	steer_share = move_toward(steer_share, clampf(intent["steer"], -1.0, 1.0), rate * dt)
	wheel_angle = steer_share * lock(row, speed)

	# Along the front: the engine (or reverse) pushes, the brakes, rolling resistance and drag hold back toward a stop.
	var engage := VehicleConfig.reverse_engage_speed
	var push := 0.0
	var resist: float = float(row["rolling"]) + float(row["drag"]) * vx * vx
	braking = false
	if hold:
		braking = absf(vx) > VehicleConfig.stop_speed
		resist += float(row["brake"])
	elif throttle > 0.0:
		if vx < -engage:
			braking = true
			resist += float(row["brake"]) * throttle
		else:
			push = throttle * _engine(row, mass, vx)
	elif throttle < 0.0:
		if vx > engage:
			braking = true
			resist += float(row["brake"]) * -throttle
		else:
			push = throttle * float(row["reverse_force"]) / mass * maxf(0.0, 1.0 - pow(maxf(-vx, 0.0) / float(row["reverse_speed"]), 3.0))
	if handbrake:
		resist += float(row["handbrake_brake"])
	vx = move_toward(vx + push * dt, 0.0, resist * dt)

	# Sideways: each axle's impulse cancels its slip up to its grip, both solved together.
	var front: float = row["axle_front"]
	var back: float = -float(row["axle_rear"])
	var c := cos(wheel_angle)
	var s := sin(wheel_angle)
	var k_front := 1.0 / mass + (front * c) * (front * c) / inertia
	var k_rear := 1.0 / mass + back * back / inertia
	var grip_front: float = float(row["grip_front"]) * mass * 0.5 * dt
	var grip_rear: float = float(row["grip_rear"]) * (float(row["handbrake_grip"]) if handbrake else 1.0) * mass * 0.5 * dt
	var j_front := 0.0
	var j_rear := 0.0
	for i in VehicleConfig.tyre_iterations:
		var slide_front := -vx * s + (vy + w * front) * c
		var next := clampf(j_front - slide_front / k_front, -grip_front, grip_front)
		var d := next - j_front
		j_front = next
		vx += -s * d / mass
		vy += c * d / mass
		w += front * c * d / inertia
		var slide_rear := vy - w * back
		next = clampf(j_rear - slide_rear / k_rear, -grip_rear, grip_rear)
		d = next - j_rear
		j_rear = next
		vy += d / mass
		w -= back * d / inertia
	var left_front := absf(-vx * s + (vy + w * front) * c)
	var left_rear := absf(vy - w * back)
	slip = clampf(maxf(left_front, left_rear) / maxf(speed, VehicleConfig.slip_reference_speed), 0.0, 1.0)

	# At rest with nothing pushing, the tyres hold it still.
	if push == 0.0 and Vector2(vx, vy).length() < VehicleConfig.stop_speed and absf(w) < 0.05:
		vx = 0.0
		vy = 0.0
		w = 0.0
	state.linear_velocity = fwd * vx + right * vy
	state.angular_velocity = w
	_update_engine(row, vx, throttle if not braking else 0.0, running, dt)


## Full lock (rad) at `speed`: `steer_angle`, or at speed the angle whose turn (pivoting about the rear axle, sideways
## acceleration speed² x tan(angle) / wheelbase) asks `steer_demand` of the most the front axle holds. Turning in
## steady, the front carries rear-lever / wheelbase of the sideways force, so it holds `grip_front` x wheelbase / (2 x
## rear lever) of acceleration (each axle's limit is `grip` x mass / 2).
static func lock(row: Dictionary, speed: float) -> float:
	var full: float = row["steer_angle"]
	var front: float = row["axle_front"]
	var rear: float = -float(row["axle_rear"])
	var base := front + rear
	var holds: float = float(row["grip_front"]) * base / (2.0 * rear)
	var asked: float = float(row["steer_demand"]) * holds * base
	if speed * speed * tan(full) <= asked:
		return full
	return atan(asked / (speed * speed))


## The engine's forward push at `vx` (px/s², full throttle): `engine_force / mass` at rest, eased by the cube of the
## share of the top speed toward the rolling resistance and drag at the top speed, which it equals there, so the
## vehicle settles at `top_speed` whatever its drag; past it, less than that, so it slows back.
func _engine(row: Dictionary, mass: float, vx: float) -> float:
	var top: float = row["top_speed"]
	var held_at_top: float = float(row["rolling"]) + float(row["drag"]) * top * top
	var share := pow(maxf(vx, 0.0) / top, 3.0)
	return maxf(0.0, lerpf(float(row["engine_force"]) / mass, held_at_top, share))


## The engine's revs and load: idle at rest, climbing through each gear's share of the top speed and dropping at the
## change; the load is the throttle held. Off: both 0.
func _update_engine(row: Dictionary, vx: float, throttle: float, running: bool, dt: float) -> void:
	if not running:
		rpm = 0.0
		engine_load = 0.0
		return
	var gears := maxi(VehicleConfig.gears, 1)
	var share := clampf(absf(vx) / float(row["top_speed"]), 0.0, 0.999) * gears
	var gear := int(share)
	var low := VehicleConfig.idle_rpm if gear == 0 else 0.55
	var target := lerpf(low, 1.0, share - gear)
	target = maxf(target, VehicleConfig.idle_rpm + 0.25 * absf(throttle) * (1.0 - share / gears))
	rpm = move_toward(rpm, target, 3.0 * dt) if absf(rpm - target) < 0.3 else target
	engine_load = absf(throttle)
