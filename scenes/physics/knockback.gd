class_name Knockback extends Node

## Reusable physics adapter for a shoveable RigidBody2D. Add it as a child of the body. It
## configures the body for top-down play (no gravity, mass, damping, sleep, origin-pinned
## center of mass) and is the home of the "pushable" contract: the owner forwards
## `apply_impulse()` / `get_mass()` here, so any pusher uses one contract and never touches
## the body directly. The engine integrates motion, collisions, pivoting and settling; this
## component only feeds it impulses and hands momentum to the kinematic character on contact.
## All tuning is PhysicsConfig.body_* / impact_*.

## Sentinel for `apply_impulse`'s optional contact point (a central shove when omitted).
const _NO_POINT := Vector2(INF, INF)

## The body's mass. Set by the owner from its catalog definition; applied to the RigidBody2D.
var mass: float = 10.0

var _body: RigidBody2D  ## The shoved body (parent).


## Configure the parent RigidBody2D for top-down physics and wire contact reporting.
func _ready() -> void:
	_body = get_parent()
	_body.mass = effective_mass()
	_body.gravity_scale = 0.0
	_body.linear_damp = PhysicsConfig.body_linear_damp
	_body.angular_damp = PhysicsConfig.body_angular_damp
	_body.can_sleep = true
	_body.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY if PhysicsConfig.body_continuous_cd else RigidBody2D.CCD_MODE_DISABLED
	# Pin the center of mass to the origin so a carved object still rotates about its
	# origin-centered drawn silhouette instead of a shifted mass center.
	_body.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	_body.center_of_mass = Vector2.ZERO
	# Report contacts so momentum can be handed to the kinematic character (below).
	_body.contact_monitor = true
	_body.max_contacts_reported = 4
	_body.body_entered.connect(_on_body_entered)


## Mass floored so featherweight decor still reacts.
func effective_mass() -> float:
	return maxf(mass, 0.5)


## Apply a shove. With no contact point it is a central impulse; given a world contact point
## it is applied off-center so the body spins/pivots (a bullet or punch landing off-center).
func apply_impulse(impulse: Vector2, at_world: Vector2 = _NO_POINT) -> void:
	if at_world == _NO_POINT:
		_body.apply_central_impulse(impulse)
	else:
		_body.apply_impulse(impulse, at_world - _body.global_position)


## Hand momentum to a non-rigid pushable we collide with (the kinematic character — the
## solver already resolves rigid-vs-rigid and rigid-vs-wall on its own). The struck body
## takes our travel momentum scaled down so cascades lose energy and settle.
func _on_body_entered(body: Node) -> void:
	if body is RigidBody2D or not body.has_method("apply_impulse"):
		return
	var transfer := _body.linear_velocity * effective_mass() * PhysicsConfig.impact_transfer_scale
	if transfer.length_squared() > 0.0:
		body.apply_impulse(transfer)
