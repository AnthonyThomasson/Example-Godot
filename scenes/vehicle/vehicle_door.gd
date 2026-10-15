extends RefCounted

## Vehicles domain: one door of a vehicle, in the vehicle's own frame (x forward, y toward its right side). It keeps the
## door's eased open amount, says where the door is as it opens (a `swing` door turns out about its front hinge, a
## `rear` door out behind about its back corner, a `slide` door rolls back along the body), where a character stands to
## use it and where the gap behind it is, and whether it is free to open: a shape query along its swing arc or slide
## track, and at the stand point. The vehicle steps it (`update`) and reads it out (`info`).

var id: StringName  ## Its id in the kind's `doors` row (`front_left`, `side` ...).
var kind: StringName  ## `swing`, `slide` or `rear`.
var seat: StringName  ## The seat behind it.
var hinge: Vector2    ## Where it turns (a sliding door: its front edge), on the body's edge.
var handle: Vector2   ## Where it is pulled, on the body's edge, the door shut.
var length: float     ## Hinge to handle (a sliding door: its length along the body).
var open_angle: float  ## How far (rad) a swing or rear door turns when fully open.
var outward: Vector2  ## Out of the body through this door (unit).

var _turn := 1.0  ## Which way the door turns as it opens (the sign of the angle), so its free edge goes outward.
var _progress := 0.0  ## Closed 0 .. open 1, linear in time; `amount()` eases it.
var _target := 0.0  ## Where the progress is heading: 0 closing (or shut), 1 opening (or open).


func _init(def: Dictionary) -> void:
	id = def["id"]
	kind = def["kind"]
	seat = def["seat"]
	hinge = def["hinge"]
	handle = def["handle"]
	open_angle = def.get("open_angle", 0.0)
	length = def.get("length", hinge.distance_to(handle))
	outward = Vector2.LEFT if kind == &"rear" else Vector2(0.0, signf(handle.y))
	_turn = signf((handle - hinge).cross(outward))


## Move the door toward its target by `delta` s. Returns true on the frame a closing door shuts (the slam).
func update(delta: float) -> bool:
	if _progress == _target:
		return false
	var time := VehicleConfig.slide_time if kind == &"slide" else (VehicleConfig.door_open_time if _target > _progress
			else VehicleConfig.door_close_time)
	_progress = move_toward(_progress, _target, delta / maxf(time, 0.01))
	return _progress == 0.0 and _target == 0.0


## Start opening; true when the door was shut (so it is the handle's click, not a door already on its way).
func open() -> bool:
	var was_shut := _progress == 0.0 and _target == 0.0
	_target = 1.0
	return was_shut


## Start closing.
func close() -> void:
	_target = 0.0


## How far open, 0 (shut) .. 1 (open): eased out of the progress, so it opens fast and settles, and gathers speed as it
## shuts.
func amount() -> float:
	return 1.0 - (1.0 - _progress) * (1.0 - _progress)


## True once fully open.
func is_open() -> bool:
	return _progress >= 1.0


## How far a swing or rear door is turned (rad, signed); 0 for a sliding door.
func angle() -> float:
	return 0.0 if kind == &"slide" else _turn * open_angle * amount()


## How far a sliding door has rolled (local px): back along the body, standing a little out from it; zero for the others.
func offset() -> Vector2:
	if kind != &"slide":
		return Vector2.ZERO
	var a := amount()
	return Vector2(-length * a, 0.0) + outward * VehicleConfig.slide_pop * clampf(a * 4.0, 0.0, 1.0)


## The handle where the door is now (local).
func handle_now() -> Vector2:
	if kind == &"slide":
		return handle + offset()
	return hinge + (handle - hinge).rotated(angle())


## Where a character of `radius` stands to use the door (local): out from the body beyond its radius, and on past the
## handle (away from the hinge) until it is clear of the door's swing, so the door opens and shuts beside it. A sliding
## door's stand point is out from the front of its opening, clear of the track it rolls back along.
func stand_point(radius: float) -> Vector2:
	var out := radius + VehicleConfig.stand_out
	if kind == &"slide":
		return handle + Vector2(-8.0, 0.0) + outward * out
	var along := (handle - hinge).normalized()
	var reach := length + radius + VehicleConfig.door_clearance
	var past := maxf(4.0, sqrt(maxf(reach * reach - out * out, 0.0)) - length)
	return handle + along * past + outward * out


## The gap a character of `radius` steps into on its way to the seat (local): the middle of the door's opening, just
## outside the body.
func entry_point(radius: float) -> Vector2:
	var middle := (hinge + handle) * 0.5
	if kind == &"slide":
		middle = hinge + Vector2(-length * 0.5, 0.0)
	return middle + outward * radius * 0.4


## Whether the door can open for a character of `radius` (the bodies in `exclude`, its own and the vehicle's, ignored): nothing
## solid (a wall, furniture, a character, another vehicle) is in its swing arc or slide track, nor at its stand point.
func is_clear(vehicle: Node2D, exclude: Array[RID], radius: float) -> bool:
	var space := vehicle.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.collision_mask = PhysicsLayers.SOLID
	params.exclude = exclude
	params.shape = _sweep_shape()
	params.transform = vehicle.global_transform
	if not space.intersect_shape(params, 1).is_empty():
		return false
	var body := CircleShape2D.new()
	body.radius = radius
	params.shape = body
	params.transform = Transform2D(0.0, vehicle.to_global(stand_point(radius)))
	return space.intersect_shape(params, 1).is_empty()


## The door as `doors()` reports it (world space): `{ id, kind, seat, handle, open, hinge, angle, offset }`.
func info(vehicle: Node2D) -> Dictionary:
	return {
		"id": id, "kind": kind, "seat": seat, "handle": vehicle.to_global(handle_now()), "open": amount(),
		"hinge": vehicle.to_global(hinge), "angle": angle(), "offset": vehicle.global_transform.basis_xform(offset()),
	}


## The ground the door sweeps (local): the sector its free edge turns through, a little longer than the door, or the
## strip beside the body that a sliding door rolls along.
func _sweep_shape() -> ConvexPolygonShape2D:
	var points := PackedVector2Array()
	var clearance := VehicleConfig.door_clearance
	if kind == &"slide":
		var depth := outward * (VehicleConfig.slide_pop + 2.0 + clearance)
		var back := hinge + Vector2(-2.0 * length - clearance, 0.0)
		points = PackedVector2Array([hinge, back, back + depth, hinge + depth])
	else:
		var arm := (handle - hinge) * (1.0 + clearance / maxf(length, 1.0))
		points.append(hinge)
		var steps := 6
		for i in steps + 1:
			points.append(hinge + arm.rotated(_turn * open_angle * float(i) / steps))
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(points)
	return shape
