extends Node

## Human input driver for a Character. Attach as a child of the character; each physics
## frame the character calls `control(character, delta)`, and this is the ONLY place in the
## character domain that reads Keybinds / the mouse. Swap in a different `control()`-having
## node (e.g. an AI brain) to drive a non-player character with no other changes.

## The fire button went down over a HUD control, so this press belongs to the UI until it is released.
var _fire_press_on_ui := false


## Called by the character at the top of its _physics_process, so the intent we write is
## used the same frame.
func control(character, _delta: float) -> void:
	character.move_input = Keybinds.get_move_vector()
	character.run_input = Keybinds.is_run_pressed()
	character.aim_point = character.get_global_mouse_position()

	var selected := Keybinds.get_selected_item()
	if selected > 0:
		character.select_slot(selected)

	if Keybinds.is_crouch_just_pressed():
		character.toggle_crouch()

	if Keybinds.is_punch_just_pressed():
		character.melee()
	if Keybinds.is_kick_just_pressed():
		character.leg_kick()
	# A click on a HUD control (the overlay bar, a panel) belongs to the UI, not the gun. Input polling
	# ignores GUI mouse filters, so ask the viewport what the pointer is over. A press that began on the UI
	# stays the UI's however far it is dragged.
	var over_ui: bool = character.get_viewport().gui_get_hovered_control() != null
	if Keybinds.is_fire_just_pressed():
		_fire_press_on_ui = over_ui
	# One shot per click; an automatic gun keeps firing for as long as the button is held (the gun paces itself).
	if not over_ui and not _fire_press_on_ui \
			and (Keybinds.is_fire_just_pressed() or (Keybinds.is_fire_pressed() and character.is_automatic())):
		character.shoot()
	if Keybinds.is_reload_just_pressed():
		character.reload()
	if Keybinds.is_interact_just_pressed():
		character.try_interact()
