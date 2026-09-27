extends Node2D

## Player ANIMATE layer. Owns the hand geometry, the punch animation (a tween per
## swing, alternating hands), and the fist hitbox + hit detection. Control
## (player.gd) sets `facing` and calls `try_punch()`; visuals (player_visuals.gd)
## reads `hand_position()` / `hand_radius` to draw the hands.

## Hand geometry (all in pixels, in the player's local space).
@export var hand_radius: float = 10.0     ## Size of each hand circle.
@export var hand_gap: float = 6.0         ## Gap between the body edge and a resting hand.
@export var hand_lateral: float = 14.0    ## How far each hand sits to its side of center.
@export var punch_reach: float = 28.0     ## Extra forward travel at full extension.

## Emitted when the extended fist overlaps a body. `hand_index` is 0 (left) or 1 (right).
signal punched(hand_index: int, body: Node)

## Facing unit vector, set by the control node each frame.
var facing := Vector2.RIGHT
## Current item, set by the control node each frame (determines reach, etc.).
var current_item := 1
## Which hand throws the next punch: 0 = left, 1 = right.
var _next_hand := 0
## Per-hand extension, 0 (resting) .. 1 (fully punched), driven by tweens.
var _punch := [0.0, 0.0]
## Current punch reach (from the item's reach property), updated in _physics_process.
var _current_reach := 28.0

## Hit-detection state for the current swing.
var _fist: Area2D
var _attack_active := false   ## True for the whole swing (extend + retract); gates hit polling.
var _active_hand := 0         ## Hand the fist is tracking this swing.
var _hit_bodies := {}         ## Bodies already reported this swing (dedup).

@onready var _control := get_parent()  ## Player (CharacterBody2D) — source of body radius.


func _ready() -> void:
	# Build the fist hitbox at runtime, matching the room/body shape convention.
	_fist = Area2D.new()
	# monitoring = true (default) is what lets get_overlapping_bodies() see the
	# walls/furniture. Do NOT set monitorable = false here: in this Godot build that
	# also suppresses this area's own get_overlapping_bodies() results, so the fist
	# would detect nothing. Nothing else monitors the fist, so leaving it monitorable
	# is harmless.
	var fist_shape := CollisionShape2D.new()
	var fist_circle := CircleShape2D.new()
	fist_circle.radius = hand_radius
	fist_shape.shape = fist_circle
	_fist.add_child(fist_shape)
	add_child(_fist)


func _physics_process(_delta: float) -> void:
	# Update the current reach based on the equipped item.
	_current_reach = _control._items[current_item].get("reach", 28.0)

	# Track the fist on the punching hand and report anything it overlaps.
	_fist.position = hand_position(_active_hand)
	if _attack_active:
		_report_hits()


## Local-space center of a hand (0 = left, 1 = right), including its punch extension.
func hand_position(hand: int) -> Vector2:
	var body_radius: float = _control.radius
	var perp := facing.orthogonal()
	var side := -1.0 if hand == 0 else 1.0
	var rest := facing * (body_radius + hand_radius + hand_gap) + perp * (hand_lateral * side)
	return rest + facing * (_current_reach * _punch[hand])


## Throw the next hand forward, then retract it. Punch behavior depends on item's punch_hand property.
func try_punch() -> void:
	var punch_hand = _control._items[current_item].get("punch_hand", null)
	var hand: int

	if punch_hand is Array:
		# Alternating hands (fists): use _next_hand and toggle for next call.
		hand = _next_hand
		_next_hand = 1 - _next_hand
	elif punch_hand is int:
		# Single hand (pistol): always use the specified hand, no alternation.
		hand = punch_hand
	else:
		# No punching defined for this item.
		return

	if _punch[hand] > 0.0:
		return  # That hand is still mid-swing; skip.

	_active_hand = hand
	_attack_active = true
	_hit_bodies.clear()

	# Run on the physics step so _punch / _attack_active stay in sync with the
	# _report_hits() poll in _physics_process.
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(_set_punch.bind(hand), 0.0, 1.0, 0.07)  # Extend.
	tween.tween_method(_set_punch.bind(hand), 1.0, 0.0, 0.11)  # Retract.
	# Stay active across the whole swing: the fist reaches the target at full
	# extension, and get_overlapping_bodies() lags a physics frame, so a window that
	# closed at the apex would miss the hit. Per-swing dedup keeps it to one report.
	tween.tween_callback(func() -> void: _attack_active = false)


## Tween setter for a single hand's extension.
func _set_punch(value: float, hand: int) -> void:
	_punch[hand] = value


## Report bodies the fist currently overlaps (once each per swing), ignoring self.
func _report_hits() -> void:
	for body in _fist.get_overlapping_bodies():
		if body == _control or _hit_bodies.has(body):
			continue
		_hit_bodies[body] = true
		print("Punch (hand %d) hit: %s" % [_active_hand, body.name])
		punched.emit(_active_hand, body)
