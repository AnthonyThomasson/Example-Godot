extends CanvasLayer

## Debug UI showing the held item, attack state and last-hit info. Talks to the character
## only through its public API + signals (hit_landed / current_item / is_attacking), never
## its internals — so it stays a General-domain observer.

## The character to observe.
@export var character_path: NodePath = ^"../Player"
var _character: Node
var _label: Label                    ## Bottom-right stats panel.
var _hit_display_label: Label        ## Top-left last-hit banner.
var _last_hit_body: String = "—"     ## Name of the last body hit.
var _last_hit_hand: int = -1         ## Hand of the last hit (−1 = a shot).
var _last_hit_time: float = 0.0      ## When the last hit landed (seconds).
var _last_hit_damage: float = -1.0   ## Damage dealt; < 0 means "no damage" (e.g. a punch).


func _ready() -> void:
	_character = get_node(character_path)

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

	# One unified hit feed: melee (hand 0/1, damage < 0) and shots (hand -1, damage ≥ 0).
	if _character.has_signal("hit_landed"):
		_character.hit_landed.connect(_on_hit_landed)


func _process(_delta: float) -> void:
	var item: Item = _character.current_item()
	var item_name: String = item.display_name if item else "Unknown"
	var reach: float = item.reach if item else 0.0
	var attack_active: bool = _character.is_attacking()

	# Build debug text (bottom-right).
	var debug_lines := [
		"=== DEBUG ===",
		"Item: %d (%s)" % [_character.current_slot(), item_name],
		"Punch Active: %s" % ("YES" if attack_active else "NO"),
		"Reach: %.1f" % reach,
		"",
		"Last Hit:",
	]

	if _last_hit_time > 0:
		var time_ago := Time.get_ticks_msec() / 1000.0 - _last_hit_time
		var dmg_seg := "" if _last_hit_damage < 0.0 else " | Dmg: %.0f" % _last_hit_damage
		debug_lines.append("  Body: %s | Hand: %d%s | [%.1fs ago]" % [_last_hit_body, _last_hit_hand, dmg_seg, time_ago])
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
		var dmg_seg := "" if _last_hit_damage < 0.0 else " — %.0f dmg" % _last_hit_damage
		_hit_display_label.text = "HIT: %s (Hand: %s)%s" % [_last_hit_body, hand_name, dmg_seg]
		# Clear after 3 seconds.
		if time_ago > 3.0:
			_hit_display_label.text = ""
			_last_hit_time = 0.0
	else:
		_hit_display_label.text = ""


## Record the latest hit for display.
func _on_hit_landed(body: Node, damage: float, hand: int) -> void:
	_last_hit_body = body.name
	_last_hit_hand = hand         # 0/1 for melee, -1 for a gunshot.
	_last_hit_damage = damage     # < 0 for a melee punch (no damage value).
	_last_hit_time = Time.get_ticks_msec() / 1000.0
