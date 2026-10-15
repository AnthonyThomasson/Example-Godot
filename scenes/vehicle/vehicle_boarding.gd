extends RefCounted

## Vehicles domain: one character's ride in a vehicle, from E beside it to its last step back out (V3, V4), as a timed
## phase machine. The character's CharacterVehicleUse steps it every physics frame, after the controller has written its
## intent, so the machine is the character's controller for the ride:
##  - WALK: the character walks with its own walk cycle (`move_input`) round the body to the stand point beside the door,
##    turning smoothly (`aim_point`) to face the door as it arrives;
##  - OPEN: the door eases open while it stands;
##  - STEP_IN, FOLD: it steps into the gap, turns to face forward and folds down into the seat, every frame a pose the
##    vehicle carries (`set_ride_pose(position, facing, fold)`, positions kept in the vehicle's frame);
##  - SEATED: the door shuts behind it; from the driver's seat its `move_input` / `run_input` drive the vehicle. A
##    passenger first slides across to an empty driver's seat (SHIFT_SEAT);
##  - BRAKE, SHIFT_OUT, OPEN_OUT, UNFOLD, STEP_OUT: getting out is the reverse, after braking to a stop (a driver above
##    `exit_max_speed`) or waiting for one (a passenger), by its own door if clear, else the nearest clear one; it ends
##    standing beside the door (`end_ride()`), which then shuts behind it.
## Nothing interrupts it but death (`abandon`), which leaves the door as it is.

const VehicleDoor = preload("res://scenes/vehicle/vehicle_door.gd")

enum Phase { WALK, OPEN, STEP_IN, FOLD, SEATED, SHIFT_SEAT, BRAKE, SHIFT_OUT, OPEN_OUT, UNFOLD, STEP_OUT, DONE }

var vehicle: Node2D  ## The vehicle ridden.
var character: Node2D  ## Who rides.
## The door it got in by (its own door, the first choice out) and the seat it holds.
var door: VehicleDoor
var seat: StringName
var phase := Phase.WALK  ## Where the ride is, from the walk to the door to the last step out.

var _exit_door: VehicleDoor  ## The door it is getting out by.
var _braking := false  ## A driver braking to a stop before it gets out.
var _clock := 0.0  ## Seconds into the walk, or into the current pose phase.
var _duration := 0.0  ## The pose phase's length.
var _from := Vector2.ZERO  ## The pose phase's path and fold (vehicle frame).
var _to := Vector2.ZERO
var _fold_from := 0.0
var _fold_to := 0.0
var _turn_to := 0.0  ## The heading (vehicle frame, rad) the facing turns toward in a pose phase.
var _heading := 0.0  ## The facing in a pose phase (vehicle frame, rad).
var _posed := Vector2.ZERO  ## Last frame's posed point (vehicle frame), for the step the legs take.
var _facing := Vector2.RIGHT  ## The facing during the walk (world).
var _route: Array[Vector2] = []  ## The walk's waypoints (vehicle frame).


func _init(on: Node2D, who: Node2D, by: VehicleDoor) -> void:
	vehicle = on
	character = who
	door = by
	seat = by.seat
	_facing = who.facing
	_route = _path(vehicle.to_local(who.global_position), by.stand_point(who.radius))


## Step the ride one physics frame.
func step(delta: float) -> void:
	match phase:
		Phase.WALK:
			_walk(delta)
		Phase.OPEN:
			_wait_for_door(delta)
		Phase.STEP_IN:
			if _pose(delta):
				_begin_pose(Phase.FOLD, vehicle.seat_point(seat), VehicleConfig.fold_time, 0.0, 1.0, 0.0)
		Phase.FOLD:
			if _pose(delta):
				_sit()
		Phase.SHIFT_SEAT:
			if _pose(delta):
				vehicle.change_seat(character, &"driver")
				seat = &"driver"
				phase = Phase.SEATED
				_start_if_driving()
		Phase.SEATED:
			_ride(delta)
		Phase.BRAKE:
			_brake(delta)
		Phase.SHIFT_OUT:
			if _pose(delta):
				_open_out()
		Phase.OPEN_OUT:
			_pose(delta)
			if _exit_door.is_open():
				_begin_pose(Phase.UNFOLD, _exit_door.entry_point(character.radius), VehicleConfig.fold_time, 1.0, 0.0,
						_exit_door.outward.angle())
		Phase.UNFOLD:
			if _pose(delta):
				var stand: Vector2 = _exit_door.stand_point(character.radius)
				_begin_pose(Phase.STEP_OUT, stand, _step_time(_posed, stand), 0.0, 0.0, (stand - _posed).angle())
		Phase.STEP_OUT:
			if _pose(delta):
				_step_off()


## Seated in its seat (the door shut or not), not on its way in or out.
func is_seated() -> bool:
	return phase == Phase.SEATED or phase == Phase.SHIFT_SEAT or phase == Phase.BRAKE


## The ride is over: the character is out (or never got in).
func is_done() -> bool:
	return phase == Phase.DONE


## E while seated: get out (braking first at speed). Ignored on the way in or out.
func request_exit() -> void:
	if phase != Phase.SEATED:
		return
	_braking = seat == &"driver" and vehicle.speed() > VehicleConfig.exit_max_speed
	phase = Phase.BRAKE


## The character died: its seat is given up where it is, and the door is left as it is.
func abandon() -> void:
	if phase != Phase.DONE:
		vehicle.release(character)
	phase = Phase.DONE


# --- On the way in ---------------------------------------------------------------------

## Walk round the body to the stand point, then face the door and open it. Given up if the vehicle starts moving or the
## walk does not arrive in time (something stands in the way).
func _walk(delta: float) -> void:
	_clock += delta
	if vehicle.speed() >= VehicleConfig.board_max_speed or _clock > VehicleConfig.walk_timeout:
		_give_up()
		return
	var pos: Vector2 = character.global_position
	while not _route.is_empty() and vehicle.to_global(_route[0]).distance_to(pos) < 1.0:
		_route.pop_front()
	character.run_input = false
	if _route.is_empty():
		character.move_input = Vector2.ZERO
		phase = Phase.OPEN
		vehicle.open_door(door)
		_turn(_to_handle(), delta)
		return
	var to: Vector2 = vehicle.to_global(_route[0]) - pos
	var reach: float = float(character.speed) * delta
	character.move_input = to.normalized() * minf(1.0, to.length() / maxf(reach, 0.001))
	# Looking where it walks, and at the door over the last stretch.
	_turn(to.normalized() if _left_to_walk(pos) > 18.0 else _to_handle(), delta)


## Stand facing the door while it opens; step in once it is open and the character faces it.
func _wait_for_door(delta: float) -> void:
	character.move_input = Vector2.ZERO
	character.run_input = false
	if vehicle.speed() >= VehicleConfig.board_max_speed:
		_give_up()
		return
	var want := _to_handle()
	_turn(want, delta)
	if door.is_open() and absf(_facing.angle_to(want)) <= VehicleConfig.face_tolerance:
		_heading = _facing.rotated(-vehicle.global_rotation).angle()
		_posed = vehicle.to_local(character.global_position)
		var entry := door.entry_point(character.radius)
		_begin_pose(Phase.STEP_IN, entry, _step_time(_posed, entry), 0.0, 0.0, 0.0)


## Folded into the seat: the door shuts behind it, and the engine starts for a driver. A passenger with nobody at the
## wheel slides across to it first.
func _sit() -> void:
	phase = Phase.SEATED
	vehicle.close_door(door)
	if seat == &"passenger" and vehicle.is_free(&"driver"):
		vehicle.reserve(character, &"driver")
		_begin_pose(Phase.SHIFT_SEAT, vehicle.seat_point(&"driver"), VehicleConfig.shift_time, 1.0, 1.0, 0.0)
		return
	_start_if_driving()


## In the driver's seat: start the engine.
func _start_if_driving() -> void:
	if seat == &"driver":
		vehicle.start_engine()


## Give up boarding before the step in: the seat is free again and the door (if it began to open) shuts.
func _give_up() -> void:
	character.move_input = Vector2.ZERO
	vehicle.release(character)
	vehicle.close_door(door)
	phase = Phase.DONE


# --- Seated ----------------------------------------------------------------------------

## Ride in the seat; from the driver's seat the character's movement keys are the drive intent.
func _ride(_delta: float) -> void:
	_hold_seat()
	if seat == &"driver":
		var keys: Vector2 = character.move_input
		vehicle.drive_input(character, -keys.y, keys.x, character.run_input)
	character.move_input = Vector2.ZERO
	character.run_input = false


## Sit still in the seat, facing forward.
func _hold_seat() -> void:
	_posed = vehicle.seat_point(seat)
	_heading = 0.0
	character.set_ride_pose(vehicle.to_global(_posed), _world_facing(0.0), 1.0)


# --- On the way out --------------------------------------------------------------------

## Brake to a stop first (a driver above `exit_max_speed`), or wait for the vehicle to slow (a passenger); then pick the
## door. With none clear the character stays in.
func _brake(_delta: float) -> void:
	_hold_seat()
	character.move_input = Vector2.ZERO
	character.run_input = false
	if _braking and vehicle.speed() >= VehicleConfig.stop_speed:
		vehicle.brake_input(character)
		return
	if not _braking and vehicle.speed() > VehicleConfig.exit_max_speed:
		return
	_braking = false
	_exit_door = vehicle.exit_door(character, seat, door)
	if _exit_door == null:
		phase = Phase.SEATED
		return
	if seat == &"driver":
		vehicle.stop_engine()
	if _exit_door.seat != seat:
		_begin_pose(Phase.SHIFT_OUT, vehicle.seat_point(_exit_door.seat), VehicleConfig.shift_time, 1.0, 1.0, 0.0)
	else:
		_open_out()


## Open the way out and wait in the seat beside it.
func _open_out() -> void:
	vehicle.open_door(_exit_door)
	_begin_pose(Phase.OPEN_OUT, _posed, 0.0, 1.0, 1.0, _heading)


## Out and standing beside the door: the seat is free, the door shuts behind it and the character is its own again.
func _step_off() -> void:
	phase = Phase.DONE
	vehicle.release(character)
	vehicle.close_door(_exit_door)
	character.end_ride()


# --- Poses -----------------------------------------------------------------------------

## Begin pose phase `next`: from where the character is posed to `to` (vehicle frame) in `duration` s, the fold easing
## from `fold_from` to `fold_to` and the facing turning toward `turn_to`.
func _begin_pose(next: Phase, to: Vector2, duration: float, fold_from: float, fold_to: float, turn_to: float) -> void:
	phase = next
	_clock = 0.0
	_duration = duration
	_from = _posed
	_to = to
	_fold_from = fold_from
	_fold_to = fold_to
	_turn_to = turn_to


## Pose the character for this frame of the pose phase (eased in and out); true once the phase is over.
func _pose(delta: float) -> bool:
	_clock += delta
	var k := smoothstep(0.0, 1.0, clampf(_clock / maxf(_duration, 0.001), 0.0, 1.0))
	var at := _from.lerp(_to, k)
	var fold := lerpf(_fold_from, _fold_to, k)
	_heading = rotate_toward(_heading, _turn_to, VehicleConfig.turn_rate * delta)
	# The legs step with the motion through the vehicle's frame, less the further they are folded.
	var stepped := (at - _posed).rotated(vehicle.global_rotation) / maxf(delta, 0.001) * (1.0 - fold)
	_posed = at
	character.set_ride_pose(vehicle.to_global(at), _world_facing(_heading), fold, stepped)
	return _clock >= _duration and absf(angle_difference(_heading, _turn_to)) < 0.01


## How long a step from `a` to `b` (vehicle frame) takes at the stepping pace: its eased peak stays under the walk.
func _step_time(a: Vector2, b: Vector2) -> float:
	var pace := maxf(float(character.speed) * VehicleConfig.step_pace, 1.0)
	return maxf(VehicleConfig.step_min_time, 1.5 * a.distance_to(b) / pace)


## The world facing of heading `angle` in the vehicle's frame.
func _world_facing(angle: float) -> Vector2:
	return Vector2.from_angle(angle + vehicle.global_rotation)


## Turn the walking character's facing toward `want` (world, unit) no faster than the boarding turn rate, through its
## aim (a standing character faces its aim at once).
func _turn(want: Vector2, delta: float) -> void:
	if want.length_squared() > 0.0001:
		var most := VehicleConfig.turn_rate * delta
		_facing = _facing.rotated(clampf(_facing.angle_to(want), -most, most)).normalized()
	character.aim_point = character.global_position + _facing * 64.0


## The way from the character to the door's handle (world, unit).
func _to_handle() -> Vector2:
	return (vehicle.to_global(door.handle) - character.global_position).normalized()


## How far is left to walk from `pos` (world) along the route.
func _left_to_walk(pos: Vector2) -> float:
	var total := 0.0
	var at := pos
	for p in _route:
		var w := vehicle.to_global(p)
		total += at.distance_to(w)
		at = w
	return total


# --- The walk round the body -----------------------------------------------------------

## Waypoints (vehicle frame) from `from` to `to` that keep a walker of the character's radius off the body: straight when
## the line misses it, else round one corner of the body or two, whichever is shorter.
func _path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var half: Vector2 = vehicle.half_size() + Vector2.ONE * (float(character.radius) + VehicleConfig.walk_margin)
	var straight: Array[Vector2] = [to]
	if not _crosses(from, to, half):
		return straight
	var corners: Array[Vector2] = []
	for c in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
		corners.append((half + Vector2.ONE) * c)
	var best: Array[Vector2] = straight
	var best_length := INF
	for i in corners.size():
		var c: Vector2 = corners[i]
		if not _crosses(from, c, half) and not _crosses(c, to, half):
			var length := from.distance_to(c) + c.distance_to(to)
			if length < best_length:
				best_length = length
				best = [c, to]
		for j in [(i + 1) % 4, (i + 3) % 4]:
			var d: Vector2 = corners[j]
			if not _crosses(from, c, half) and not _crosses(d, to, half):
				var length := from.distance_to(c) + c.distance_to(d) + d.distance_to(to)
				if length < best_length:
					best_length = length
					best = [c, d, to]
	return best


## Whether the segment `a`-`b` passes through the inside of the box of half extents `half` about the origin.
static func _crosses(a: Vector2, b: Vector2, half: Vector2) -> bool:
	var inner := half - Vector2.ONE * 0.5
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		if absf(d[axis]) < 0.000001:
			if a[axis] <= -inner[axis] or a[axis] >= inner[axis]:
				return false
			continue
		var ta := (-inner[axis] - a[axis]) / d[axis]
		var tb := (inner[axis] - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 >= t1:
			return false
	return true
