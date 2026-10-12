extends CanvasLayer

## UI domain, settings page: a full-screen window with the Debug checkbox and one row per rebindable
## input — the action's name, a button showing its key (click it, then press the new key or mouse
## button), a note when another action shares the binding, and a Reset. Built entirely in code, like
## the other UI windows (an opaque full-screen page like the test browser), above everything (layer 20)
## so it can open over the setup window.
##
## A decoupled piece, like the test browser window: it takes plain dicts and only emits signals — the
## host (Main) applies each change to the settings and answers with `set_rows()`. It knows nothing of
## the input system beyond the raw `InputEvent` it hands back.
##
## While it is open it owns Escape and, during a capture, every key press: both are consumed in
## `_input`, which runs before the host's `_unhandled_input`, so Escape never reaches Main's
## "return to setup" and a captured key never reaches the game.

## The Debug checkbox changed.
signal debug_changed(on: bool)
## A key or mouse press was captured for `action`; the host decides whether it can be bound.
signal rebind_requested(action: String, event: InputEvent)
## The row's Reset button: put `action` back on its default.
signal reset_requested(action: String)
## The Reset all button.
signal reset_all_requested
## Back, or Escape while idle.
signal back_requested

const _LAYER := 20
const _ROW_FONT := 22
const _CONFLICT_COLOR := Color(1.0, 0.45, 0.35)
const _PROMPT := "Press a key…"

var _debug_check: CheckBox  ## The Debug checkbox.
var _list: VBoxContainer    ## The scrolling list of headings and rows.
var _rows: Array = []        ## The latest rows from the host: `{ action, label, group, text, conflicts, changed }`.
var _capturing := ""         ## The action waiting for its next key or mouse press, "" when idle.


func _init() -> void:
	layer = _LAYER


## Build the window from `model` = `{ debug: bool, rows: Array }` and show it. Each row is
## `{ action, label, group, text, conflicts: [labels], changed: bool }`, in display order.
func open(model: Dictionary) -> void:
	_build_ui(bool(model.get("debug", false)))
	set_rows(model.get("rows", []))


## Replace the rows (after the host applied a change) and redraw the list. Any capture in progress ends.
func set_rows(rows: Array) -> void:
	_rows = rows
	_capturing = ""
	_rebuild()


# --- UI construction ------------------------------------------------------------------------

## Lay out the opaque page: title, Debug checkbox, the scrolling list and the bottom buttons.
func _build_ui(debug_on: bool) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)  # opaque, so the setup window underneath doesn't show through
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks meant for the window underneath
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	box.add_child(title)

	_debug_check = CheckBox.new()
	_debug_check.text = "Debug (AI overlays and their toggle bar)"
	_debug_check.button_pressed = debug_on
	_debug_check.add_theme_font_size_override("font_size", 26)
	_debug_check.toggled.connect(debug_changed.emit)
	box.add_child(_debug_check)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var reset_all := Button.new()
	reset_all.text = "Reset all keys"
	reset_all.add_theme_font_size_override("font_size", 24)
	reset_all.pressed.connect(reset_all_requested.emit)
	buttons.add_child(reset_all)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(back_requested.emit)
	buttons.add_child(back)


## Redraw the list from `_rows`: a heading whenever the group changes, then one row per action.
func _rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)  # detached now, so the old and new rows never show together
		child.queue_free()
	var group := ""
	for row in _rows:
		if row.group != group:
			group = row.group
			_list.add_child(_heading(group))
		_list.add_child(_row(row))


## A group heading label.
func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


## One action row: name, key button, conflict note, Reset.
func _row(row: Dictionary) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.text = row.label
	name_label.custom_minimum_size = Vector2(260, 0)
	name_label.add_theme_font_size_override("font_size", _ROW_FONT)
	box.add_child(name_label)

	var capturing: bool = _capturing == row.action
	var key := Button.new()
	key.text = _PROMPT if capturing else str(row.text)
	key.custom_minimum_size = Vector2(230, 0)
	key.focus_mode = Control.FOCUS_NONE  # Space/Enter must not re-press it
	key.add_theme_font_size_override("font_size", _ROW_FONT)
	key.pressed.connect(_begin_capture.bind(row.action))
	box.add_child(key)

	var note := Label.new()
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	note.add_theme_font_size_override("font_size", 20)
	if capturing:
		note.text = "Esc cancels"
		note.modulate = Color(1, 1, 1, 0.7)
	elif not row.conflicts.is_empty():
		note.text = "also: " + ", ".join(row.conflicts)
		note.add_theme_color_override("font_color", _CONFLICT_COLOR)
	box.add_child(note)

	var reset := Button.new()
	reset.text = "Reset"
	reset.custom_minimum_size = Vector2(110, 0)
	reset.disabled = not row.changed
	reset.focus_mode = Control.FOCUS_NONE
	reset.add_theme_font_size_override("font_size", 20)
	reset.pressed.connect(reset_requested.emit.bind(row.action))
	box.add_child(reset)
	return box


# --- capture ---------------------------------------------------------------------------------

## Start waiting for the next key or mouse press for `action`.
func _begin_capture(action: String) -> void:
	_capturing = action
	_rebuild()


## Stop waiting and redraw.
func _end_capture() -> void:
	_capturing = ""
	_rebuild()


## Consume Escape (back, or cancel a capture) and, during a capture, the next key or mouse press.
## Handled here in `_input` so it never reaches Main's `_unhandled_input` or the game.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if _capturing == "":
		if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			back_requested.emit()
		return
	if key != null:
		get_viewport().set_input_as_handled()  # a capture swallows every key, releases included
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				_end_capture()
			else:
				_commit(event)
	elif click != null and click.pressed:
		get_viewport().set_input_as_handled()
		_commit(event)


## End the capture and hand the press to the host, which answers with `set_rows` if it rebound.
func _commit(event: InputEvent) -> void:
	var action := _capturing
	_end_capture()
	rebind_requested.emit(action, event)
