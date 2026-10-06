extends Node

## Human input driver for a Character. Attach as a child of the character; each physics
## frame the character calls `control(character, delta)`, and this is the ONLY place in the
## character domain that reads Keybinds / the mouse. Swap in a different `control()`-having
## node (e.g. an AI brain) to drive a non-player character with no other changes.

## How close (px) a door must be to operate it — matches the interaction reach.
const DOOR_REACH := 46.0
## Open-fraction change per mouse-wheel tick while holding the operate-door key.
const WHEEL_STEP := 0.12

## The door latched on the current operate-door press (so the wheel adjusts that one door until
## release), and whether the wheel moved it this hold (a hold without the wheel = a full swing).
var _held_door: Node = null
var _wheel_used := false


## Called by the character at the top of its _physics_process, so the intent we write is
## used the same frame.
func control(character, _delta: float) -> void:
	character.move_input = Keybinds.get_move_vector()
	character.aim_point = character.get_global_mouse_position()

	var selected := Keybinds.get_selected_item()
	if selected > 0:
		character.select_slot(selected)

	if Keybinds.is_punch_just_pressed():
		character.melee()
	if Keybinds.is_fire_just_pressed():
		character.shoot()
	if Keybinds.is_interact_just_pressed():
		character.try_interact()

	_operate_door(character)


## Door operation: tap E to swing the nearest door fully; hold E and scroll the wheel to move it
## gradually. On press we latch the nearest door and drop any stale wheel ticks; while held the
## wheel nudges it; on release, if the wheel was never used, it's a tap -> full swing.
func _operate_door(character) -> void:
	if Keybinds.is_operate_door_just_pressed():
		_held_door = _nearest_door(character)
		_wheel_used = false
		Keybinds.consume_wheel()
	elif Keybinds.is_operate_door_pressed() and is_instance_valid(_held_door):
		var wheel := Keybinds.consume_wheel()
		if wheel != 0:
			_held_door.nudge(wheel * WHEEL_STEP)
			_wheel_used = true

	if Keybinds.is_operate_door_just_released():
		if is_instance_valid(_held_door) and not _wheel_used:
			_held_door.swing()
		_held_door = null


## The door (group "doors") within DOOR_REACH of the character and nearest the mouse (aim_point),
## or null. Mirrors CharacterInteraction's "closest to where you're aiming" targeting.
func _nearest_door(character) -> Node:
	var best: Node = null
	var best_d := INF
	for door in get_tree().get_nodes_in_group("doors"):
		if not is_instance_valid(door):
			continue
		if door.operate_distance(character.global_position) > DOOR_REACH:
			continue
		var d: float = door.operate_distance(character.aim_point)
		if d < best_d:
			best_d = d
			best = door
	return best
