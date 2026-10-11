extends GameTest

## The settings window is plain data in, signals out: it draws the rows it is given, turns a click on a
## key button into a capture, hands the next key or mouse press back as `rebind_requested`, and owns
## Escape (cancel a capture, else go back) so it never reaches Main's "return to setup". Driven by feeding
## it events directly; it knows nothing of Keybinds, so the rows here are hand-made.

const SettingsMenu := preload("res://scenes/ui/settings_menu.gd")

var _menu: CanvasLayer
var _rebinds: Array = []
var _resets: Array = []
var _debugs: Array = []
var _backs := 0


func describe() -> Dictionary:
	return {
		"name": "Settings window captures a key and owns Escape",
		"description": "Rows draw from plain dicts; clicking a key button captures the next key/mouse press as rebind_requested; Escape cancels a capture, else goes back; Reset and Debug emit their signals.",
		"tags": ["settings", "ui", "input"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	_menu = SettingsMenu.new()
	t.world.add_child(_menu)
	_menu.rebind_requested.connect(func(action, event): _rebinds.append([action, event]))
	_menu.reset_requested.connect(func(action): _resets.append(action))
	_menu.debug_changed.connect(func(on): _debugs.append(on))
	_menu.back_requested.connect(func(): _backs += 1)
	_menu.open({ "debug": true, "rows": _rows() })

	# The rows draw from the dicts.
	for label in ["Move up", "Punch", "Fire"]:
		t.check(_row(label) != null, "a row for %s" % label)
	t.expect_eq(_key_button("Punch").text, "G", "the key button shows the row's text")
	t.expect_eq(_note("Punch").text, "also: Move up", "a shared binding is noted")
	t.expect_eq(_note("Move up").text, "", "an unshared one has no note")
	t.check(not _reset_button("Punch").disabled, "a changed row can be reset")
	t.check(_reset_button("Move up").disabled, "an unchanged row has nothing to reset")

	# The Debug checkbox starts as given and reports a change.
	var debug_check: CheckBox = _menu.find_children("*", "CheckBox", true, false)[0]
	t.check(debug_check.button_pressed, "Debug starts as given")
	t.check(_debugs.is_empty(), "seeding Debug emits nothing")
	debug_check.button_pressed = false
	t.expect_eq(_debugs, [false], "toggling Debug is reported")

	# Escape with nothing being captured goes back.
	_menu._input(_key(KEY_ESCAPE))
	t.expect_eq(_backs, 1, "idle Escape goes back")

	# Clicking a key button starts a capture; Escape cancels it without going back.
	_key_button("Punch").pressed.emit()
	t.expect_eq(_key_button("Punch").text, "Press a key…", "the row prompts for a key")
	_menu._input(_key(KEY_ESCAPE))
	t.expect_eq(_key_button("Punch").text, "G", "Escape cancels the capture")
	t.check(_rebinds.is_empty() and _backs == 1, "a cancelled capture rebinds nothing and does not go back")

	# A key release or repeat is not a capture; the next press is.
	_key_button("Punch").pressed.emit()
	var release := _key(KEY_H)
	release.pressed = false
	_menu._input(release)
	var echo := _key(KEY_H)
	echo.echo = true
	_menu._input(echo)
	t.check(_rebinds.is_empty(), "a release or an echo is not captured")
	_menu._input(_key(KEY_H))
	if not t.require(_rebinds.size() == 1, "a key press is captured"):
		return
	t.expect_eq(_rebinds[0][0], "punch", "for the row being captured")
	t.expect_eq((_rebinds[0][1] as InputEventKey).physical_keycode, KEY_H, "with the key pressed")
	t.expect_eq(_key_button("Punch").text, "G", "the window waits for the host's new rows")

	# A mouse press is captured too.
	_key_button("Fire").pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	_menu._input(click)
	if not t.require(_rebinds.size() == 2, "a mouse press is captured"):
		return
	t.expect_eq((_rebinds[1][1] as InputEventMouseButton).button_index, MOUSE_BUTTON_RIGHT, "with the button pressed")

	# New rows from the host replace the list and end any capture.
	_key_button("Punch").pressed.emit()
	var rows := _rows()
	rows[1]["text"] = "H"
	_menu.set_rows(rows)
	t.expect_eq(_key_button("Punch").text, "H", "set_rows redraws")

	# Reset reports the row's action.
	_reset_button("Punch").pressed.emit()
	t.expect_eq(_resets, ["punch"], "Reset reports its action")

	_menu.queue_free()


func _rows() -> Array:
	return [
		{ "action": "move_up", "label": "Move up", "group": "Movement", "text": "W", "conflicts": [], "changed": false },
		{ "action": "punch", "label": "Punch", "group": "Combat", "text": "G", "conflicts": ["Move up"], "changed": true },
		{ "action": "fire", "label": "Fire", "group": "Combat", "text": "Mouse Left", "conflicts": [], "changed": false },
	]


## The row whose name label reads `label` (rebuilt on every redraw, so look it up fresh each time).
func _row(label: String) -> HBoxContainer:
	for box in _menu.find_children("*", "HBoxContainer", true, false):
		if box.get_child_count() > 0 and box.get_child(0) is Label and (box.get_child(0) as Label).text == label:
			return box
	return null


func _key_button(label: String) -> Button:
	return _row(label).get_child(1)


func _note(label: String) -> Label:
	return _row(label).get_child(2)


func _reset_button(label: String) -> Button:
	return _row(label).get_child(3)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event
