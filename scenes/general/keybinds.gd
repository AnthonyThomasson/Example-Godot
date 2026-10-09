extends Node

## Central place for all input actions and their default keys.
##
## Autoloaded as `Keybinds` (see project.godot [autoload]). Everything that reads
## input should go through the constants and helpers here instead of hard-coding
## action-name strings, ## this file.

## Action names. Use these constants instead of raw strings elsewhere.
const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const MOVE_UP := "move_up"
const MOVE_DOWN := "move_down"
const PUNCH := "punch"
const FIRE := "fire"
const INTERACT := "interact"
## Return to the pre-game setup window to start a fresh match (handled by main.gd, works in both
## player and spectator mode).
const MENU := "menu"
## Pause/resume the game (spectator inspector only — shares Space with INTERACT, which is unused in the
## player-less spectator match).
const PAUSE := "pause"
const ITEM_1 := "item_1"
const ITEM_2 := "item_2"
const ITEM_3 := "item_3"
const ITEM_4 := "item_4"
const ITEM_5 := "item_5"
const ITEM_6 := "item_6"
const ITEM_7 := "item_7"
const ITEM_8 := "item_8"
const ITEM_9 := "item_9"

## Default key for each action, keyed by action name. Change a value here (or call
## `rebind()` at runtime) to customize the layout — e.g. swap WASD for arrow keys.
const DEFAULTS := {
	MOVE_LEFT: KEY_A,
	MOVE_RIGHT: KEY_D,
	MOVE_UP: KEY_W,
	MOVE_DOWN: KEY_S,
	PUNCH: KEY_F,
	INTERACT: KEY_SPACE,
	MENU: KEY_ESCAPE,
	PAUSE: KEY_SPACE,
	ITEM_1: KEY_1,
	ITEM_2: KEY_2,
	ITEM_3: KEY_3,
	ITEM_4: KEY_4,
	ITEM_5: KEY_5,
	ITEM_6: KEY_6,
	ITEM_7: KEY_7,
	ITEM_8: KEY_8,
	ITEM_9: KEY_9,
}


func _ready() -> void:
	# Make sure every action exists in the InputMap and matches DEFAULTS, even if
	# project.godot drifts. This is the single source of truth at runtime.
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		rebind(action, DEFAULTS[action])

	# FIRE is bound to a mouse button, which isn't a Key value, so it lives
	# outside the keyboard DEFAULTS dict and is registered separately here.
	rebind_mouse(FIRE, MOUSE_BUTTON_LEFT)


## Point the given action at a single physical key, replacing any existing events.
## `action` is one of the constants above; `keycode` is a Key value (e.g. KEY_A).
func rebind(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


## Point the given action at a single mouse button, replacing any existing events.
## Mirrors rebind() for pointer input (e.g. left-click to fire).
func rebind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


## Movement direction from the four move actions, ready to multiply by speed.
func get_move_vector() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN)


## True on the frame the punch key is pressed. Goes through the same rebindable
## action as movement, so remapping `PUNCH` via `rebind()` just works.
func is_punch_just_pressed() -> bool:
	return Input.is_action_just_pressed(PUNCH)


## True on the frame the fire button (left-click) is pressed. Rebindable via
## rebind_mouse(FIRE, ...) exactly like the keyboard actions.
func is_fire_just_pressed() -> bool:
	return Input.is_action_just_pressed(FIRE)


## True on the frame the interact key (space) is pressed. Goes through the same rebindable
## action path as the others.
func is_interact_just_pressed() -> bool:
	return Input.is_action_just_pressed(INTERACT)


## True on the frame the menu key (Escape) is pressed — main.gd uses it to return to the setup window.
## Rebindable like the others via rebind().
func is_menu_just_pressed() -> bool:
	return Input.is_action_just_pressed(MENU)


## Item selection (1-9). Returns the item number (1-9) if an item key was pressed
## on this frame, or -1 if none. Only the first pressed item is returned.
func get_selected_item() -> int:
	var items := [ITEM_1, ITEM_2, ITEM_3, ITEM_4, ITEM_5, ITEM_6, ITEM_7, ITEM_8, ITEM_9]
	for i in range(items.size()):
		if Input.is_action_just_pressed(items[i]):
			return i + 1  # 1-indexed: item 1-9, not 0-8.
	return -1  # No item key pressed.
