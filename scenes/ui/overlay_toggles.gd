extends CanvasLayer

## UI domain, in-game debug-overlay toggle bar: a collapsible panel of toggle buttons, one per overlay in
## `overlay_registry.gd`, grouped (Perception / Combat / Movement / Brain / Map). Pressing one emits
## `overlay_toggled(flag, on)`; Main applies it live to the NPCs' overlay nodes (or, in the spectator
## match, to the inspector's selected-NPC flags). It knows nothing of the AI — only the registry rows and
## the flag dict it is given. Runs PROCESS_MODE_ALWAYS so it still works while the match is paused, and
## its panel swallows clicks so pressing a button never selects an NPC underneath.

const Registry := preload("res://scenes/ui/overlay_registry.gd")

## Size multiplier for the whole bar (width, fonts, spacing).
const SCALE := 1.5

## Emitted when a button is pressed: the overlay's `show_<x>` flag and its new state.
signal overlay_toggled(flag: String, on: bool)

var _buttons: Dictionary = {}  ## flag → its toggle Button.
var _body: Control             ## The button list, hidden when the bar is collapsed.
var _header: Button            ## The collapse/expand button.


## Build the bar seeded from `flags` (`{ flag: bool }`; a missing flag uses its registry default).
func setup(flags: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -SCALE * 220.0 - 10.0
	panel.offset_right = -10.0
	panel.offset_top = 10.0
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(2 * SCALE))
	panel.add_child(box)
	_header = Button.new()
	_header.add_theme_font_size_override("font_size", int(16 * SCALE))
	_header.pressed.connect(_toggle_collapsed)
	box.add_child(_header)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(2 * SCALE))
	box.add_child(_body)
	var group := ""
	for e in Registry.ENTRIES:
		if e["group"] != group:
			group = e["group"]
			var title := Label.new()
			title.text = group
			title.add_theme_font_size_override("font_size", int(12 * SCALE))
			title.modulate = Color(1, 1, 1, 0.5)
			_body.add_child(title)
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
	_set_collapsed(false)


## Set a flag's button without emitting (e.g. when something else changed the flag).
func set_flag(flag: String, on: bool) -> void:
	if _buttons.has(flag):
		(_buttons[flag] as Button).set_pressed_no_signal(on)


## A flag's button was toggled: announce it.
func _on_toggled(on: bool, flag: String) -> void:
	overlay_toggled.emit(flag, on)


## The header was pressed: flip the panel between collapsed and open.
func _toggle_collapsed() -> void:
	_set_collapsed(_body.visible)


## Show or hide the toggle list and update the header's arrow.
func _set_collapsed(collapsed: bool) -> void:
	_body.visible = not collapsed
	_header.text = ("Overlays  ▸" if collapsed else "Overlays  ▾")
	_header.focus_mode = Control.FOCUS_NONE
