class_name Ragdoll extends RefCounted

## A generic 3D ragdoll (Physics domain): point masses joined by bones and joint limits, stepped as
## position-based dynamics. Space is the owner's local floor plane (x, y in px) plus z = height
## above the floor: gravity pulls toward z = 0, the floor holds each point at its radius, and walls
## and solid furniture (layer 1) block x/y moves. It knows nothing of what the body is: the owner
## adds points, bones, frames (an orientation read off three points) and limits (swing cones and
## anatomical hinges, set in a frame), seeds velocities, then calls step() each physics frame until
## it sleeps. Tuning: PhysicsConfig.ragdoll_*.

## Fraction of a joint limit's violation corrected per constraint pass (softens jitter).
const LIMIT_STIFFNESS := 0.6
## Most a limit turns a bone per pass (rad): a far-out bone is brought back over several passes, so
## the correction never becomes a burst of speed.
const LIMIT_MAX_TURN := 0.3

enum { SWING, HINGE }

## True once the body has come to rest (or timed out); step() then does nothing.
var asleep := false
## Colliders the wall sweep ignores (e.g. the owner's own body).
var exclude: Array[RID] = []

var _pos := PackedVector3Array()     ## Point positions (local x/y px, z = height px).
var _prev := PackedVector3Array()    ## Positions at the start of the sub-step.
var _vel := PackedVector3Array()     ## Point velocities (px/s).
var _radius := PackedFloat32Array()  ## Point collision radii (px).
var _inv_mass := PackedFloat32Array()  ## Point inverse masses (heavier points move less).
var _bones: Array = []   ## [a, b, rest length, stiffness].
var _frames: Array = []  ## [origin, up, right, sign]: forward = (up × right) · sign.
var _limits: Array = []  ## Swing / hinge dicts (see add_swing / add_hinge).
var _params: PhysicsShapeQueryParameters2D  ## Reused wall-sweep query.
var _shapes := {}        ## Circle query shapes by radius.
var _still := 0.0        ## Seconds every point has stayed under the sleep speed.
var _time := 0.0         ## Seconds simulated.
var _primed := false     ## False until the first step pulls starting points out of walls.


# --- Building ----------------------------------------------------------------------------

## Add a point at `at` (local px, z = height) with a collision `radius` and `mass`; returns its index.
func add_point(at: Vector3, radius: float, mass: float = 1.0) -> int:
	_pos.append(at)
	_prev.append(at)
	_vel.append(Vector3.ZERO)
	_radius.append(radius)
	_inv_mass.append(1.0 / maxf(mass, 0.001))
	return _pos.size() - 1


## Join points `a` and `b` at their current distance. `stiffness` (0–1) is the share of any stretch
## corrected per pass.
func add_bone(a: int, b: int, stiffness: float = 1.0) -> void:
	_bones.append([a, b, _pos[a].distance_to(_pos[b]), stiffness])


## Bind `indices` into one rigid cluster (a bone between every pair).
func add_rigid(indices: Array) -> void:
	for i in indices.size():
		for j in range(i + 1, indices.size()):
			add_bone(indices[i], indices[j])


## An orientation read off three points each step: y = `origin` → `up`, x = toward `right` (made
## square to y), z = forward, signed so it points along `forward_hint` now. Returns its id.
func add_frame(origin: int, up: int, right: int, forward_hint: Vector3) -> int:
	_frames.append([origin, up, right, 1.0])
	var f := _frames.size() - 1
	if frame_basis(f).z.dot(forward_hint) < 0.0:
		_frames[f][3] = -1.0
	return f


## Keep `child` within a cone around `rest` from `joint` — `rest` a unit direction along the frame's
## y axis (up or down) — at most `limits` `right` / `left` / `front` / `back` radians off it toward
## the frame's +x / −x / +z / −z, blended by direction in between.
func add_swing(frame: int, joint: int, child: int, rest: Vector3, limits: Dictionary) -> void:
	_limits.append({ "kind": SWING, "frame": frame, "joint": joint, "child": child,
		"rest": rest.normalized(), "right": maxf(limits["right"], 0.01), "left": maxf(limits["left"], 0.01),
		"front": maxf(limits["front"], 0.01), "back": maxf(limits["back"], 0.01) })


## An anatomical hinge at `joint` between the parent bone (`parent` → `joint`) and the child bone
## (`joint` → `child`). Its bend side is the frame-space `bend` (square to the frame-space `rest`)
## carried by the shortest turn taking `rest` onto the live parent bone, so the hinge keeps a
## sensible plane in any limb pose. The child's bend off straight is held to [min_angle, max_angle]
## toward that side, and its twist out of the plane to ±`slack` (radians).
func add_hinge(frame: int, parent: int, joint: int, child: int, rest: Vector3, bend: Vector3,
		min_angle: float, max_angle: float, slack: float) -> void:
	_limits.append({ "kind": HINGE, "frame": frame, "parent": parent, "joint": joint, "child": child,
		"rest": rest.normalized(), "bend": bend.normalized(), "min": min_angle, "max": max_angle,
		"slack": slack })


## Add `v` (px/s) to point `i`'s velocity.
func push(i: int, v: Vector3) -> void:
	_vel[i] += v


# --- Reading -----------------------------------------------------------------------------

## Point `i`'s position (local x/y px, z = height px).
func point(i: int) -> Vector3:
	return _pos[i]


## How many points the body has.
func point_count() -> int:
	return _pos.size()


## Frame `f`'s live orientation: x right, y up, z forward (orthonormal).
func frame_basis(f: int) -> Basis:
	var fr: Array = _frames[f]
	var o := _pos[fr[0]]
	var up := (_pos[fr[1]] - o).normalized()
	var right := _pos[fr[2]] - o
	right = (right - up * right.dot(up)).normalized()
	return Basis(right, up, up.cross(right) * float(fr[3]))


# --- Stepping ----------------------------------------------------------------------------

## Wake a body that had gone to sleep and start its sleep clocks afresh, so a push is simulated and the body does not go
## straight back to sleep through `ragdoll_max_time` (an explosion throws a fallen body).
func wake() -> void:
	asleep = false
	_time = 0.0
	_still = 0.0


## Advance the body by `delta`. `space` + `origin` (the owner's world position) place the local
## points in the world for the wall sweep.
func step(delta: float, space: PhysicsDirectSpaceState2D, origin: Vector2) -> void:
	if asleep or delta <= 0.0:
		return
	if not _primed:
		_primed = true
		_pull_out_of_walls(space, origin)
	var n := maxi(1, PhysicsConfig.ragdoll_substeps)
	for _s in n:
		_substep(delta / n, space, origin)
	_time += delta
	var fastest := 0.0
	for v in _vel:
		fastest = maxf(fastest, v.length())
	_still = _still + delta if fastest < PhysicsConfig.ragdoll_sleep_speed else 0.0
	if _still >= PhysicsConfig.ragdoll_sleep_time or _time >= PhysicsConfig.ragdoll_max_time:
		asleep = true
		_vel.fill(Vector3.ZERO)


## One sub-step: predict, project the constraints and floor, sweep walls, then derive velocities
## and apply floor bounce/friction and joint friction.
func _substep(h: float, space: PhysicsDirectSpaceState2D, origin: Vector2) -> void:
	var gravity := Vector3(0.0, 0.0, -PhysicsConfig.ragdoll_gravity)
	var drag := exp(-PhysicsConfig.ragdoll_air_drag * h)
	var fall := PackedFloat32Array()  # Vertical speed before the floor stops it, for the bounce.
	fall.resize(_pos.size())
	var free := PackedFloat32Array()  # Speed before the constraints act on it.
	free.resize(_pos.size())
	for i in _pos.size():
		_vel[i] = (_vel[i] + gravity * h) * drag
		_prev[i] = _pos[i]
		_pos[i] += _vel[i] * h
		fall[i] = _vel[i].z
		free[i] = _vel[i].length()
	for _k in maxi(1, PhysicsConfig.ragdoll_iterations):
		for bone in _bones:
			_solve_bone(bone)
		for limit in _limits:
			if limit["kind"] == SWING:
				_solve_swing(limit)
			else:
				_solve_hinge(limit)
		_solve_floor()
	_sweep_walls(space, origin)

	var friction := PhysicsConfig.ragdoll_floor_friction * h
	var gain := PhysicsConfig.ragdoll_max_push * h
	for i in _pos.size():
		# The constraints may pass momentum along the body but never pump it up: a point leaves them
		# no faster than it came in, plus a push no harder than `ragdoll_max_push`.
		var v := ((_pos[i] - _prev[i]) / h).limit_length(minf(free[i] + gain, PhysicsConfig.ragdoll_max_speed))
		if _pos[i].z <= _radius[i] + 0.01:
			if _prev[i].z > _radius[i] + 0.01 and fall[i] < 0.0:
				v.z = -fall[i] * PhysicsConfig.ragdoll_floor_bounce
			var flat := Vector2(v.x, v.y).move_toward(Vector2.ZERO, friction)
			v.x = flat.x
			v.y = flat.y
		_vel[i] = v
	var hold := 1.0 - exp(-PhysicsConfig.ragdoll_joint_friction * h)
	for limit in _limits:
		var j: int = limit["joint"]
		var c: int = limit["child"]
		_vel[c] = _vel[c].lerp(_vel[j], hold)


## Restore a bone's length, split by inverse mass.
func _solve_bone(bone: Array) -> void:
	var a: int = bone[0]
	var b: int = bone[1]
	var d := _pos[b] - _pos[a]
	var length := d.length()
	var total := _inv_mass[a] + _inv_mass[b]
	if length < 0.0001 or total <= 0.0:
		return
	var fix := d * ((length - float(bone[2])) / length * float(bone[3]) / total)
	_pos[a] += fix * _inv_mass[a]
	_pos[b] -= fix * _inv_mass[b]


## Hold a swing limit's child inside its cone.
func _solve_swing(l: Dictionary) -> void:
	var j: int = l["joint"]
	var c: int = l["child"]
	var d := _pos[c] - _pos[j]
	var length := d.length()
	if length < 0.0001:
		return
	var b := frame_basis(l["frame"])
	var w := d / length
	var local := Vector3(w.dot(b.x), w.dot(b.y), w.dot(b.z))
	var rest: Vector3 = l["rest"]
	var cos_t := clampf(local.dot(rest), -1.0, 1.0)
	var swing := local - rest * cos_t
	if swing.length_squared() < 0.00000001:
		if cos_t > 0.0:
			return  # On the rest axis: inside any cone.
		swing = Vector3(0.0, 0.0, 1.0)  # Straight opposite: bring it round the front.
	swing = swing.normalized()
	var lx: float = l["right"] if swing.x > 0.0 else l["left"]
	var lz: float = l["front"] if swing.z > 0.0 else l["back"]
	var max_t := lerpf(lz, lx, atan2(absf(swing.x), absf(swing.z)) / (PI * 0.5))
	if acos(cos_t) <= max_t:
		return
	var fixed := rest * cos(max_t) + swing * sin(max_t)
	_turn_child(j, c, w, b * fixed, length)


## Hold a hinge's child bone to its bend range and plane.
func _solve_hinge(l: Dictionary) -> void:
	var p: int = l["parent"]
	var j: int = l["joint"]
	var c: int = l["child"]
	var upper := _pos[j] - _pos[p]
	var d := _pos[c] - _pos[j]
	var length := d.length()
	if upper.length_squared() < 0.00000001 or length < 0.0001:
		return
	var u := upper.normalized()
	var b := frame_basis(l["frame"])
	var rest: Vector3 = b * (l["rest"] as Vector3)
	var bend: Vector3 = b * (l["bend"] as Vector3)
	# The bend side carried along with the parent bone (a half turn flips it outright).
	var n: Vector3 = -bend if rest.dot(u) < -0.999 else Quaternion(rest, u) * bend
	n = n - u * n.dot(u)
	if n.length_squared() < 0.00000001:
		return
	n = n.normalized()
	var side := u.cross(n)
	var w := d / length
	var cos_t := clampf(w.dot(u), -1.0, 1.0)
	var theta := acos(cos_t)
	var perp := w - u * cos_t
	var phi := atan2(perp.dot(side), perp.dot(n)) if perp.length_squared() > 0.00000001 else 0.0
	var theta_ok := clampf(theta, l["min"], l["max"])
	var phi_ok := clampf(phi, -float(l["slack"]), float(l["slack"]))
	if is_equal_approx(theta_ok, theta) and is_equal_approx(phi_ok, phi):
		return
	var fixed := u * cos(theta_ok) + (n * cos(phi_ok) + side * sin(phi_ok)) * sin(theta_ok)
	_turn_child(j, c, w, fixed, length)


## Move `child` (and `joint`, by inverse mass) part way from lying along `from` toward lying along
## `dir` at `length` from the joint (both unit), turning it at most LIMIT_MAX_TURN.
func _turn_child(j: int, c: int, from: Vector3, dir: Vector3, length: float) -> void:
	var total := _inv_mass[j] + _inv_mass[c]
	if total <= 0.0:
		return
	var turn := from.angle_to(dir)
	if turn > LIMIT_MAX_TURN:
		dir = from.slerp(dir, LIMIT_MAX_TURN / turn)
	var fix := (_pos[j] + dir * length - _pos[c]) * LIMIT_STIFFNESS
	_pos[c] += fix * (_inv_mass[c] / total)
	_pos[j] -= fix * (_inv_mass[j] / total)


## No point sinks below the floor.
func _solve_floor() -> void:
	for i in _pos.size():
		if _pos[i].z < _radius[i]:
			var p := _pos[i]
			p.z = _radius[i]
			_pos[i] = p


## Sweep each point's x/y move this sub-step against walls and solid furniture: stop where it first
## touches, then slide the rest along the surface.
func _sweep_walls(space: PhysicsDirectSpaceState2D, origin: Vector2) -> void:
	for i in _pos.size():
		var from := Vector2(_prev[i].x, _prev[i].y)
		var to := Vector2(_pos[i].x, _pos[i].y)
		var reached := _sweep(space, origin, from, to, _radius[i])
		if reached != to:
			_pos[i] = Vector3(reached.x, reached.y, _pos[i].z)


## Before the first step: draw any point that starts inside a wall back toward the origin (the
## owner's own free center).
func _pull_out_of_walls(space: PhysicsDirectSpaceState2D, origin: Vector2) -> void:
	for i in _pos.size():
		var to := Vector2(_pos[i].x, _pos[i].y)
		var reached := _sweep(space, origin, Vector2.ZERO, to, _radius[i])
		_pos[i] = Vector3(reached.x, reached.y, _pos[i].z)
		_prev[i] = _pos[i]


## Where a circle of `radius` moving from `from` to `to` (local) comes to rest: at its first contact
## with layer 1, slid along the surface for the rest of the move.
func _sweep(space: PhysicsDirectSpaceState2D, origin: Vector2, from: Vector2, to: Vector2,
		radius: float) -> Vector2:
	var motion := to - from
	if motion.length_squared() < 0.0001:
		return to
	var params := _query(radius)
	params.transform = Transform2D(0.0, origin + from)
	params.motion = motion
	var res := space.cast_motion(params)
	if res[0] >= 1.0:
		return to
	if res[1] <= 0.0:
		# Touching at the start: only a move that ends clear is allowed (away from the surface).
		params.transform = Transform2D(0.0, origin + to)
		params.motion = Vector2.ZERO
		return to if space.intersect_shape(params, 1).is_empty() else from
	var rest := from + motion * res[0]
	params.transform = Transform2D(0.0, origin + from + motion * res[1])
	params.motion = Vector2.ZERO
	var info := space.get_rest_info(params)
	var normal: Vector2 = info["normal"] if info.has("normal") else -motion.normalized()
	var slide := (motion * (1.0 - res[0])).slide(normal)
	params.transform = Transform2D(0.0, origin + rest)
	params.motion = slide
	var res2 := space.cast_motion(params)
	return rest + slide * res2[0]


## The reused wall query, set to a circle of `radius`.
func _query(radius: float) -> PhysicsShapeQueryParameters2D:
	if _params == null:
		_params = PhysicsShapeQueryParameters2D.new()
		_params.collision_mask = PhysicsConfig.wall_mask
		_params.exclude = exclude
	if not _shapes.has(radius):
		var circle := CircleShape2D.new()
		circle.radius = radius
		_shapes[radius] = circle
	_params.shape = _shapes[radius]
	return _params
