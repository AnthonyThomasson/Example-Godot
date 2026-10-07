extends CanvasLayer

## General domain, pre-game setup window: a modal shown before the match starts so a human can choose
## the run's parameters — whether there is a human player, and how many defenders and invaders spawn —
## then hands them back to Main, which builds the world with them. Built entirely in code (no
## scene-side layout), like the other General HUDs.
##
## Main opens it on a fresh launch and spawns the world only once the player presses Start; scripted
## restarts (the dev command server) set an Engine `skip_setup` meta and bypass it, so the headless
## match harness is unaffected. A decoupled piece: it knows nothing of the domains, only the parameter
## dict it emits.

## Emitted when the player presses Start, carrying the chosen parameters:
## `{ has_player: bool, seed: int, spawn_doors: bool, defenders: int, invaders: int,
##    show_agent_labels: bool, show_agent_paths: bool, show_vision: bool }`.
## Main applies these and builds the world.
signal start_requested(config: Dictionary)

const _MAX_COUNT := 8  ## Upper bound per side in the spinboxes; spawn spread handles any count in range.

var _player_check: CheckBox         ## Checked = a human player; unchecked = the 2-AI spectator contest.
var _seed_edit: LineEdit            ## The level seed; blank/0 = a fresh random seed each run.
var _doors_check: CheckBox          ## Checked = physical doors are placed; unchecked = open archways only.
var _defender_spin: SpinBox         ## How many defenders to drop into the house.
var _invader_spin: SpinBox          ## How many invaders to spawn outside the house.
var _agent_labels_check: CheckBox   ## Checked = draw the floating action-status label above each NPC.
var _agent_paths_check: CheckBox    ## Checked = draw the NPC's live navigation path in the world.
var _vision_check: CheckBox         ## Checked = draw each NPC's line-of-sight / awareness overlay.


## Build the window seeded from `defaults` (`{ has_player, seed, spawn_doors, defenders, invaders,
## show_agent_labels, show_agent_paths, show_vision }`) and show it. Called by Main before the
## world is spawned.
func open(defaults: Dictionary) -> void:
	_build_ui(defaults)


# --- UI construction (built in code like the other General HUDs; no scene-side layout) ----------

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
		margin.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var title := Label.new()
	title.text = "MATCH SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	_player_check = CheckBox.new()
	_player_check.text = "Human player"
	_player_check.button_pressed = bool(defaults.get("has_player", false))
	box.add_child(_player_check)

	_doors_check = CheckBox.new()
	_doors_check.text = "Spawn doors"
	_doors_check.button_pressed = bool(defaults.get("spawn_doors", true))
	box.add_child(_doors_check)

	_seed_edit = _seed_row(box, int(defaults.get("seed", 0)))

	_defender_spin = _spin_row(box, "Defenders", int(defaults.get("defenders", 1)))
	_invader_spin = _spin_row(box, "Invaders", int(defaults.get("invaders", 1)))

	var sep := Label.new()
	sep.text = "Debug overlays"
	sep.add_theme_font_size_override("font_size", 14)
	sep.modulate = Color(1, 1, 1, 0.5)
	box.add_child(sep)

	_agent_labels_check = CheckBox.new()
	_agent_labels_check.text = "Agent labels"
	_agent_labels_check.button_pressed = bool(defaults.get("show_agent_labels", true))
	box.add_child(_agent_labels_check)

	_agent_paths_check = CheckBox.new()
	_agent_paths_check.text = "Agent paths"
	_agent_paths_check.button_pressed = bool(defaults.get("show_agent_paths", true))
	box.add_child(_agent_paths_check)

	_vision_check = CheckBox.new()
	_vision_check.text = "Vision cones"
	_vision_check.button_pressed = bool(defaults.get("show_vision", true))
	box.add_child(_vision_check)

	var start := Button.new()
	start.text = "Start"
	start.pressed.connect(_on_start)
	box.add_child(start)


## A labelled seed row (label + LineEdit), added to `parent`; returns the LineEdit so the caller can
## read it on Start. Prefilled with `value` unless it is 0, which shows as blank (= random).
func _seed_row(parent: VBoxContainer, value: int) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "Seed"
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = "random"
	edit.text = "" if value == 0 else str(value)
	edit.custom_minimum_size = Vector2(160, 0)
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
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = _MAX_COUNT
	spin.step = 1
	spin.value = clampi(value, 0, _MAX_COUNT)
	spin.custom_minimum_size = Vector2(100, 0)
	row.add_child(spin)
	parent.add_child(row)
	return spin


## Gather the chosen parameters and hand them to Main. Main applies them, frees this window and builds
## the world.
func _on_start() -> void:
	start_requested.emit({
		"has_player": _player_check.button_pressed,
		"seed": _seed_edit.text.strip_edges().to_int(),
		"spawn_doors": _doors_check.button_pressed,
		"defenders": int(_defender_spin.value),
		"invaders": int(_invader_spin.value),
		"show_agent_labels": _agent_labels_check.button_pressed,
		"show_agent_paths": _agent_paths_check.button_pressed,
		"show_vision": _vision_check.button_pressed,
	})
