extends CanvasLayer

## Debug UI showing punch state and hit detection info.

var _player: CharacterBody2D
var _animator: Node2D
var _label: Label
var _hit_display_label: Label
var _last_hit_body: String = "—"
var _last_hit_hand: int = -1
var _last_hit_time: float = 0.0


func _ready() -> void:
	_player = get_parent().get_node("Player")
	_animator = _player.get_node("PlayerAnimator")

	# Create a label for debug output (bottom-right).
	_label = Label.new()
	add_child(_label)
	_label.anchor_left = 1.0
	_label.anchor_top = 1.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = -400.0
	_label.offset_top = -180.0
	_label.offset_right = -10.0
	_label.offset_bottom = -10.0
	_label.text = ""

	# Make text larger and readable.
	var font: Font = ThemeDB.fallback_font
	_label.add_theme_font_size_override("font_size", 24)

	# Create a label for hit display (top-left, below hint).
	_hit_display_label = Label.new()
	add_child(_hit_display_label)
	_hit_display_label.anchor_left = 0.0
	_hit_display_label.anchor_top = 0.0
	_hit_display_label.offset_left = 32.0
	_hit_display_label.offset_top = 60.0
	_hit_display_label.offset_right = 500.0
	_hit_display_label.offset_bottom = 120.0
	_hit_display_label.custom_minimum_size = Vector2(450, 40)
	_hit_display_label.text = ""
	_hit_display_label.add_theme_font_size_override("font_size", 22)
	_hit_display_label.add_theme_color_override("font_color", Color.YELLOW)

	# Connect to animator's punch signal.
	if _animator.has_signal("punched"):
		_animator.punched.connect(_on_punch_hit.bind())


func _process(_delta: float) -> void:
	var item_name: String = _player._items.get(_player.current_item, {}).get("name", "Unknown")
	var reach: float = _animator._current_reach
	var attack_active: bool = _animator._attack_active

	# Build debug text (bottom-right).
	var debug_lines := [
		"=== DEBUG ===",
		"Item: %d (%s)" % [_player.current_item, item_name],
		"Punch Active: %s" % ("YES" if attack_active else "NO"),
		"Reach: %.1f" % reach,
		"",
		"Last Hit:",
	]

	if _last_hit_time > 0:
		var time_ago := Time.get_ticks_msec() / 1000.0 - _last_hit_time
		debug_lines.append("  Body: %s | Hand: %d | [%.1fs ago]" % [_last_hit_body, _last_hit_hand, time_ago])
		# Clear old hits after 5 seconds.
		if time_ago > 5.0:
			_last_hit_time = 0.0
	else:
		debug_lines.append("  (none)")

	_label.text = "\n".join(debug_lines)

	# Update hit display (top-left).
	if _last_hit_time > 0:
		var time_ago := Time.get_ticks_msec() / 1000.0 - _last_hit_time
		var hand_name: String = "LEFT" if _last_hit_hand == 0 else "RIGHT"
		_hit_display_label.text = "HIT: %s (Hand: %s)" % [_last_hit_body, hand_name]
		# Clear after 3 seconds.
		if time_ago > 3.0:
			_hit_display_label.text = ""
			_last_hit_time = 0.0
	else:
		_hit_display_label.text = ""


func _on_punch_hit(hand_index: int, body: Node) -> void:
	_last_hit_body = body.name
	_last_hit_hand = hand_index
	_last_hit_time = Time.get_ticks_msec() / 1000.0
