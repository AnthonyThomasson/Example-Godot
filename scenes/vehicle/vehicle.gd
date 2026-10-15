extends RigidBody2D

## Vehicles domain: a drivable vehicle (a car or a van, `kind`, tuned by its `VehicleConfig.kinds` row). The control
## layer: a rigid body on `PhysicsLayers.SOLID` that the physics engine moves and collides, driven by the bicycle model
## (vehicle_drive.gd) inside `_integrate_forces` from the drive intent its driver hands on. It owns its doors
## (vehicle_door.gd) and seats, and the rides of the characters getting in and out (vehicle_boarding.gd, stepped by each
## character's CharacterVehicleUse). Drawing is vehicle_visuals.gd on the `Chassis` (under the occupants) and `Roof` (over
## them) children. Vehicles are found by the group `vehicles`.
##
## The drivable contract (interface 19): `doors()`, `seats()`, `driver()`, `board(character, door)`, `exit(character)`,
## `drive_input(...)`, and the reads `speed()`, `engine_state()`, `slip()`, `wheel_angle()`, `brake_lights()`,
## `view_zoom_out()`.
## It is also hittable like furniture (`get_surface` / `take_hit`: dents through Physics' Deformable, debris and a shove)
## and pushable through RigidBody2D's own `apply_impulse(v, at)` / `get_mass()`. Its contacts post crashes, and a
## character it strikes (directly, or through a piece of furniture pressed against it) is knocked back and hurt by the
## closing speed, the vehicle losing only the momentum the character and what it is pressed against take. The `vehicle`, `engine` and `skid` EventBus
## topics are posted here.

const VehicleDoor = preload("res://scenes/vehicle/vehicle_door.gd")
const VehicleDrive = preload("res://scenes/vehicle/vehicle_drive.gd")
const VehicleBoarding = preload("res://scenes/vehicle/vehicle_boarding.gd")

## Which `VehicleConfig.kinds` row this is.
@export var kind: StringName = &"car"
## The body's paint.
@export var color: Color = Color(0.62, 0.13, 0.12)

var _row: Dictionary  ## Its kind's `VehicleConfig.kinds` row.
var _doors: Array[VehicleDoor] = []  ## Its doors, in the row's order.
## Seat id -> who holds it (boarding into it, sitting in it or getting out of it), or null.
var _seats: Dictionary = {}
## Seat id -> the character on its way into it from another seat (a passenger sliding across to the wheel).
var _reserved: Dictionary = {}
## Character -> its ride (VehicleBoarding), from the E press to its last step out.
var _rides: Dictionary = {}
var _drive := VehicleDrive.new()  ## The driving model, stepped in `_integrate_forces`.
## The drive intent the driver handed on (`drive_input` / `brake_input`); zero with nobody at the wheel.
var _intent := { "throttle": 0.0, "steer": 0.0, "handbrake": false, "brake": false }
var _running := false  ## The engine runs.
var _skidding := false  ## A `skid` is under way.
var _deformable: Deformable  ## Records the dents.
## The velocities the last physics step began with: what an impact found this step was struck at.
var _last_velocity := Vector2.ZERO
var _last_spin := 0.0
## The bodies touching the vehicle at the last step (instance id -> true), to tell a new impact from a lasting contact.
var _touching: Dictionary = {}
## What the contacts found, carried out in `_physics_process` (outside the physics server's flush, where a death may
## change bodies): `{ body, push, harm, position }`, a character or a piece shoved by `push` (an impulse) and, for a
## character newly struck, hurt by the closing speed `harm` (0: not hurt).
var _struck: Array = []
## When (the vehicle's own physics clock, s) each living character was last in a pile (instance id -> time): one struck
## again within `rehit_time` is the same run-in, shoved on but not hurt again.
var _piled: Dictionary = {}
var _clock := 0.0  ## Its own physics clock (s), advanced each step in `_integrate_forces`.


func _ready() -> void:
	_row = VehicleConfig.kinds[kind]
	add_to_group(&"vehicles")
	# Before the characters each frame: a character struck at the last step is shoved before it moves, so it moves off
	# in this frame and is not met where it stood by the next step.
	process_physics_priority = -1
	var size: Vector2 = _row["size"]
	mass = _row["mass"]
	inertia = mass * (size.x * size.x + size.y * size.y) / 12.0
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector2.ZERO
	gravity_scale = 0.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = PhysicsLayers.SOLID
	collision_mask = PhysicsLayers.SOLID
	var surface := PhysicsMaterial.new()
	surface.bounce = _row["bounce"]
	surface.friction = _row["friction"]
	physics_material_override = surface
	_build_collider()
	for def: Dictionary in _row["doors"]:
		_doors.append(VehicleDoor.new(def))
	for id in _row["seats"]:
		_seats[id] = null
	_deformable = Deformable.new()
	_deformable.max_depth = VehicleConfig.dent_max_depth
	_deformable.allow_chunks = false
	_deformable.max_impacts = VehicleConfig.dent_max_impacts
	add_child(_deformable)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_read_contacts(state)
	_drive.step(state, _row, _intent, _running)
	_last_velocity = state.linear_velocity
	_last_spin = state.angular_velocity


func _physics_process(delta: float) -> void:
	for d in _doors:
		if d.update(delta):
			_post(&"slide_close" if d.kind == &"slide" else &"door_close", to_global(d.handle))
	_apply_struck()
	_update_skid()


# --- The drivable contract (interface 19) ------------------------------------------------

## The doors, world space: `[{ id, kind, seat, handle, open, hinge, angle, offset }]` (`open` 0..1, `angle` how far a
## swing or rear door is turned, `offset` how far a sliding door has rolled).
func doors() -> Array:
	return _doors.map(func(d): return d.info(self))


## The seats: `[{ id, occupant }]`, the occupant the character holding it (boarding, seated or getting out) or null.
func seats() -> Array:
	var out := []
	for id in _seats:
		out.append({ "id": id, "occupant": occupant(id) })
	return out


## Who holds the driver's seat (null when nobody).
func driver() -> Node:
	return occupant(&"driver")


## Start `character` boarding by door `door_id`: it walks to the door, which opens, and gets in to the seat behind it.
## Returns the ride for its CharacterVehicleUse to step, or null when that door cannot be used now: the vehicle moves
## at `board_max_speed` or faster, the seat is taken, or the door's swing (or the stand point beside it) is blocked.
func board(character: Node2D, door_id: StringName) -> RefCounted:
	var by := _door(door_id)
	if by == null or speed() >= VehicleConfig.board_max_speed or _rides.has(character) or not is_free(by.seat):
		return null
	if not by.is_clear(self, [get_rid(), character.get_rid()], character.radius):
		return null
	_seats[by.seat] = character
	var ride := VehicleBoarding.new(self, character, by)
	_rides[character] = ride
	character.add_collision_exception_with(self)
	return ride


## `character`, seated, asks to get out (it brakes or waits for the vehicle to slow first; with no clear door it stays
## in). False when it is not seated here.
func exit(character: Node2D) -> bool:
	var ride: VehicleBoarding = _rides.get(character)
	if ride == null or not ride.is_seated():
		return false
	ride.request_exit()
	return true


## The drive intent from `character`'s keys: `throttle` (1 = W, -1 = S: brake, then reverse), `steer` (1 = right,
## relative to the vehicle) and `handbrake`. Only the driver drives.
func drive_input(character: Node2D, throttle: float, steer: float, handbrake: bool) -> void:
	if driver() != character or not _running:
		return
	_intent = { "throttle": throttle, "steer": steer, "handbrake": handbrake, "brake": false }
	if throttle != 0.0 or steer != 0.0:
		sleeping = false


## How fast it moves (px/s, unsigned).
func speed() -> float:
	return linear_velocity.length()


## The engine: `{ running, rpm, load }` (revs 0..1 of the redline with a gear-like rise and drop, load the throttle).
func engine_state() -> Dictionary:
	return { "running": _running, "rpm": _drive.rpm, "load": _drive.engine_load }


## How much it slides: 0 while the tyres grip, rising with the slide.
func slip() -> float:
	return _drive.slip


## The front wheels' steering angle (rad, + = to the right), as they are drawn.
func wheel_angle() -> float:
	return _drive.wheel_angle


## True while braking (the brake lights show).
func brake_lights() -> bool:
	return _drive.braking


## How far a camera following someone aboard zooms out (V8): `VehicleConfig.drive_zoom_out` at the top speed, in
## proportion below it, none at rest.
func view_zoom_out() -> float:
	return VehicleConfig.drive_zoom_out * clampf(speed() / float(_row["top_speed"]), 0.0, 1.0)


# --- Hittable contract (interface 3) -----------------------------------------------------

## A metal body: high coverage, hard to shoot through.
func get_surface() -> Dictionary:
	return { "coverage": _row["coverage"], "penetration": _row["penetration"], "material": _row["material"], "color": color }


## A hit dents the body where it struck, throws debris and shoves it at the contact point. A vehicle is never destroyed.
func take_hit(hit: HitInfo) -> void:
	apply_impulse(Physics.impact_impulse(hit), hit.position - global_position)
	_deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())


## The dents (Deformable impacts, local), for the visuals.
func hit_marks() -> Array:
	return _deformable.impacts


# --- Vehicles-internal: what a ride and the visuals use ----------------------------------

## Half the body's length and width (px).
func half_size() -> Vector2:
	return (_row["size"] as Vector2) * 0.5


## The body's outline (local): its rectangle with chamfered corners. The collider, and what the visuals paint.
func outline() -> PackedVector2Array:
	var half := half_size()
	var c: float = _row["corner"]
	return PackedVector2Array([
		Vector2(half.x, -half.y + c), Vector2(half.x, half.y - c), Vector2(half.x - c, half.y), Vector2(-half.x + c, half.y),
		Vector2(-half.x, half.y - c), Vector2(-half.x, -half.y + c), Vector2(-half.x + c, -half.y), Vector2(half.x - c, -half.y),
	])


## The kind's tuning row.
func row() -> Dictionary:
	return _row


## The door objects (VehicleDoor), for the visuals.
func door_list() -> Array[VehicleDoor]:
	return _doors


## Where seat `id` is (local).
func seat_point(id: StringName) -> Vector2:
	return _row["seats"][id]


## Who holds seat `id` (null when empty or freed).
func occupant(id: StringName) -> Node:
	var who: Variant = _seats.get(id)
	return who if is_instance_valid(who) else null


## Whether seat `id` is free: nobody holds it or is on the way into it.
func is_free(id: StringName) -> bool:
	return occupant(id) == null and not is_instance_valid(_reserved.get(id))


## Hold seat `id` for `character` while it slides across the bench to it.
func reserve(character: Node2D, id: StringName) -> void:
	_reserved[id] = character


## Move `character` to seat `id` (it has slid across the bench).
func change_seat(character: Node2D, id: StringName) -> void:
	for s in _seats:
		if _seats[s] == character:
			_seats[s] = null
	_seats[id] = character
	_reserved.erase(id)


## `character` gives up its seat and its ride (out, given up, or dead). A driver leaving cuts the engine.
func release(character: Node2D) -> void:
	for s in _seats:
		if _seats[s] == character:
			_seats[s] = null
			if s == &"driver":
				stop_engine()
	for s in _reserved.keys():
		if _reserved[s] == character:
			_reserved.erase(s)
	_rides.erase(character)


## Open `which` (posting the handle's click the moment a shut door starts to open).
func open_door(which: VehicleDoor) -> void:
	if which.open():
		_post(&"slide_open" if which.kind == &"slide" else &"door_open", to_global(which.handle))


## Close `which` (the slam is posted when it shuts).
func close_door(which: VehicleDoor) -> void:
	which.close()


## The driver has sat down: the ignition cranks and the engine runs.
func start_engine() -> void:
	if _running:
		return
	_running = true
	can_sleep = false  # Its wheels and revs follow the driver even at rest.
	sleeping = false
	_post(&"ignition", global_position)
	EventBus.post(&"engine", { "vehicle": self, "kind": kind, "stage": &"start" })


## Cut the engine (the driver has left the seat): nobody drives it, and it rolls to a stop.
func stop_engine() -> void:
	_intent = { "throttle": 0.0, "steer": 0.0, "handbrake": false, "brake": false }
	if not _running:
		return
	_running = false
	can_sleep = true
	EventBus.post(&"engine", { "vehicle": self, "kind": kind, "stage": &"stop" })


## The driver brakes to a stop (getting out at speed).
func brake_input(character: Node2D) -> void:
	if driver() == character:
		_intent = { "throttle": 0.0, "steer": 0.0, "handbrake": false, "brake": true }


## The door `character`, in `seat`, gets out by: `own` (the one it got in by) when clear, else the nearest clear door
## whose seat is its own or empty; null when none is clear.
func exit_door(character: Node2D, seat: StringName, own: VehicleDoor) -> VehicleDoor:
	var exclude: Array[RID] = [get_rid(), character.get_rid()]
	if own != null and own.seat == seat and own.is_clear(self, exclude, character.radius):
		return own
	var best: VehicleDoor = null
	var best_distance := INF
	for d in _doors:
		if d.seat != seat and not is_free(d.seat):
			continue
		var distance: float = character.global_position.distance_to(to_global(d.handle))
		if distance < best_distance and d.is_clear(self, exclude, character.radius):
			best = d
			best_distance = distance
	return best


# --- Contacts: crashes and characters struck (V6) ----------------------------------------

## Read this step's contacts, each body's closing speed taken from the velocities the step began with. A body newly
## struck faster than `crash_min_speed` posts a crash at once (the step that stopped the vehicle is the one it is heard
## in). Furniture alone is left to the solver, which shoves it; a contact with a living character in its pile (the
## character itself, or a piece pressed against one) goes through `_strike_pile`, and a dead body is rolled over.
func _read_contacts(state: PhysicsDirectBodyState2D) -> void:
	var touching := {}
	var struck := {}  # instance id -> the strongest contact with that body: { body, speed, position, normal, new }
	for i in state.get_contact_count():
		var body := state.get_contact_collider_object(i) as Node
		if body == null:
			continue
		var at := state.get_contact_local_position(i)
		var normal := state.get_contact_local_normal(i)
		var offset := at - state.transform.origin
		if offset.dot(normal) < 0.0:
			normal = -normal  # Out of the vehicle, into the other body.
		var ours := _last_velocity + Vector2(-offset.y, offset.x) * _last_spin
		var closing := (ours - _velocity_of(body, state, i)).dot(normal)
		var id := body.get_instance_id()
		touching[id] = true
		if not struck.has(id) or closing > struck[id]["speed"]:
			struck[id] = { "body": body, "speed": closing, "position": at, "normal": normal, "new": not _touching.has(id) }
	_clock += state.step
	var done := {}  # bodies already met in a pile this step
	for id in struck:
		var hit: Dictionary = struck[id]
		var body: Node = hit["body"]
		var character := _is_character(body)
		var living: bool = character and not body.is_dead
		# A living character is always seen to (the solver may stop the vehicle on it even as it moves off); anything
		# else only while the vehicle closes on it.
		if done.has(id) or (hit["speed"] <= 0.0 and not living):
			continue
		if character and not living:
			# A dead body is rolled over: the vehicle keeps its speed along the contact and stops colliding with it.
			var normal: Vector2 = hit["normal"]
			state.linear_velocity += normal * (_last_velocity.dot(normal) - state.linear_velocity.dot(normal))
			_struck.append({ "body": body, "push": Vector2.ZERO, "harm": 0.0, "position": hit["position"] })
			continue
		var pile := _pile(body, hit["normal"]) if character or _is_piece(body) else {}
		for member: Dictionary in pile.get("members", []):
			done[(member["body"] as Node).get_instance_id()] = true
		if pile.get("people", 0) > 0:
			_strike_pile(state, hit, pile)
		elif hit["new"] and hit["speed"] > VehicleConfig.crash_min_speed:
			var surface: Dictionary = body.get_surface() if body.has_method("get_surface") else {}
			_post(&"crash", hit["position"], { "speed": hit["speed"], "material": String(surface.get("material", "")) })
	_touching = touching
	for id in _piled.keys():
		if _clock - float(_piled[id]) > VehicleConfig.rehit_time:
			_piled.erase(id)


## Strike the pile `hit` heads (one with a living character in it). The solver treats a character as immovable, so it
## has stopped the vehicle (and any piece pressing one) against it as against a wall. Where nothing solid stands behind
## the pile, that stop is undone: the vehicle and the pile meet as two bodies (the pile's mass all its members', with
## the character's bounce `harm_bounce` on a first touch by a character, the vehicle's own `bounce` by a piece, none
## while it keeps pushing), so the vehicle loses only the momentum the pile takes, and each member is shoved up to the
## pile's new speed. Pinned against a wall (or anything else not pushable), the vehicle stops as on a wall and posts a
## crash. Each living character newly in the pile (not in one for `rehit_time`) is hurt by the speed it is struck at:
## the vehicle's closing speed, less what the pieces between them took of it (the vehicle and those pieces carrying the
## blow on as one).
func _strike_pile(state: PhysicsDirectBodyState2D, hit: Dictionary, pile: Dictionary) -> void:
	var normal: Vector2 = hit["normal"]
	var members: Array = pile["members"]
	# How fast the pile moves along the contact: its slowest member, each at its own velocity (a character's what it
	# moves at by itself, its walk and knockback: pressed against the vehicle it may be held back a frame).
	var pile_speed := INF
	var pile_mass := 0.0
	for member: Dictionary in members:
		pile_speed = minf(pile_speed, _along(member, normal))
		pile_mass += member["mass"]
	var offset: Vector2 = hit["position"] - state.transform.origin
	var ours := (_last_velocity + Vector2(-offset.y, offset.x) * _last_spin).dot(normal)
	var closing := ours - pile_speed
	if closing <= 0.0:
		# The pile moves off at least as fast: the vehicle keeps what it had along the contact.
		if pile["blocked"] == null:
			state.linear_velocity += normal * (_last_velocity.dot(normal) - state.linear_velocity.dot(normal))
		return
	var first_is_character: bool = (members[0] as Dictionary)["character"]
	if pile["blocked"] != null:
		# Pinned: the vehicle stops as the solver stopped it, as on a wall.
		if hit["new"] and closing > VehicleConfig.crash_min_speed:
			var blocker: Node = pile["blocked"]
			var surface: Dictionary = blocker.get_surface() if blocker.has_method("get_surface") else {}
			_post(&"crash", hit["position"], { "speed": closing, "material": String(surface.get("material", "")) })
	else:
		var bounce := 0.0
		if hit["new"]:
			bounce = VehicleConfig.harm_bounce if first_is_character else float(_row["bounce"])
		var impulse := (1.0 + bounce) * closing * mass * pile_mass / (mass + pile_mass)
		var along := _last_velocity.dot(normal) - impulse / mass
		state.linear_velocity += normal * (along - state.linear_velocity.dot(normal))
		var pile_to := pile_speed + impulse / pile_mass
		for member: Dictionary in members:
			var body: Node = member["body"]
			var moving := _along(member, normal)
			if pile_to > moving:
				_struck.append({ "body": body, "push": normal * member["mass"] * (pile_to - moving), "harm": 0.0, "position": hit["position"] })
	for member: Dictionary in members:
		if not member["character"]:
			continue
		var body: Node = member["body"]
		var id := body.get_instance_id()
		if not _piled.has(id):
			var struck_at: float = closing * mass / (mass + float(member["through"]))
			_struck.append({ "body": body, "push": Vector2.ZERO, "harm": struck_at, "position": body.global_position })
		_piled[id] = _clock


## How fast pile member `member` moves along `normal` by itself: a character its own velocity, a piece its rigid body's.
static func _along(member: Dictionary, normal: Vector2) -> float:
	var body: Node = member["body"]
	return ((body.velocity if member["character"] else body.linear_velocity) as Vector2).dot(normal)


## The pile `first` heads along `normal` (out of the vehicle): `first` and the bodies pressed one against the next in
## front of it, found through the characters in it (a character's circle, `radius`, moved `pile_gap` on along the
## normal), up to `pile_depth` of them. Returns `{ members: [{ body, mass, character, through }], people, blocked }`:
## `through` the mass of the pieces between the vehicle and that member, `people` the living characters, `blocked`
## what stops the pile (a wall or anything else that is not pushable) or null. Furniture pressing furniture is the
## solver's, so a piece is followed only into the characters it presses.
func _pile(first: Node, normal: Vector2) -> Dictionary:
	var members: Array = [{ "body": first, "mass": float(first.get_mass()), "character": _is_character(first), "through": 0.0 }]
	var exclude: Array[RID] = [get_rid(), first.get_rid()]
	var blocked: Node = null
	var i := 0
	while i < members.size() and members.size() < VehicleConfig.pile_depth:
		var member: Dictionary = members[i]
		i += 1
		var found := _pressed_by(member, normal, exclude)
		if found.get("blocked") != null:
			blocked = found["blocked"]
			break
		var through: float = member["through"] + (0.0 if member["character"] else float(member["mass"]))
		for body: Node in found.get("bodies", []):
			if members.size() >= VehicleConfig.pile_depth:
				break
			exclude.append(body.get_rid())
			members.append({ "body": body, "mass": float(body.get_mass()), "character": _is_character(body), "through": through })
	var people := 0
	for member: Dictionary in members:
		if member["character"]:
			people += 1
	return { "members": members, "people": people, "blocked": blocked }


## What pile member `member` presses into along `normal`: `{ bodies, blocked }`. A character: whatever its circle moved
## `pile_gap` on meets ahead of it (a living character, a pushable piece; anything else blocks the pile). A piece: the
## living characters within `pile_reach` of it whose circles, moved `pile_gap` back toward it, meet it.
func _pressed_by(member: Dictionary, normal: Vector2, exclude: Array[RID]) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var body: Node2D = member["body"]
	var circle := CircleShape2D.new()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = PhysicsLayers.SOLID
	var bodies: Array = []
	if member["character"]:
		circle.radius = body.radius
		query.transform = Transform2D(0.0, body.global_position + normal * VehicleConfig.pile_gap)
		query.exclude = exclude
		var met := space.intersect_shape(query, 8)
		for result: Dictionary in met:
			var other := result["collider"] as Node2D
			if other == null:
				continue
			if _is_character(other):
				if not other.is_dead and (other.global_position - body.global_position).normalized().dot(normal) > 0.5:
					bodies.append(other)
				continue
			if not _faces_push(space, query, met, result, normal):
				continue
			if not _is_piece(other):
				return { "blocked": other }
			bodies.append(other)
		return { "bodies": bodies }
	circle.radius = VehicleConfig.pile_reach
	query.transform = Transform2D(0.0, body.global_position)
	query.exclude = exclude
	for result: Dictionary in space.intersect_shape(query, 16):
		var other := result["collider"] as Node2D
		if other == null or not _is_character(other) or other.is_dead or (other.global_position - body.global_position).dot(normal) <= 0.0:
			continue
		var back := PhysicsShapeQueryParameters2D.new()
		var own := CircleShape2D.new()
		own.radius = other.radius
		back.shape = own
		back.collision_mask = PhysicsLayers.SOLID
		back.transform = Transform2D(0.0, other.global_position - normal * VehicleConfig.pile_gap)
		back.exclude = [get_rid(), other.get_rid()]
		for touched: Dictionary in space.intersect_shape(back, 8):
			if touched["collider"] == body:
				bodies.append(other)
				break
	return { "bodies": bodies }


## Whether the body of `result` (one of `met`, what `query` overlaps) faces the push: the nearest point of its surface the
## query's circle meets has its normal against `normal`, so the circle runs into it rather than brushing past it.
static func _faces_push(space: PhysicsDirectSpaceState2D, query: PhysicsShapeQueryParameters2D, met: Array, result: Dictionary, normal: Vector2) -> bool:
	var alone := PhysicsShapeQueryParameters2D.new()
	alone.shape = query.shape
	alone.transform = query.transform
	alone.collision_mask = query.collision_mask
	var exclude := query.exclude.duplicate()
	for other: Dictionary in met:
		if other["rid"] != result["rid"]:
			exclude.append(other["rid"])
	alone.exclude = exclude
	var rest := space.get_rest_info(alone)
	return not rest.is_empty() and (rest["normal"] as Vector2).dot(normal) < -0.5


## Carry out what the contacts found: shove each body by its push and hurt each character newly struck (posting a bump
## above `crash_min_speed`; harm from `harm_min_speed`, the whole health at `harm_kill_speed`). A dead character is a body
## on the floor that the vehicle rolls over: it stops colliding with it.
func _apply_struck() -> void:
	var struck := _struck
	_struck = []
	for hit: Dictionary in struck:
		var body: Node = hit["body"]
		if not is_instance_valid(body):
			continue
		var character := _is_character(body)
		if character and body.is_dead:
			add_collision_exception_with(body)
			continue
		if hit["push"] != Vector2.ZERO:
			body.apply_impulse(hit["push"])
		var closing: float = hit["harm"]
		if not character or closing <= 0.0:
			continue
		if closing > VehicleConfig.crash_min_speed:
			_post(&"bump_character", hit["position"], { "speed": closing })
		var harm := inverse_lerp(VehicleConfig.harm_min_speed, VehicleConfig.harm_kill_speed, closing)
		if harm > 0.0:
			body.take_damage(float(body.health) * minf(harm, 1.0))
		if body.is_dead:
			add_collision_exception_with(body)


## How fast `body` moves at contact `i`: a rigid body's velocity at the point as the physics server has it; a character
## (a kinematic body: neither its server velocity nor the motion that pushed it out of the vehicle is its own) the
## velocity it moves at by itself, its walk and any knockback.
static func _velocity_of(body: Node, state: PhysicsDirectBodyState2D, i: int) -> Vector2:
	if body is CharacterBody2D:
		return (body as CharacterBody2D).velocity
	return state.get_contact_collider_velocity_at_position(i)


## Whether `body` is a character (the group `characters`, interface 7).
static func _is_character(body: Node) -> bool:
	return body.is_in_group(&"characters")


## Whether `body` is a piece the vehicle can shove on: a free rigid body with the pushable contract (furniture, another
## vehicle).
static func _is_piece(body: Node) -> bool:
	return body is RigidBody2D and not (body as RigidBody2D).freeze and body.has_method("apply_impulse") and body.has_method("get_mass")


# --- Skids -------------------------------------------------------------------------------

## Post a `skid` start when the tyres begin to slide and a stop when they grip again.
func _update_skid() -> void:
	var sliding := _drive.slip > (VehicleConfig.skid_stop_slip if _skidding else VehicleConfig.skid_start_slip) and speed() > VehicleConfig.stop_speed
	if sliding == _skidding:
		return
	_skidding = sliding
	EventBus.post(&"skid", { "vehicle": self, "stage": &"start" if sliding else &"stop" })


# --- Helpers -----------------------------------------------------------------------------

## Post a `vehicle` event at `stage`, at `where`, with `extra` fields.
func _post(stage: StringName, where: Vector2, extra := {}) -> void:
	var data := { "position": where, "kind": kind, "stage": stage }
	data.merge(extra)
	EventBus.post(&"vehicle", data)


## Door `id`, or null.
func _door(id: StringName) -> VehicleDoor:
	for d in _doors:
		if d.id == id:
			return d
	return null


## The body's collider: its outline (built here, the runtime-shape convention).
func _build_collider() -> void:
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(outline())  # The hull, wound the way the physics server expects.
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
