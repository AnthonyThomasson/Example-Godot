extends RigidBody2D

## Door CONTROL layer (Objects domain). A one-directional swinging door that BLOCKS movement and
## line-of-sight while closed, is hittable + destructible, and is operated by the player (E + wheel,
## via player_controller) or opened by an NPC (goal_controller). Built by DoorFactory; the leaf is
## drawn by door_visuals.gd.
##
## It is a FROZEN RigidBody2D on purpose: frozen, it blocks characters and is hit by projectiles
## (they query bodies on layer 1 for get_surface/take_hit), yet the nav bake ignores it — NavBuilder
## parses only static (StaticBody2D) colliders and its furniture hole/avoider passes skip frozen
## bodies. So the doorway stays WALKABLE in the navmesh and an NPC paths up to the door and opens it,
## instead of rerouting around a sealed doorway. The leaf swings kinematically (we set `rotation`),
## so freeze_mode is KINEMATIC to push characters correctly as it sweeps.

## Radians/sec the leaf eases toward its target angle when swung fully (player tap / AI open). The
## wheel bypasses this and sets the angle directly for gradual control.
const SWING_SPEED := 9.0
## open_fraction at/above which the doorway counts as clear (not blocking) — read by the AI.
const OPEN_ENOUGH := 0.85

@export var leaf_length: float = 70.0      ## Doorway width; length of the swinging leaf.
@export var wall_thickness: float = 24.0   ## Leaf thickness (matches the wall it sits in).
@export var closed_dir: Vector2 = Vector2.RIGHT  ## Unit dir the SHUT leaf points, along the wall.
@export var swing_sign: float = 1.0        ## Which way it opens (+1/-1): the single allowed direction.
@export var max_angle: float = PI / 2.0    ## How far open (radians) at open_fraction 1.
@export var color: Color = Color(0.45, 0.30, 0.18)  ## Leaf fill color.
@export var destroy_damage: float = 60.0   ## Accumulated damage that destroys (frees) the door.

## 0 = closed (fills the doorway gap), 1 = fully open. Read by door_visuals.gd.
var open_fraction: float = 0.0
## Angle (rad) the leaf eases toward; swing()/open() set it, nudge() sets it to the live fraction.
var _target_fraction: float = 0.0
## Damage dents; drives the destroy check. Read by the visuals.
var _deformable: Deformable


func _ready() -> void:
	# Frozen kinematic body: we drive the swing by setting `rotation`; it blocks but never falls or
	# is shoved, and (being frozen) is invisible to the nav bake.
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	collision_layer = 1
	collision_mask = 1
	add_to_group("doors")

	_deformable = Deformable.new()
	add_child(_deformable)
	_deformable.changed.connect(_on_deformable_changed)

	_build_collider()
	_apply_angle()


func _physics_process(delta: float) -> void:
	# Ease toward the swing target (tap/AI open); a wheel nudge keeps target == fraction so it holds.
	if not is_equal_approx(open_fraction, _target_fraction):
		open_fraction = move_toward(open_fraction, _target_fraction, SWING_SPEED * delta)
		_apply_angle()


# --- Operate API (player_controller + the AI) ------------------------------------------

## Toggle: swing fully open if closed-ish, fully shut if open-ish. The player's E tap.
func swing() -> void:
	_target_fraction = 0.0 if _target_fraction >= 0.5 else 1.0


## Nudge the leaf by `delta` (the mouse wheel): direct, gradual control, clamped 0..1.
func nudge(delta: float) -> void:
	open_fraction = clampf(open_fraction + delta, 0.0, 1.0)
	_target_fraction = open_fraction
	_apply_angle()


## Set the open amount directly (0..1).
func set_open_fraction(f: float) -> void:
	open_fraction = clampf(f, 0.0, 1.0)
	_target_fraction = open_fraction
	_apply_angle()


## Force the door fully open — the NPC's call when a closed door blocks its path.
func open() -> void:
	_target_fraction = 1.0


## Whether the doorway is clear enough to pass (read by the AI before deciding to open).
func is_open() -> bool:
	return open_fraction >= OPEN_ENOUGH


## Distance from a world point to the door leaf (the hinge->tip segment), so "near the door" is
## judged against the whole leaf, not just the hinge at one jamb. Used by the player and the AI.
func operate_distance(from: Vector2) -> float:
	var hinge := global_position
	var tip := hinge + Vector2.RIGHT.rotated(rotation) * leaf_length
	return Geometry2D.get_closest_point_to_segment(from, hinge, tip).distance_to(from)


# --- Hittable contract (shot by projectiles; destructible) -----------------------------

## The door's ballistic surface: solid cover, wood debris. Mirrors the wall/furniture contract.
func get_surface() -> Dictionary:
	return { "coverage": 80.0, "penetration": 35.0, "material": "wood", "color": color }


## Take a hit: record the dent and spray debris, then destroy the door once it has taken enough
## damage (clearing the doorway). Unlike furniture it is not knocked back — it is hinged and frozen.
func take_hit(hit: HitInfo) -> void:
	_deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())
	if _deformable.damage_total >= destroy_damage:
		queue_free()


func _on_deformable_changed() -> void:
	if _visuals():
		_visuals().queue_redraw()


# --- Geometry (built in code, runtime-shape convention) --------------------------------

## Orient the leaf for the current open_fraction: shut it points along `closed_dir` (filling the
## gap); opening rotates it up to `max_angle` in the one allowed direction.
func _apply_angle() -> void:
	rotation = closed_dir.angle() + swing_sign * open_fraction * max_angle
	var v := _visuals()
	if v:
		v.queue_redraw()


## One rectangle collider spanning the leaf, from the hinge (local origin) out along +X.
func _build_collider() -> void:
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(leaf_length, wall_thickness)
	col.shape = rect
	col.position = Vector2(leaf_length * 0.5, 0.0)
	add_child(col)


func _visuals() -> Node2D:
	return get_node_or_null("DoorVisuals") as Node2D
