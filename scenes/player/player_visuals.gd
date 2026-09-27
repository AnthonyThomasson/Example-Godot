extends Node2D

## Player DRAW layer. Renders the body circle, hands, and weapons. Reads the body
## radius from the control node (player.gd), hand positions from the animator
## (player_animator.gd), and the equipped item from control. Owns appearance only.

@export var body_color: Color = Color(0.32549, 0.65098, 1.0)
@export var hand_color: Color = Color(1.0, 0.85, 0.4)
@export var pistol_color: Color = Color(0.3, 0.3, 0.3)

@onready var _control := get_parent()              ## Player — body radius, current_item.
@onready var _animator := $"../PlayerAnimator"     ## Sibling — hand positions / size.

var _current_item := 1  ## Track the equipped item to decide what to draw.


func _process(_delta: float) -> void:
	# Track the current item and redraw every frame (facing/items change continuously).
	_current_item = _control.current_item
	queue_redraw()


func _draw() -> void:
	# Placeholder body: filled circle with a thin outline so facing is obvious.
	var r: float = _control.radius
	draw_circle(Vector2.ZERO, r, body_color)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color.WHITE, 2.0, true)

	# Draw hands based on the equipped item's weapon_hand property.
	var item_def := _control._items.get(_current_item, {})
	var weapon_hand: int = item_def.get("weapon_hand", -1)

	if weapon_hand >= 0:
		# Item has a weapon: draw only the weapon-holding hand, then the weapon.
		_draw_hand(weapon_hand)
		_draw_weapon_for_item(_current_item, weapon_hand)
	else:
		# Unarmed: draw both hands.
		for hand in [0, 1]:
			_draw_hand(hand)


## Draw a single hand circle at the given index (0=left, 1=right).
func _draw_hand(hand: int) -> void:
	var p: Vector2 = _animator.hand_position(hand)
	draw_circle(p, _animator.hand_radius, hand_color)
	draw_arc(p, _animator.hand_radius, 0.0, TAU, 24, Color.WHITE, 1.5, true)


## Draw the weapon for a given item at the specified hand position.
func _draw_weapon_for_item(item: int, hand: int) -> void:
	if item == 2:  # Pistol
		_draw_pistol(_animator.hand_position(hand))
	# Add more item-specific weapon drawing here as needed.


## Draw a simple pistol shape at the given position, rotated toward facing.
func _draw_pistol(hand_pos: Vector2) -> void:
	# Pistol: a barrel line and a grip circle, aligned with the facing direction.
	var barrel_len: float = 16.0
	var barrel_width: float = 4.0
	var barrel_offset: float = 8.0  # How far forward from the hand.

	# Barrel: a thick line from hand forward.
	var barrel_start: Vector2 = hand_pos + _animator.facing * barrel_offset
	var barrel_end: Vector2 = barrel_start + _animator.facing * barrel_len
	draw_line(barrel_start, barrel_end, pistol_color, barrel_width)

	# Grip: a small circle at the hand position.
	var grip_radius: float = 5.0
	draw_circle(hand_pos, grip_radius, pistol_color)
	draw_arc(hand_pos, grip_radius, 0.0, TAU, 12, Color.WHITE, 1.0, true)
