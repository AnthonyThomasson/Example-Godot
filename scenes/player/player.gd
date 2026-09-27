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

## Current equipped item (1-indexed: 1=unarmed, 2=pistol, etc.). Public so visuals
## and animator can read it.
var current_item := 1

## Item definitions: dict of item_num -> {name, reach, ...}. Defines the item's
## properties (attack reach, visuals, etc.). Initialized in _ready().
var _items := {}

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _animator := $PlayerAnimator


func _ready() -> void:
	# Physics is control's job: keep the body's collision circle in sync with radius.
	var circle := CircleShape2D.new()
	circle.radius = radius
	_shape.shape = circle

	# Initialize item definitions.
	_items[1] = { name="Unarmed", reach=28.0, has_attack=false }
	_items[2] = { name="Fists", reach=28.0, has_attack=true, punch_hand=[0, 1] }
	_items[3] = { name="Pistol", reach=32.0, has_attack=true, punch_hand=1, weapon_hand=1 }


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

	# Check for item selection (1-9 keys).
	var selected := Keybinds.get_selected_item()
	if selected > 0 and selected in _items:
		current_item = selected

	# Forward the current item to the animator (so it knows which reach to use, etc.).
	_animator.current_item = current_item

	# Only trigger attacks if the current item has an attack.
	if Keybinds.is_punch_just_pressed() and _items[current_item].get("has_attack", false):
		_animator.try_punch()
