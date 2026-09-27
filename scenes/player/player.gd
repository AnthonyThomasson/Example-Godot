extends CharacterBody2D

## Player CONTROL layer. Reads input through the Keybinds autoload, moves the body,
## and tracks the mouse-facing direction. Drawing lives in player_visuals.gd and the
## punch animation / hit detection in player_animator.gd; this node orchestrates them.

## Radius of the placeholder circle. The room's wall lines are drawn at half the
## character's *width* (i.e. half the diameter = the radius) thick.
@export var radius: float = 24.0
@export var speed: float = 300.0

## Unit vector from the player toward the mouse; read by the animator and visuals.
var facing := Vector2.RIGHT

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _animator := $PlayerAnimator


func _ready() -> void:
	# Physics is control's job: keep the body's collision circle in sync with radius.
	var circle := CircleShape2D.new()
	circle.radius = radius
	_shape.shape = circle


func _physics_process(_delta: float) -> void:
	# Aim toward the mouse. Guard the degenerate zero-length case.
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 0.001:
		facing = to_mouse.normalized()
	# A parent's _physics_process runs before its children's, so the animator sees
	# this fresh facing on the same frame.
	_animator.facing = facing

	velocity = Keybinds.get_move_vector() * speed
	move_and_slide()

	if Keybinds.is_punch_just_pressed():
		_animator.try_punch()
