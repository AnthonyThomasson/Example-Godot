extends CanvasLayer

## UI domain, in-game debug-overlay toggle bar: a collapsible panel of toggle buttons, one per overlay in
## `overlay_registry.gd`, grouped (Perception / Combat / Movement / Brain / Entry / Map / Stats). Pressing one emits
## `overlay_toggled(flag, on)`; each group's header button and the "All" button flip a whole set at once
## (all on unless they already are, then all off), emitting one `overlay_toggled` per flag changed. Main
## applies each live to the NPCs' overlay nodes (or, in the spectator match, to the inspector's
## selected-NPC flags). It knows nothing of the AI — only the registry rows and the flag dict it is given.
## Its "Overlays" title is a drag handle that moves the bar. Runs PROCESS_MODE_ALWAYS so it still works while the match is paused, and its panel swallows clicks so
## pressing a button never selects an NPC underneath.

const Registry := preload("res://scenes/ui/overlays/overlay_registry.gd")
const DragHandle := preload("res://scenes/ui/overlays/drag_handle.gd")

## Size multiplier for the whole bar (width, fonts, spacing).
const SCALE := 1.5

## Screen width the bar occupies from the right edge (panel + margin); other top-right HUDs dock left of it.
const RESERVED_WIDTH := SCALE * 220.0 + 10.0

## Emitted when a button is pressed: the overlay's `show_<x>` flag and its new state.
signal overlay_toggled(flag: String, on: bool)

var _buttons: Dictionary = {}  ## flag → its toggle Button.
var _body: Control             ## The button list, hidden when the bar is collapsed.
var _header: Button            ## The collapse/expand button.
var _all_button: Button        ## Flips every overlay at once.
var _group_buttons: Dictionary = {}  ## group name → its header Button (flips that group).
var _group_flags: Dictionary = {}    ## group name → Array of its flags.


## Build the bar seeded from `flags` (`{ flag: bool }`; a missing flag uses its registry default).
func setup(flags: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -RESERVED_WIDTH
	panel.offset_right = -10.0
	panel.offset_top = 10.0
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(2 * SCALE))
	panel.add_child(box)
	var title_row := HBoxContainer.new()
	box.add_child(title_row)
	var grip := Label.new()  # the drag handle: left-drag it to move the whole bar
	grip.text = "Overlays"
	grip.tooltip_text = "Drag to move"
	grip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grip.add_theme_font_size_override("font_size", int(16 * SCALE))
	title_row.add_child(grip)
	var drag := DragHandle.new()
	grip.add_child(drag)
	drag.setup(grip, panel)
	_header = Button.new()
	_header.add_theme_font_size_override("font_size", int(16 * SCALE))
	_header.pressed.connect(_toggle_collapsed)
	title_row.add_child(_header)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(2 * SCALE))
	box.add_child(_body)
	_all_button = Button.new()  # click to flip every overlay
	_all_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_all_button.focus_mode = Control.FOCUS_NONE
	_all_button.add_theme_font_size_override("font_size", int(14 * SCALE))
	_all_button.pressed.connect(func(): _on_bulk_pressed(_all_flags()))
	_body.add_child(_all_button)
	var group := ""
	for e in Registry.ENTRIES:
		if e["group"] != group:
			group = e["group"]
			_group_flags[group] = []
			var title := Button.new()  # click to flip the whole group
			title.flat = true
			title.alignment = HORIZONTAL_ALIGNMENT_LEFT
			title.focus_mode = Control.FOCUS_NONE
			title.add_theme_font_size_override("font_size", int(12 * SCALE))
			title.modulate = Color(1, 1, 1, 0.7)
			title.pressed.connect(_on_bulk_pressed.bind(_group_flags[group]))
			_body.add_child(title)
			_group_buttons[group] = title
		(_group_flags[group] as Array).append(e["flag"])
		var b := Button.new()
		b.toggle_mode = true
		b.text = e["label"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE  # keep Space (pause / interact) from re-pressing a focused button
		b.add_theme_font_size_override("font_size", int(14 * SCALE))
		b.button_pressed = bool(flags.get(e["flag"], e["default"]))
		b.toggled.connect(_on_toggled.bind(e["flag"]))
		_body.add_child(b)
		_buttons[e["flag"]] = b
	_refresh_bulk()
	_set_collapsed(false)


## Set a flag's button without emitting (e.g. when something else changed the flag).
func set_flag(flag: String, on: bool) -> void:
	if _buttons.has(flag):
		(_buttons[flag] as Button).set_pressed_no_signal(on)
		_refresh_bulk()


## A flag's button was toggled: announce it.
func _on_toggled(on: bool, flag: String) -> void:
	overlay_toggled.emit(flag, on)
	_refresh_bulk()


## A group header or "All" was pressed: turn all of `flags` on, or all off if they already are.
func _on_bulk_pressed(flags: Array) -> void:
	var on := _count_on(flags) < flags.size()
	for flag in flags:
		var b := _buttons[flag] as Button
		if b.button_pressed != on:
			b.button_pressed = on  # emits toggled → overlay_toggled


## Every overlay flag in the registry, in display order.
func _all_flags() -> Array:
	var flags: Array = []
	for e in Registry.ENTRIES:
		flags.append(e["flag"])
	return flags


## How many of `flags` have their button pressed.
func _count_on(flags: Array) -> int:
	var n := 0
	for flag in flags:
		if (_buttons[flag] as Button).button_pressed:
			n += 1
	return n


## Relabel the "All" and group header buttons with how many of their overlays are on.
func _refresh_bulk() -> void:
	if _all_button == null:
		return
	var all := _all_flags()
	_all_button.text = "All (%d/%d)" % [_count_on(all), all.size()]
	for group in _group_buttons:
		var flags: Array = _group_flags[group]
		(_group_buttons[group] as Button).text = "%s (%d/%d)" % [group, _count_on(flags), flags.size()]


## The header was pressed: flip the panel between collapsed and open.
func _toggle_collapsed() -> void:
	_set_collapsed(_body.visible)


## Show or hide the toggle list and update the header's arrow.
func _set_collapsed(collapsed: bool) -> void:
	_body.visible = not collapsed
	_header.text = ("▸" if collapsed else "▾")
	_header.focus_mode = Control.FOCUS_NONE
