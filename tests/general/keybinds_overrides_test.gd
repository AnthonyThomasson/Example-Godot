extends GameTest

## Keybinds is the single place an input's binding lives: `bind` takes a key or a mouse button (and
## refuses anything else), `overrides` reports only what differs from the defaults, `apply_overrides`
## reads that back tolerantly, `reset` restores, and `conflicts_of` flags two actions on one input —
## except the Interact/Pause pair that deliberately shares Space.


func describe() -> Dictionary:
	return {
		"name": "Key bindings rebind, report overrides and flag conflicts",
		"description": "bind() takes keys and mouse buttons; overrides()/apply_overrides() round-trip only the differences; reset restores; conflicts_of flags shared inputs.",
		"tags": ["keybinds", "settings", "input"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	Keybinds.reset_all()
	t.expect_eq(Keybinds.text_of(Keybinds.INTERACT), "Space", "Interact starts on Space")
	t.expect_eq(Keybinds.text_of(Keybinds.FIRE), "Mouse Left", "Fire starts on the left mouse button")
	t.check(Keybinds.overrides().is_empty(), "a fresh run has no overrides")
	for action in Keybinds.actions():
		t.check(Keybinds.LABELS.has(action) and Keybinds.GROUPS.has(action), "%s has a settings label and group" % action)
	t.expect_eq(Keybinds.text_of(Keybinds.ZOOM_IN), "Wheel Up", "Zoom in starts on the wheel")
	t.check(Keybinds.conflicts_of(Keybinds.CAMERA_UP).is_empty(), "a camera key sharing its move key is not a conflict")
	t.check(Keybinds.conflicts_of(Keybinds.INTERACT).is_empty(), "Interact and Pause share Space without a conflict")

	# A key, stored by its physical position.
	var punch_f := _key(KEY_F)
	t.check(punch_f.is_action(Keybinds.PUNCH), "Punch starts on F")
	t.check(Keybinds.bind(Keybinds.PUNCH, _key(KEY_G)), "a key can be bound")
	t.check(_key(KEY_G).is_action(Keybinds.PUNCH), "the new key now triggers Punch")
	t.check(not punch_f.is_action(Keybinds.PUNCH), "the old key no longer does")
	t.expect_eq(Keybinds.overrides(), { Keybinds.PUNCH: { "key": KEY_G } }, "only the changed action is reported")

	# A mouse button, and the inputs that can't be bound.
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	t.check(Keybinds.bind(Keybinds.FIRE, right_click), "a mouse button can be bound")
	t.expect_eq(Keybinds.text_of(Keybinds.FIRE), "Mouse Right", "the button is described")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_LEFT
	t.check(not Keybinds.bind(Keybinds.FIRE, wheel), "the horizontal wheel is refused")
	t.check(not Keybinds.bind(Keybinds.FIRE, InputEventMouseMotion.new()), "a non-button event is refused")
	t.check(not Keybinds.bind(Keybinds.FIRE, InputEventKey.new()), "an empty key is refused")
	t.expect_eq(Keybinds.text_of(Keybinds.FIRE), "Mouse Right", "refused binds change nothing")

	# Two actions on one input are flagged, from both sides.
	Keybinds.bind(Keybinds.PUNCH, _key(KEY_W))
	t.expect_eq(Keybinds.conflicts_of(Keybinds.PUNCH), [Keybinds.MOVE_UP, Keybinds.CAMERA_UP], "Punch on W conflicts with Move up and Pan up")
	t.expect_eq(Keybinds.conflicts_of(Keybinds.MOVE_UP), [Keybinds.PUNCH], "and Move up with Punch")

	# Resetting puts defaults back; the report empties as the differences go.
	Keybinds.reset(Keybinds.PUNCH)
	t.check(_key(KEY_F).is_action(Keybinds.PUNCH), "reset puts Punch back on F")
	t.expect_eq(Keybinds.overrides().keys(), [Keybinds.FIRE], "only Fire still differs")
	Keybinds.reset_all()
	t.check(Keybinds.overrides().is_empty(), "reset_all clears every difference")

	# Reading overrides back: JSON numbers are floats, and junk entries are skipped one by one.
	Keybinds.apply_overrides({
		Keybinds.PUNCH: { "key": float(KEY_G) },
		Keybinds.FIRE: { "mouse": float(MOUSE_BUTTON_MIDDLE) },
		Keybinds.MOVE_UP: { "key": "not a number" },
		Keybinds.MOVE_DOWN: "not a dictionary",
		"no_such_action": { "key": KEY_Q },
	})
	t.check(_key(KEY_G).is_action(Keybinds.PUNCH), "a float keycode is applied")
	t.expect_eq(Keybinds.text_of(Keybinds.FIRE), "Mouse Middle", "a float mouse button is applied")
	t.check(_key(KEY_W).is_action(Keybinds.MOVE_UP), "a malformed entry leaves its action alone")
	t.check(_key(KEY_S).is_action(Keybinds.MOVE_DOWN), "a non-dictionary entry leaves its action alone")
	t.check(not InputMap.has_action("no_such_action"), "an unknown action is not created")

	Keybinds.reset_all()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event
