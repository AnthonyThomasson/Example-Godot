extends CanvasLayer

## UI domain, pre-game setup window: a modal shown before the match starts so a human can choose
## the run's parameters — whether there is a human player, and how many defenders and invaders spawn —
## then hands them back to Main, which builds the world with them. Built entirely in code (no
## scene-side layout), like the other UI HUDs.
##
## Main opens it on a fresh launch and spawns the world only once the player presses Start; scripted
## restarts (the dev command server) set an Engine `skip_setup` meta and bypass it, so the headless
## match harness is unaffected. A decoupled piece: it knows nothing of the domains, only the parameter
## dict it emits.

## Emitted when the player presses Start, carrying the chosen parameters:
## `{ has_player: bool, seed: int, defenders: int, invaders: int,
##    show_agent_labels: bool, show_agent_paths: bool, show_vision: bool, show_tactics: bool,
##    show_room_zones: bool, show_nav_holes: bool }`.
## Main applies these and builds the world.
signal start_requested(config: Dictionary)

const _MAX_COUNT := 8  ## Upper bound per side in the spinboxes; spawn spread handles any count in range.

var _player_check: CheckBox         ## Checked = a human player; unchecked = the 2-AI spectator contest.
var _seed_edit: LineEdit            ## The level seed; blank/0 = a fresh random seed each run.
var _defender_spin: SpinBox         ## How many defenders to drop into the house.
var _invader_spin: SpinBox          ## How many invaders to spawn outside the house.
var _agent_labels_check: CheckBox   ## Checked = draw the floating action-status label above each NPC.
var _agent_paths_check: CheckBox    ## Checked = draw the NPC's live navigation path in the world.
var _vision_check: CheckBox         ## Checked = draw each NPC's line-of-sight / awareness overlay.
var _tactics_check: CheckBox        ## Checked = draw each NPC's tactical navigation-zone overlay.
var _room_zones_check: CheckBox     ## Checked = draw each NPC's tactical room-zone overlay.
var _nav_holes_check: CheckBox      ## Checked = draw the navmesh's furniture holes.
var _start_button: Button           ## Disabled on press, so holding the start can't be triggered twice.
var _status: Label                  ## Status line Main shows while it holds the start (hidden when blank).


## Build the window seeded from `defaults` (`{ has_player, seed, defenders, invaders,
## show_agent_labels, show_agent_paths, show_vision, show_tactics }`) and show it. Called by Main
## before the world is spawned.
func open(defaults: Dictionary) -> void:
	_build_ui(defaults)


# --- UI construction (built in code like the other UI HUDs; no scene-side layout) ----------

## Lay out the dimmer, the centred panel and its controls, seeded from `defaults`.
func _build_ui(defaults: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow any clicks meant for the (unbuilt) world
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)

	var title := Label.new()
	title.text = "MATCH SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	_player_check = CheckBox.new()
	_player_check.text = "Human player"
	_player_check.button_pressed = bool(defaults.get("has_player", false))
	_player_check.add_theme_font_size_override("font_size", 30)
	box.add_child(_player_check)

	_seed_edit = _seed_row(box, int(defaults.get("seed", 0)))

	_defender_spin = _spin_row(box, "Defenders", int(defaults.get("defenders", 1)))
	_invader_spin = _spin_row(box, "Invaders", int(defaults.get("invaders", 1)))

	var sep := Label.new()
	sep.text = "Debug overlays"
	sep.add_theme_font_size_override("font_size", 28)
	sep.modulate = Color(1, 1, 1, 0.5)
	box.add_child(sep)

	_agent_labels_check = CheckBox.new()
	_agent_labels_check.text = "Agent labels"
	_agent_labels_check.button_pressed = bool(defaults.get("show_agent_labels", true))
	_agent_labels_check.add_theme_font_size_override("font_size", 30)
	box.add_child(_agent_labels_check)

	_agent_paths_check = CheckBox.new()
	_agent_paths_check.text = "Agent paths"
	_agent_paths_check.button_pressed = bool(defaults.get("show_agent_paths", true))
	_agent_paths_check.add_theme_font_size_override("font_size", 30)
	box.add_child(_agent_paths_check)

	_vision_check = CheckBox.new()
	_vision_check.text = "Vision cones"
	_vision_check.button_pressed = bool(defaults.get("show_vision", true))
	_vision_check.add_theme_font_size_override("font_size", 30)
	box.add_child(_vision_check)

	_tactics_check = CheckBox.new()
	_tactics_check.text = "Tactics zones"
	_tactics_check.button_pressed = bool(defaults.get("show_tactics", false))
	_tactics_check.add_theme_font_size_override("font_size", 30)
	box.add_child(_tactics_check)

	_room_zones_check = CheckBox.new()
	_room_zones_check.text = "Room zones"
	_room_zones_check.button_pressed = bool(defaults.get("show_room_zones", false))
	_room_zones_check.add_theme_font_size_override("font_size", 30)
	box.add_child(_room_zones_check)

	_nav_holes_check = CheckBox.new()
	_nav_holes_check.text = "Furniture holes"
	_nav_holes_check.button_pressed = bool(defaults.get("show_nav_holes", false))
	_nav_holes_check.add_theme_font_size_override("font_size", 30)
	box.add_child(_nav_holes_check)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 24)
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.visible = false
	box.add_child(_status)

	_start_button = Button.new()
	_start_button.text = "Start"
	_start_button.add_theme_font_size_override("font_size", 32)
	_start_button.pressed.connect(_on_start)
	box.add_child(_start_button)


## A labelled seed row (label + LineEdit), added to `parent`; returns the LineEdit so the caller can
## read it on Start. Prefilled with `value` unless it is 0, which shows as blank (= random).
func _seed_row(parent: VBoxContainer, value: int) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "Seed"
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_font_size_override("font_size", 30)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = "random"
	edit.text = "" if value == 0 else str(value)
	edit.custom_minimum_size = Vector2(200, 0)
	edit.add_theme_font_size_override("font_size", 30)
	row.add_child(edit)
	parent.add_child(row)
	return edit


## A labelled count row (label + SpinBox clamped to `0.._MAX_COUNT`), added to `parent`; returns the
## SpinBox so the caller can read its value on Start.
func _spin_row(parent: VBoxContainer, label_text: String, value: int) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_font_size_override("font_size", 30)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = _MAX_COUNT
	spin.step = 1
	spin.value = clampi(value, 0, _MAX_COUNT)
	spin.custom_minimum_size = Vector2(140, 0)
	spin.add_theme_font_size_override("font_size", 30)
	row.add_child(spin)
	parent.add_child(row)
	return spin


## Show a status line in the window, or hide it again when `text` is blank. Main uses it while it
## holds the start — e.g. waiting for the decision server — so the pause is never silent.
func set_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_status.visible = text != ""


## Gather the chosen parameters and hand them to Main. Main applies them, frees this window and builds
## the world. Start is disabled on the way out: Main may hold the start open for a moment (waiting on
## the decision server), and a second press would build the world twice.
func _on_start() -> void:
	if _start_button != null:
		_start_button.disabled = true
	start_requested.emit({
		"has_player": _player_check.button_pressed,
		"seed": _seed_edit.text.strip_edges().to_int(),
		"defenders": int(_defender_spin.value),
		"invaders": int(_invader_spin.value),
		"show_agent_labels": _agent_labels_check.button_pressed,
		"show_agent_paths": _agent_paths_check.button_pressed,
		"show_vision": _vision_check.button_pressed,
		"show_tactics": _tactics_check.button_pressed,
		"show_room_zones": _room_zones_check.button_pressed,
		"show_nav_holes": _nav_holes_check.button_pressed,
	})
