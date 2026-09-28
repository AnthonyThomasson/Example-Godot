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

## Knockback velocity from objects shoved into the player; decays each frame (see
## push_knockback_friction). Added on top of input-driven movement.
var _knockback := Vector2.ZERO
## Speed multiplier from pushing objects last frame (1.0 = unencumbered). Applied to the
## next frame's movement so pushing heavy furniture slows the player.
var _push_slow := 1.0

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
	_items[3] = { name="Pistol", reach=32.0, has_attack=true, punch_hand=1, weapon_hand=1, fires=true, damage=15.0 }


func _physics_process(delta: float) -> void:
	# Aim toward the mouse. Guard the degenerate zero-length case.
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 0.001:
		facing = to_mouse.normalized()
	# A parent's _physics_process runs before its children's, so the animator sees
	# this fresh facing on the same frame.
	_animator.facing = facing

	velocity = Keybinds.get_move_vector() * speed * _push_slow + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector2.ZERO, Config.push_knockback_friction * delta)
	_push_slow = _apply_pushes()

	# Check for item selection (1-9 keys).
	var selected := Keybinds.get_selected_item()
	if selected > 0 and selected in _items:
		current_item = selected

	# Forward the current item to the animator (so it knows which reach to use, etc.).
	_animator.current_item = current_item

	# Only trigger attacks if the current item has an attack.
	if Keybinds.is_punch_just_pressed() and _items[current_item].get("has_attack", false):
		_animator.try_punch()

	# Guns fire a projectile on left-click (the pistol keeps its F melee jab too).
	if Keybinds.is_fire_just_pressed() and _items[current_item].get("fires", false):
		_animator.try_fire()


## Shove every pushable object the body slid against this frame (walls have no
## apply_impact and are skipped), and return the speed multiplier for next frame:
## heavier objects slow the player more, floored so movement never fully locks.
func _apply_pushes() -> float:
	var input_strength := Keybinds.get_move_vector().length()
	if input_strength <= 0.0:
		return 1.0

	var heaviest := 0.0
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null or not collider.has_method("apply_impact"):
			continue
		# The normal points back toward the player, so "into the object" is -normal.
		collider.apply_impact(-collision.get_normal() * Config.push_impulse * input_strength)
		heaviest = maxf(heaviest, float(collider.get("weight")))

	if heaviest <= 0.0:
		return 1.0
	return clampf(1.0 - heaviest * Config.push_slow_per_weight, Config.push_slow_min, 1.0)


## Receive knockback from an object shoved into the player (mirrors the object-to-object
## transfer in environment_object.gd). Divided by player_mass so light hits barely register.
func apply_impact(impulse: Vector2) -> void:
	_knockback += impulse / maxf(Config.player_mass, 0.5)
