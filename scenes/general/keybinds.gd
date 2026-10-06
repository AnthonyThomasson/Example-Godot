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
## Operate a nearby door: tap to swing it fully, hold + mouse wheel to move it gradually.
const OPERATE_DOOR := "operate_door"
## Return to the pre-game setup window to start a fresh match (handled by main.gd, works in both
## player and spectator mode).
const MENU := "menu"
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
	OPERATE_DOOR: KEY_E,
	MENU: KEY_ESCAPE,
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


## Accumulated mouse-wheel ticks since the last consume_wheel() (+ up, - down). The wheel is
## event-only (no held state), so Keybinds captures it here and the controller polls consume_wheel().
var _wheel_ticks := 0


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


## Capture mouse-wheel ticks (the one event-driven input): the wheel has no held/pressed state to
## poll, so we accumulate ticks here and hand them to the controller via consume_wheel().
func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_wheel_ticks += 1
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_wheel_ticks -= 1


## Return the wheel ticks accumulated since the last call and reset to zero (+ up, - down).
func consume_wheel() -> int:
	var ticks := _wheel_ticks
	_wheel_ticks = 0
	return ticks


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


## Door-operate key state. just_pressed/just_released edge the E tap; pressed holds it for the
## wheel-driven gradual mode. Rebindable like the others via rebind().
func is_operate_door_pressed() -> bool:
	return Input.is_action_pressed(OPERATE_DOOR)


func is_operate_door_just_pressed() -> bool:
	return Input.is_action_just_pressed(OPERATE_DOOR)


func is_operate_door_just_released() -> bool:
	return Input.is_action_just_released(OPERATE_DOOR)


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
