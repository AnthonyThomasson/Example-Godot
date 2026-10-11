extends Node

## Human input driver for a Character. Attach as a child of the character; each physics
## frame the character calls `control(character, delta)`, and this is the ONLY place in the
## character domain that reads Keybinds / the mouse. Swap in a different `control()`-having
## node (e.g. an AI brain) to drive a non-player character with no other changes.

## Called by the character at the top of its _physics_process, so the intent we write is
## used the same frame.
func control(character, _delta: float) -> void:
	character.move_input = Keybinds.get_move_vector()
	character.run_input = Keybinds.is_run_pressed()
	character.aim_point = character.get_global_mouse_position()

	var selected := Keybinds.get_selected_item()
	if selected > 0:
		character.select_slot(selected)

	if Keybinds.is_punch_just_pressed():
		character.melee()
	# A click on a HUD control (the overlay bar, a panel) belongs to the UI, not the gun. Input polling
	# ignores GUI mouse filters, so ask the viewport what the pointer is over.
	if Keybinds.is_fire_just_pressed() and character.get_viewport().gui_get_hovered_control() == null:
		character.shoot()
	if Keybinds.is_reload_just_pressed():
		character.reload()
	if Keybinds.is_interact_just_pressed():
		character.try_interact()
