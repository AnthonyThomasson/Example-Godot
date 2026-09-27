extends Node

## Central place for all input actions and their default keys.
##
## Autoloaded as `Keybinds` (see project.godot [autoload]). Everything that reads
## input should go through the constants and helpers here instead of hard-coding
## action-name strings, so swapping keys or adding a rebind UI later touches only
## this file.

## Action names. Use these constants instead of raw strings elsewhere.
const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const MOVE_UP := "move_up"
const MOVE_DOWN := "move_down"
const PUNCH := "punch"

## Default key for each action, keyed by action name. Change a value here (or call
## `rebind()` at runtime) to customize the layout — e.g. swap WASD for arrow keys.
const DEFAULTS := {
	MOVE_LEFT: KEY_A,
	MOVE_RIGHT: KEY_D,
	MOVE_UP: KEY_W,
	MOVE_DOWN: KEY_S,
	PUNCH: KEY_F,
}


func _ready() -> void:
	# Make sure every action exists in the InputMap and matches DEFAULTS, even if
	# project.godot drifts. This is the single source of truth at runtime.
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		rebind(action, DEFAULTS[action])


## Point the given action at a single physical key, replacing any existing events.
## `action` is one of the constants above; `keycode` is a Key value (e.g. KEY_A).
func rebind(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


## Movement direction from the four move actions, ready to multiply by speed.
func get_move_vector() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN)


## True on the frame the punch key is pressed. Goes through the same rebindable
## action as movement, so remapping `PUNCH` via `rebind()` just works.
func is_punch_just_pressed() -> bool:
	return Input.is_action_just_pressed(PUNCH)
