class_name ThrownGrenade extends Node2D

## A grenade let go into the world (Items domain): it flies a lob on a pseudo-height to the aim point, strikes walls and
## furniture taller than the arc is high there (the same `coverage` scale as everything else) and the characters in its
## way, bounces off them with energy loss, skids to a stop and goes off when its fuse runs out. Docs: `docs/grenades.md`
## G3, G6 and G10. A world `Node2D` like `DroppedItem`; nobody picks it up or throws it back. While it lives it is in the
## group `live_grenades` (`kind`, `fuse_left()`, `throw_stats()`, `thrower`) for perception to query.
##
## The lob is planned once at the throw (`plan`): its flight time and gravity are solved so the grenade comes to REST at
## the aim point (the touchdown, a bounce or two and the skid are simulated with the very integrator the node then
## runs), except that a throw is capped at the row's `max_range` of first touchdown, and rolls on a little past it.
## On the fuse's end it calls the Projectile System's `Explosion.frag` / `Explosion.stun` with its `GrenadeConfig` row.

## Physics layers it strikes (walls + solid furniture + the living).
const SOLID_MASK := PhysicsLayers.SOLID
## What a collider with no surface of its own counts as: it always stops a grenade.
const UNKNOWN_COVERAGE := 100.0
## It is at rest once it rolls slower than this (px/s).
const REST_SPEED := 4.0
## A wall strike slower than this (px/s) is a nudge, not a clatter.
const MIN_CLATTER_SPEED := 30.0
## Steps of the planner's search, and the longest it simulates (physics frames).
const PLAN_STEPS := 22
const PLAN_FRAMES := 600
## Physics step the plan is simulated at (the game's).
const PLAN_DELTA := 1.0 / 60.0

@export var radius: float = 3.0              ## Its size against walls (px).
@export var spin_friction: float = 14.0      ## Spin deceleration on the floor (rad/s²).
@export var shadow_per_height: float = 0.06  ## Shadow shift per px of height.

## Which grenade this is (a `GrenadeConfig` id) and who threw it (may be gone by the time it goes off).
var kind: StringName = &""
var thrower: Node  ## Who threw it; it may be gone by the time it goes off.
## The grenade item that draws it.
var item: Item

var _row := {}               ## The `GrenadeConfig` row it was thrown with.
var _motion := Motion.new()  ## Its height and speed.
var _direction := Vector2.RIGHT  ## Across the floor.
var _fuse := 0.0             ## Seconds left until it goes off (counted from the release).
var _angle := 0.0            ## Which way the art points (rad).
var _spin := 0.0             ## Spin (rad/s).
var _resting := false        ## It has come to rest (the `rest` event was posted).
var _query: PhysicsShapeQueryParameters2D  ## Reused sweep (a circle of `radius`).


## The height, rise and speed of a grenade over time, stepped by one integrator for the node and for the plan, so the
## plan's prediction is the node's own motion. `height` above the floor, `rise` vertical speed (up), `speed` across it.
class Motion:
	var height := 0.0
	var rise := 0.0
	var speed := 0.0
	var gravity := 600.0
	var restitution := 0.35
	var friction := 520.0
	var min_hop := 40.0
	var rolling := false  ## Down for good and skidding.

	## Advance by `delta`; true when it came down and bounced. A bounce keeps `restitution` of the fall and of the speed; a
	## landing too soft for one (slower than `min_hop`, or one whose rebound the next frame's gravity would cancel) starts the
	## roll, which the floor slows by `friction`.
	func step(delta: float) -> bool:
		if rolling:
			speed = move_toward(speed, 0.0, friction * delta)
			return false
		rise -= gravity * delta
		height += rise * delta
		if height > 0.0:
			return false
		height = 0.0
		if rise < -min_hop and -rise * restitution > gravity * delta:
			rise = -rise * restitution
			speed *= restitution
			return true
		rise = 0.0
		rolling = true
		return false


## Let a grenade of `kind` go from `from` toward `to`, thrown by `by`, into `parent` (the world root).
static func spawn(grenade: StringName, from: Vector2, to: Vector2, by: Node, parent: Node) -> ThrownGrenade:
	var row := GrenadeConfig.row(grenade)
	var node := ThrownGrenade.new()
	node.name = "Thrown%s" % grenade.capitalize()
	node.kind = grenade
	node.thrower = by
	node.item = ItemRegistry.create(int(row.get("slot", -1)), 1)
	node._row = row.duplicate()
	node._fuse = float(row.get("fuse", 3.0))
	var lob := plan(row, from.distance_to(to))
	node._motion = _motion_for(row, lob)
	node._direction = (to - from).normalized() if from.distance_to(to) > 0.5 else Vector2.RIGHT
	node._angle = node._direction.angle()
	node._spin = randf_range(8.0, 14.0) * (1.0 if randf() < 0.5 else -1.0)
	parent.add_child(node)
	node.global_position = from
	return node


## The lob that brings a grenade of `row` to rest `distance` px away: `{ time, rise, gravity, speed, reach }` (the flight
## time, the launch's vertical speed, the gravity it is flown under, the speed across the floor and how far it first
## touches down). A throw aimed past what `max_range` allows first touches down at `max_range` and rolls on from there.
static func plan(row: Dictionary, distance: float) -> Dictionary:
	var cap := float(row.get("max_range", 450.0))
	var reach := cap
	if _simulate(row, cap).y > distance:
		var low := 0.0
		var high := cap
		for _i in PLAN_STEPS:
			var mid := (low + high) * 0.5
			if _simulate(row, mid).y > distance:
				high = mid
			else:
				low = mid
		reach = low
	return _flight(row, reach)


## The flight that touches down `reach` px away: the arc starts at the release height, peaks at `arc_height`
## and is back at the floor after `time`, which the speed across the floor sets (never under `min_flight_time`).
static func _flight(row: Dictionary, reach: float) -> Dictionary:
	var start := float(row.get("release_height", 50.0))
	var climb := maxf(float(row.get("arc_height", 80.0)) - start, 1.0)
	var time := maxf(reach / float(row.get("throw_speed", 500.0)), GrenadeConfig.min_flight_time)
	var rise := 2.0 * climb * (1.0 + sqrt(1.0 + start / climb)) / time
	return { "time": time, "rise": rise, "gravity": rise * rise / (2.0 * climb), "speed": reach / time, "reach": reach }


## A `Motion` for a grenade of `row` thrown on `lob`.
static func _motion_for(row: Dictionary, lob: Dictionary) -> Motion:
	var motion := Motion.new()
	motion.height = float(row.get("release_height", 50.0))
	motion.rise = lob["rise"]
	motion.speed = lob["speed"]
	motion.gravity = lob["gravity"]
	motion.restitution = float(row.get("restitution", 0.35))
	motion.friction = float(row.get("friction", 520.0))
	motion.min_hop = GrenadeConfig.min_hop_speed
	return motion


## How far (px) from the hand the flight that first touches down `reach` px out comes to rest through the bounces and the
## skid, in free air: `(first touchdown, rest)`.
static func _simulate(row: Dictionary, reach: float) -> Vector2:
	var motion := _motion_for(row, _flight(row, reach))
	var travelled := 0.0
	var touched := -1.0
	for _frame in PLAN_FRAMES:
		var bounced := motion.step(PLAN_DELTA)
		travelled += motion.speed * PLAN_DELTA
		if touched < 0.0 and (bounced or motion.rolling):
			touched = travelled
		if motion.rolling and motion.speed <= REST_SPEED:
			break
	return Vector2(touched, travelled)


func _ready() -> void:
	add_to_group(&"live_grenades")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var circle := CircleShape2D.new()
	circle.radius = radius
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = circle
	_query.collision_mask = SOLID_MASK
	_update_layer()


func _physics_process(delta: float) -> void:
	_fuse -= delta
	if _fuse <= 0.0:
		_detonate()
		return
	if _resting:
		return
	var landed := _motion.step(delta)
	_slide(_direction * _motion.speed * delta)
	if _motion.rolling:
		_spin = move_toward(_spin, 0.0, spin_friction * delta)
	_angle += _spin * delta
	_update_layer()
	if landed:
		_post(&"bounce")
	if _motion.rolling and _motion.speed <= REST_SPEED:
		_resting = true
		_spin = 0.0
		_post(&"rest")
	queue_redraw()


## Seconds until it goes off.
func fuse_left() -> float:
	return maxf(_fuse, 0.0)


## What an onlooker may know of it: `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, from the row it was thrown with (the same
## dictionary as `GrenadeItem.throw_stats()`).
func throw_stats() -> Dictionary:
	return GrenadeConfig.stats_of(kind, _row)


## Tell the world it hit the floor or a wall (`stage` &"bounce") or came to rest (&"rest"): the Audio domain voices the
## clatter, perception hears where it landed.
func _post(stage: StringName) -> void:
	EventBus.post(&"grenade", { "position": global_position, "kind": kind, "stage": stage })


## Aloft it draws over the living; down it lies beneath them, like a dropped item.
func _update_layer() -> void:
	z_index = DrawLayers.ABOVE if _motion.height > 12.0 else DrawLayers.LYING


## Move across the floor by `motion`, striking walls, solid furniture taller than it is high and the living in the way:
## it stops at the thing, bounces off with the row's `restitution` and goes on the other way.
func _slide(motion: Vector2) -> void:
	if motion.length_squared() < 0.000001:
		return
	var space := get_world_2d().direct_space_state
	var struck := _first_strike(space, motion)
	if struck.is_empty():
		global_position += motion
		return
	global_position += motion * float(struck["safe"])
	var normal: Vector2 = struck["normal"]
	_direction = _direction.bounce(normal).normalized()
	global_position += normal * 0.5
	if _motion.speed > MIN_CLATTER_SPEED:
		_post(&"bounce")
	_motion.speed *= _motion.restitution
	_spin *= -0.5


## What first stops a sweep of `motion`, as `{ safe, normal }` (how far along it is clear, and the surface's normal), or {}
## when nothing does. A piece whose `coverage` is below the grenade's height is flown over: it is skipped.
func _first_strike(space: PhysicsDirectSpaceState2D, motion: Vector2) -> Dictionary:
	var skipped: Array[RID] = []
	for _attempt in 6:
		_query.exclude = skipped
		_query.transform = Transform2D(0.0, global_position)
		_query.motion = motion
		var res := space.cast_motion(_query)
		if res[0] >= 1.0:
			return {}
		_query.transform = Transform2D(0.0, global_position + motion * res[1])
		_query.motion = Vector2.ZERO
		var info := space.get_rest_info(_query)
		if info.is_empty():
			return { "safe": res[0], "normal": -motion.normalized() }
		if _coverage_of(info["collider_id"]) <= _motion.height:
			skipped.append(info["rid"])
			continue
		return { "safe": res[0], "normal": info["normal"] }
	return {}


## The height of what object `id` is (its surface's `coverage`; a collider with none always stops a grenade).
func _coverage_of(id: int) -> float:
	var collider: Object = instance_from_id(id)
	if collider != null and collider.has_method("get_surface"):
		return float(collider.get_surface().get("coverage", UNKNOWN_COVERAGE))
	return UNKNOWN_COVERAGE


## The fuse is out: the burst (Projectile System) and this node is done.
func _detonate() -> void:
	remove_from_group(&"live_grenades")
	var source: Node = thrower if is_instance_valid(thrower) else null
	var world := get_parent()
	match kind:
		&"frag": Explosion.frag(global_position, world, source, _row)
		&"stun": Explosion.stun(global_position, world, source, _row)
	queue_free()


func _draw() -> void:
	if item == null:
		return
	var away := global_transform.basis_xform_inv(-ArtConfig.light_from.normalized()).normalized()
	item.draw_dropped(self, away * (0.5 + _motion.height * shadow_per_height), _angle,
		Color(0.0, 0.0, 0.0, ArtConfig.drop_shadow_alpha))
	item.draw_dropped(self, Vector2.ZERO, _angle, Color.WHITE)
