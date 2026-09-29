class_name Knockback extends Node

## Reusable knockback component. Add it as a child of a shoveable PhysicsBody2D. It owns the
## shove velocity/spin and, each physics frame, sweeps its parent body along that velocity —
## stopping at (and transferring momentum into) whatever it hits — then damps back to rest.
## The parent forwards `apply_impulse()` / `get_mass()` here, so any pusher uses one contract
## and never needs to know this component exists. All tuning is PhysicsConfig.impact_*.

## The body's mass. A shove's impulse is divided by this, so heavier bodies move less.
## Set by the owner from its catalog definition.
var mass: float = 10.0

## Current shove velocity (px/s) and spin (rad/s), integrated in _physics_process.
var velocity := Vector2.ZERO
var angular := 0.0

var _body: PhysicsBody2D  ## The shoved body (parent).
var _origin: Vector2      ## Spawn position, for the optional displacement cap.


func _ready() -> void:
	_body = get_parent()
	_origin = _body.position


## Mass floored so featherweight decor still reacts.
func effective_mass() -> float:
	return maxf(mass, 0.5)


## Add a shove. Divided by mass; a little spin is mixed in for juice.
func apply_impulse(impulse: Vector2) -> void:
	var m := effective_mass()
	velocity += impulse / m
	angular += (impulse.length() / m) * 0.002 * (1.0 if randf() > 0.5 else -1.0)


func _physics_process(delta: float) -> void:
	if velocity.length_squared() < 1.0 and absf(angular) < 0.01:
		return

	var motion := velocity * delta
	if motion.length_squared() > 0.0:
		_move_and_collide(motion)

	_body.rotation += angular * delta
	var offset := _body.position - _origin
	if PhysicsConfig.impact_max_slide > 0.0 and offset.length() > PhysicsConfig.impact_max_slide:
		_body.position = _origin + offset.normalized() * PhysicsConfig.impact_max_slide
		velocity = Vector2.ZERO
	velocity = velocity.move_toward(Vector2.ZERO, PhysicsConfig.impact_friction * delta)
	angular = move_toward(angular, 0.0, PhysicsConfig.impact_friction * 0.01 * delta)


## Advance `motion`, stopping at (and shoving) whatever it hits instead of tunneling.
func _move_and_collide(motion: Vector2) -> void:
	var collision := KinematicCollision2D.new()
	if not _body.test_move(_body.global_transform, motion, collision):
		_body.position += motion
		return

	# Snap to the last safe point so this body never overlaps what it hit.
	_body.position += collision.get_travel()

	var collider: Object = collision.get_collider()
	if collider != null and collider.has_method("apply_impulse"):
		var normal := collision.get_normal()
		# Speed we were closing on the obstacle along the contact normal (normal points
		# back toward us, so "into it" is -normal).
		var closing_speed := velocity.dot(-normal)
		if closing_speed > 0.0:
			var transfer := -normal * closing_speed * effective_mass() * PhysicsConfig.impact_transfer_scale
			collider.apply_impulse(transfer)

	# Stop dead at contact (walls have no apply_impulse and are simply immovable).
	velocity = Vector2.ZERO
