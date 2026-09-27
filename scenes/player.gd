extends CharacterBody2D

## Placeholder top-down character: a circle moved with WASD, colliding with walls.
## Two smaller circles ("hands") sit in front of the body, aimed at the mouse.
## Pressing the punch key (F by default, via Keybinds) throws one hand forward like
## a jab, alternating left/right each press, and reports what the fist hits.

## Radius of the placeholder circle. The room's wall lines are drawn at half the
## character's *width* (i.e. half the diameter = the radius) thick.
@export var radius: float = 24.0
@export var speed: float = 300.0

## Hand appearance / placement (all in pixels, in the player's local space).
@export var hand_radius: float = 10.0     ## Size of each hand circle.
@export var hand_gap: float = 6.0         ## Gap between the body edge and a resting hand.
@export var hand_lateral: float = 14.0    ## How far each hand sits to its side of center.
@export var punch_reach: float = 28.0     ## Extra forward travel at full extension.
@export var hand_color: Color = Color(1.0, 0.85, 0.4)

## Emitted when the extended fist overlaps a body. `hand_index` is 0 (left) or 1 (right).
signal punched(hand_index: int, body: Node)

@onready var _shape: CollisionShape2D = $CollisionShape2D

## Unit vector from the player toward the mouse; drives where the hands point.
var _facing := Vector2.RIGHT
## Which hand throws the next punch: 0 = left, 1 = right.
var _next_hand := 0
## Per-hand extension, 0 (resting) .. 1 (fully punched), driven by tweens.
var _punch := [0.0, 0.0]

## Hit-detection state for the current swing.
var _fist: Area2D
var _attack_active := false   ## True only during a punch's forward thrust.
var _active_hand := 0         ## Hand the fist is tracking this swing.
var _hit_bodies := {}         ## Bodies already reported this swing (dedup).


func _ready() -> void:
	# Keep the physics circle in sync with the drawn radius.
	var circle := CircleShape2D.new()
	circle.radius = radius
	_shape.shape = circle

	# Build the fist hitbox at runtime, matching the room/body shape convention.
	_fist = Area2D.new()
	_fist.monitorable = false  # Only this area senses others, not the reverse.
	var fist_shape := CollisionShape2D.new()
	var fist_circle := CircleShape2D.new()
	fist_circle.radius = hand_radius
	fist_shape.shape = fist_circle
	_fist.add_child(fist_shape)
	add_child(_fist)


func _physics_process(_delta: float) -> void:
	# Aim the hands at the mouse. Guard the degenerate zero-length case.
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > 0.001:
		_facing = to_mouse.normalized()

	var direction := Keybinds.get_move_vector()
	velocity = direction * speed
	move_and_slide()

	if Keybinds.is_punch_just_pressed():
		_start_punch()

	# Track the fist on the punching hand and report anything it overlaps.
	_fist.position = _hand_position(_active_hand)
	if _attack_active:
		_report_hits()

	queue_redraw()  # Facing and hand positions change every frame.


## Local-space center of a hand (0 = left, 1 = right), including its punch extension.
func _hand_position(hand: int) -> Vector2:
	var perp := _facing.orthogonal()
	var side := -1.0 if hand == 0 else 1.0
	var rest := _facing * (radius + hand_radius + hand_gap) + perp * (hand_lateral * side)
	return rest + _facing * (punch_reach * _punch[hand])


## Throw the next hand forward, then retract it. Rapid presses alternate hands.
func _start_punch() -> void:
	var hand := _next_hand
	_next_hand = 1 - _next_hand
	if _punch[hand] > 0.0:
		return  # That hand is still mid-swing; skip.

	_active_hand = hand
	_attack_active = true
	_hit_bodies.clear()

	var tween := create_tween()
	tween.tween_method(_set_punch.bind(hand), 0.0, 1.0, 0.07)  # Extend.
	tween.tween_callback(func() -> void: _attack_active = false)
	tween.tween_method(_set_punch.bind(hand), 1.0, 0.0, 0.11)  # Retract.


## Tween setter for a single hand's extension.
func _set_punch(value: float, hand: int) -> void:
	_punch[hand] = value
	queue_redraw()


## Report bodies the fist currently overlaps (once each per swing), ignoring self.
func _report_hits() -> void:
	for body in _fist.get_overlapping_bodies():
		if body == self or _hit_bodies.has(body):
			continue
		_hit_bodies[body] = true
		print("Punch (hand %d) hit: %s" % [_active_hand, body.name])
		punched.emit(_active_hand, body)


func _draw() -> void:
	# Placeholder circle (filled) with a thin outline so facing is obvious.
	draw_circle(Vector2.ZERO, radius, Color(0.32549, 0.65098, 1.0))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color.WHITE, 2.0, true)

	# Hands: filled circles with a thin outline, in front toward the mouse.
	for hand in [0, 1]:
		var p := _hand_position(hand)
		draw_circle(p, hand_radius, hand_color)
		draw_arc(p, hand_radius, 0.0, TAU, 24, Color.WHITE, 1.5, true)
