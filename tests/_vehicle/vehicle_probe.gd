extends RefCounted

## Shared bits for the vehicle tests (ticket #54, rules V1 to V9; not a test).
## `const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")`.
##
## Everything is read through the drivable contract: the character's `try_use_vehicle()`, `vehicle()`,
## `is_in_vehicle()` (true only while seated) and `posture_folded()` (the ride fold while in a vehicle); the vehicle's
## `doors()` (`{ id, kind, seat, handle, open, hinge, angle, offset }` per door, world space), `seats()` (`{ id, occupant }`),
## `driver()`, `speed()` (unsigned px/s), `engine_state()` (`{ running, rpm, load }`), `slip()` (the slide amount, 0 while
## gripping), `wheel_angle()`, `brake_lights()`, its `Chassis` / `Roof` draw layers, and `VehicleConfig`'s tuning. Nothing
## here knows how a vehicle is built, and a read that does not exist yet fails a `require` instead of a script error.

## The plan's numbers: the spec, not the code.
const DOOR_REACH := 60.0       ## E picks a door whose handle is within this of the character.
const BOARD_MAX_SPEED := 20.0  ## Boarding only below this speed (px/s).
const EXIT_MAX_SPEED := 20.0   ## Above this, E brakes to a stop first.
const HARM_MIN_SPEED := 90.0   ## A character struck slower than this is shoved, not hurt.
const DOOR_OPEN_TIME := 0.35   ## A door eases open in about this long.
const FOLD_TIME := 0.5         ## The fold into the seat takes about this long.

## Each kind's doors: id -> [kind, the seat behind it].
const CAR_DOORS := {
	&"front_left": [&"swing", &"driver"],
	&"front_right": [&"swing", &"passenger"],
	&"rear_left": [&"swing", &"rear_left"],
	&"rear_right": [&"swing", &"rear_right"],
}
const VAN_DOORS := {
	&"front_left": [&"swing", &"driver"],
	&"front_right": [&"swing", &"passenger"],
	&"side": [&"slide", &"cargo_right"],
	&"rear_left": [&"rear", &"cargo_left"],
	&"rear_right": [&"rear", &"cargo_right"],
}
const CAR_SEATS := [&"driver", &"passenger", &"rear_left", &"rear_right"]
const VAN_SEATS := [&"driver", &"passenger", &"cargo_left", &"cargo_right"]

## What a character needs to use a vehicle, and what every vehicle reads out.
const CHARACTER_READS := [&"try_use_vehicle", &"vehicle", &"is_in_vehicle"]
const VEHICLE_READS := [&"doors", &"seats", &"driver", &"speed", &"engine_state", &"slip", &"get_surface"]

## The sound categories the vehicles add (V7).
const SOUND_CATEGORIES := [&"engine", &"vehicle", &"skid"]


# --- Premises -------------------------------------------------------------------------------

## Require that vehicle `id` was placed (its scene exists), that it has the contract's reads (plus `extra`), and that every
## actor in `characters` can use a vehicle. False (the test has ended) at the first that does not hold.
static func ready(t: TestContext, id: StringName, characters: Array = [], extra: Array = []) -> bool:
	var v := t.vehicle(id)
	if not t.require(v != null, "the vehicle %s exists (TestSetup.vehicle placed res://scenes/vehicle/<kind>.tscn)" % id):
		return false
	if not has_reads(t, v, VEHICLE_READS + extra, "the %s" % id):
		return false
	for c in characters:
		var who := t.actor(c)
		if not t.require(who != null, "actor %s exists" % c):
			return false
		if not has_reads(t, who, CHARACTER_READS, "character %s" % c):
			return false
	return true


## Require that `node` has every method in `methods`, naming the missing ones.
static func has_reads(t: TestContext, node: Object, methods: Array, what: String) -> bool:
	var missing: Array = methods.filter(func(m): return not node.has_method(m))
	return t.require(missing.is_empty(), "%s has %s (missing: %s)" % [what, ", ".join(methods.map(func(m): return String(m) + "()")), missing])


## The `VehicleConfig` static holder, looked up by class name (null before it exists, so a test referencing it still parses).
static func config() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == &"VehicleConfig":
			return load(c["path"])
	return null


## A shared `VehicleConfig` number (`harm_kill_speed`, `crash_min_speed`, `drive_zoom_out` ...), or `fallback` without one.
static func config_value(prop: StringName, fallback: Variant = null) -> Variant:
	var c := config()
	if c == null:
		return fallback
	var v: Variant = c.get(prop)
	return fallback if v == null else v


## A per-kind `VehicleConfig.kinds[kind][key]` (`top_speed` ...), or `fallback` without one.
static func kind_value(kind: StringName, key: StringName, fallback: Variant = null) -> Variant:
	var kinds: Variant = config_value(&"kinds")
	if not kinds is Dictionary:
		return fallback
	var row: Variant = kinds.get(kind, kinds.get(String(kind)))
	if not row is Dictionary:
		return fallback
	return row.get(key, row.get(String(key), fallback))


# --- Doors and seats ------------------------------------------------------------------------

## Door `id` of `v` as `doors()` reports it now, or {}.
static func door(v: Node, id: StringName) -> Dictionary:
	for d: Dictionary in v.doors():
		if d.get("id") == id:
			return d
	return {}


## The ids of `v`'s doors.
static func door_ids(v: Node) -> Array:
	return v.doors().map(func(d): return d.get("id"))


## How far door `id` is open (0..1), 0 for an unknown door.
static func open_of(v: Node, id: StringName) -> float:
	return float(door(v, id).get("open", 0.0))


## The seat `character` sits in (or is boarding into), &"" when none.
static func seat_of(v: Node, character: Node) -> StringName:
	for s: Dictionary in v.seats():
		if s.get("occupant") == character:
			return s.get("id", &"")
	return &""


## Who sits in seat `id` (null when empty or unknown).
static func occupant(v: Node, id: StringName) -> Node:
	for s: Dictionary in v.seats():
		if s.get("id") == id:
			var who: Variant = s.get("occupant")
			return who if is_instance_valid(who) else null
	return null


## `ids` as Strings, sorted (to compare sets of ids whatever order they are listed in).
static func sorted(ids: Array) -> Array:
	var out: Array = ids.map(func(x): return String(x))
	out.sort()
	return out


## Every door's largest open amount while `condition` stays false (sampled each frame, at most `timeout` s).
## Returns `{ done: bool (condition came true), max: { door id: open } }`.
static func watch_doors(t: TestContext, v: Node, condition: Callable, timeout: float) -> Dictionary:
	var most := {}
	for id in door_ids(v):
		most[id] = 0.0
	var deadline := t.time + timeout
	var done := false
	while t.time < deadline:
		for d: Dictionary in v.doors():
			most[d.get("id")] = maxf(most.get(d.get("id"), 0.0), float(d.get("open", 0.0)))
		if condition.call():
			done = true
			break
		await t.frames(1)
	return { "done": done, "max": most }


## The doors in a `watch_doors` result that opened past `threshold`.
static func opened(watched: Dictionary, threshold := 0.5) -> Array:
	var out: Array = []
	for id in watched["max"]:
		if watched["max"][id] > threshold:
			out.append(id)
	return out


# --- Geometry -------------------------------------------------------------------------------

## The vehicle's front (unit, world).
static func forward(v: Node2D) -> Vector2:
	return v.global_transform.x.normalized()


## Its right side (unit, world): +y at rotation 0, so its left side is toward -y.
static func right(v: Node2D) -> Vector2:
	return v.global_transform.y.normalized()


## Out of door `d` (a `doors()` entry): behind the vehicle for a rear door, else away from its side.
static func outward(v: Node2D, d: Dictionary) -> Vector2:
	if d.get("kind") == &"rear":
		return -forward(v)
	var side := signf((d["handle"] as Vector2 - v.global_position).dot(right(v)))
	return right(v) * (side if side != 0.0 else 1.0)


## Where a character stands to use door `id`: `out` px out from its handle.
static func stand_point(v: Node2D, id: StringName, out := 22.0) -> Vector2:
	var d := door(v, id)
	return (d["handle"] as Vector2) + outward(v, d) * out


## Where the vehicle's body meets the line from its centre toward `direction` (world), by a ray from far out along it that
## hits only the vehicle (whatever else is on the line is skipped). The centre when nothing is hit.
static func edge(v: Node2D, direction: Vector2) -> Vector2:
	var space := v.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(v.global_position + direction.normalized() * 800.0, v.global_position)
	var skipped: Array[RID] = []
	for i in 12:
		query.exclude = skipped
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		if hit["collider"] == v:
			return hit["position"]
		skipped.append(hit["rid"])
	return v.global_position


## How far (px) from the vehicle's body along `direction` the next solid thing is (another body or a wall), by a ray out
## from its edge; INF when nothing is within 2000 px.
static func gap_to_solid(v: Node2D, direction: Vector2) -> float:
	var space := v.get_world_2d().direct_space_state
	var from := edge(v, direction)
	var query := PhysicsRayQueryParameters2D.create(from, from + direction.normalized() * 2000.0)
	query.exclude = [v.get_rid()]
	var hit := space.intersect_ray(query)
	return INF if hit.is_empty() else from.distance_to(hit["position"])


## Its tail (the back of the body on its centre line) in its own frame, measured at rest.
static func tail_offset(v: Node2D) -> Vector2:
	return v.to_local(edge(v, -forward(v)))


## The body's velocity in its own frame: x along its front, y toward its right.
static func local_velocity(v: Node2D) -> Vector2:
	var lv: Vector2 = v.get("linear_velocity")
	return Vector2(lv.dot(forward(v)), lv.dot(right(v)))


## The pivot: the point on the centre line (its own frame, + = forward of the centre) with no sideways velocity,
## -lateral / yaw rate. In a gripping turn it is the rear axle; when the tail slides out it moves forward. INF while the
## body turns slower than 0.1 rad/s.
static func pivot(v: Node2D) -> float:
	var w: float = v.get("angular_velocity")
	if absf(w) <= 0.1:
		return INF
	return -local_velocity(v).y / w


## The body slip angle toward the outside of the turn (rad): + when the velocity points outside the heading (the tail is
## out, a slide), - when inside it (a gripping turn). 0 below 5 px/s or 0.05 rad/s of turn.
static func outward_slip(v: Node2D) -> float:
	var lv := local_velocity(v)
	var w: float = v.get("angular_velocity")
	if lv.length() < 5.0 or absf(w) < 0.05:
		return 0.0
	return -atan2(lv.y, absf(lv.x)) * signf(w)


## Its velocity along its own front (px/s; negative = reversing).
static func along(v: Node2D) -> float:
	return (v.get("linear_velocity") as Vector2).dot(forward(v))


# --- Moving things --------------------------------------------------------------------------

## Put a character at `point` (standing still) and let a couple of frames pass.
static func place(t: TestContext, id: StringName, point: Vector2) -> void:
	var p := t.puppet(id)
	if p != null:
		p.stop()
	t.actor(id).global_position = point
	await t.frames(2)


## Move a parked vehicle to `pos`, turned to `rot`: frozen a frame, moved, then let go (a free rigid body moved directly is
## put back by the physics step).
static func move_vehicle(t: TestContext, v: Node2D, pos: Vector2, rot: float) -> void:
	v.set("freeze", true)
	await t.frames(1)
	v.global_position = pos
	v.global_rotation = rot
	await t.frames(1)
	v.set("freeze", false)
	await t.frames(2)


## Press E for puppet `id` and wait until it is seated (true) or `timeout` passes.
static func board(t: TestContext, id: StringName, timeout := 6.0) -> bool:
	var c := t.actor(id)
	t.puppet(id).use_vehicle()
	return await t.until(func(): return c.is_in_vehicle(), timeout)


## Press E for seated puppet `id` and wait until it is out (its `vehicle()` null) or `timeout` passes.
static func exit(t: TestContext, id: StringName, timeout := 8.0) -> bool:
	var c := t.actor(id)
	t.puppet(id).use_vehicle()
	return await t.until(func(): return c.vehicle() == null, timeout)


## Walk puppet `id` to door `door_id`'s stand point, press E and wait until seated. False when it never sits.
static func board_by(t: TestContext, id: StringName, v: Node2D, door_id: StringName, timeout := 6.0) -> bool:
	await place(t, id, stand_point(v, door_id))
	return await board(t, id, timeout)


## Hold full throttle (puppet `id`) until `v` reaches `target` px/s; then let go. Whether it got there.
static func reach_speed(t: TestContext, id: StringName, v: Node, target: float, timeout := 6.0) -> bool:
	var p := t.puppet(id)
	p.drive(1.0, 0.0, false)
	var ok := await t.until(func(): return v.speed() >= target, timeout)
	p.drive(0.0, 0.0, false)
	return ok


## Drive for `duration` s holding `steer` (and `handbrake`), the throttle on below `target` px/s and off above it, calling
## `sample` each frame.
static func hold_speed(t: TestContext, id: StringName, v: Node, target: float, steer: float, handbrake: bool,
		duration: float, sample := Callable()) -> void:
	var p := t.puppet(id)
	var deadline := t.time + duration
	while t.time < deadline:
		p.drive(1.0 if v.speed() < target else 0.0, steer, handbrake)
		await t.frames(1)
		if sample.is_valid():
			sample.call()
	p.drive(0.0, 0.0, false)


# --- Drawing --------------------------------------------------------------------------------

## The vehicle's draw layer `layer_name` (`Chassis` under the occupants, `Roof` over them), or null.
static func layer(v: Node, layer_name: String) -> CanvasItem:
	return v.find_child(layer_name, true, false) as CanvasItem


## The z index `item` is drawn at, its relative parents' added in.
static func absolute_z(item: CanvasItem) -> int:
	var z := item.z_index
	var node: Node = item
	while (node as CanvasItem).z_as_relative:
		node = node.get_parent()
		if not node is CanvasItem:
			break
		z += (node as CanvasItem).z_index
	return z


## Whether `a` is drawn over `b`: a higher absolute z, or the same z and later in the tree.
static func draws_above(a: CanvasItem, b: CanvasItem) -> bool:
	var za := absolute_z(a)
	var zb := absolute_z(b)
	if za != zb:
		return za > zb
	return a.is_greater_than(b)


# --- Sound ----------------------------------------------------------------------------------

## A sound range table with nothing out of earshot, the vehicle categories included.
static func everywhere() -> Dictionary:
	var out: Dictionary = SoundConfig.category_range.duplicate()
	for k in out:
		out[k] = 1.0e9
	for k in SOUND_CATEGORIES:
		out[k] = 1.0e9
	return out
