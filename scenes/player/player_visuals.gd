extends Node2D

## Player DRAW layer. Renders the body circle and the two hands. Reads the body
## radius from the control node (player.gd) and the hand positions / size from the
## animator (player_animator.gd), so this file owns appearance only.

@export var body_color: Color = Color(0.32549, 0.65098, 1.0)
@export var hand_color: Color = Color(1.0, 0.85, 0.4)

@onready var _control := get_parent()              ## Player — body radius.
@onready var _animator := $"../PlayerAnimator"     ## Sibling — hand positions / size.


func _process(_delta: float) -> void:
	# Facing and hand positions change every frame; redraw at the same cadence.
	queue_redraw()


func _draw() -> void:
	# Placeholder body: filled circle with a thin outline so facing is obvious.
	var r: float = _control.radius
	draw_circle(Vector2.ZERO, r, body_color)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color.WHITE, 2.0, true)

	# Hands: filled circles with a thin outline, in front toward the mouse.
	for hand in [0, 1]:
		var p: Vector2 = _animator.hand_position(hand)
		draw_circle(p, _animator.hand_radius, hand_color)
		draw_arc(p, _animator.hand_radius, 0.0, TAU, 24, Color.WHITE, 1.5, true)
