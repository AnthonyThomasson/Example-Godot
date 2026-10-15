extends Node

## Central place for all input actions, their default bindings and runtime rebinding.
##
## Autoloaded as `Keybinds` (see project.godot [autoload]). Everything that reads
## input should go through the constants and helpers here instead of hard-coding
## action-name strings. Each action holds exactly one binding, a key or a mouse button.
## The settings page edits them through `bind()` / `reset()`; `Settings` (also General)
## persists the differences from the defaults via `overrides()` / `apply_overrides()`.

## Action names. Use these constants instead of raw strings elsewhere.
const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const MOVE_UP := "move_up"
const MOVE_DOWN := "move_down"
const RUN := "run"
## Crouch (toggle): a smaller target but slower, and only a standing character can run.
const CROUCH := "crouch"
const PUNCH := "punch"
## Kick with a leg, whatever is held.
const KICK := "kick"
const FIRE := "fire"
const INTERACT := "interact"
## Reload the held gun from a carried magazine.
const RELOAD := "reload"
## Get into the vehicle whose door is nearest, or out of the one the player sits in.
const USE_VEHICLE := "use_vehicle"
## Return to the pre-game setup window to start a fresh match (handled by main.gd, works in both
## player and spectator mode).
const MENU := "menu"
## Pause/resume the game (spectator inspector only — shares Space with INTERACT, which is unused in the
## player-less spectator match).
const PAUSE := "pause"
## Pan the spectator camera by hand (camera_controller.gd). Shares WASD with the MOVE_* actions —
## harmless because the spectator match has no player to move.
const CAMERA_LEFT := "camera_left"
const CAMERA_RIGHT := "camera_right"
const CAMERA_UP := "camera_up"
const CAMERA_DOWN := "camera_down"
## Zoom the camera (default: mouse wheel).
const ZOOM_IN := "zoom_in"
const ZOOM_OUT := "zoom_out"
const ITEM_1 := "item_1"
const ITEM_2 := "item_2"
const ITEM_3 := "item_3"
const ITEM_4 := "item_4"
const ITEM_5 := "item_5"
const ITEM_6 := "item_6"
const ITEM_7 := "item_7"
const ITEM_8 := "item_8"
const ITEM_9 := "item_9"

## Default key for each action, keyed by action name. Change a value here to change the shipped
## layout — e.g. swap WASD for arrow keys; a player's own changes go through `bind()` and `Settings`.
const DEFAULTS := {
	MOVE_LEFT: KEY_A,
	MOVE_RIGHT: KEY_D,
	MOVE_UP: KEY_W,
	MOVE_DOWN: KEY_S,
	RUN: KEY_SHIFT,
	CROUCH: KEY_C,
	PUNCH: KEY_F,
	KICK: KEY_V,
	INTERACT: KEY_SPACE,
	RELOAD: KEY_R,
	USE_VEHICLE: KEY_E,
	MENU: KEY_ESCAPE,
	PAUSE: KEY_SPACE,
	CAMERA_LEFT: KEY_A,
	CAMERA_RIGHT: KEY_D,
	CAMERA_UP: KEY_W,
	CAMERA_DOWN: KEY_S,
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

## Default mouse button for each pointer-bound action (`MouseButton` values aren't `Key`s, so they
## live apart from DEFAULTS).
const MOUSE_DEFAULTS := {
	FIRE: MOUSE_BUTTON_LEFT,
	ZOOM_IN: MOUSE_BUTTON_WHEEL_UP,
	ZOOM_OUT: MOUSE_BUTTON_WHEEL_DOWN,
}

## The settings-page label of each action, in page order. Every action in DEFAULTS / MOUSE_DEFAULTS
## needs a row here and in GROUPS (a test enforces it).
const LABELS := {
	MOVE_UP: "Move up",
	MOVE_DOWN: "Move down",
	MOVE_LEFT: "Move left",
	MOVE_RIGHT: "Move right",
	RUN: "Run (hold)",
	CROUCH: "Crouch",
	PUNCH: "Punch",
	KICK: "Kick",
	FIRE: "Fire",
	RELOAD: "Reload",
	INTERACT: "Interact",
	USE_VEHICLE: "Get in / out of vehicle",
	ITEM_1: "Item 1",
	ITEM_2: "Item 2",
	ITEM_3: "Item 3",
	ITEM_4: "Item 4",
	ITEM_5: "Item 5",
	ITEM_6: "Item 6",
	ITEM_7: "Item 7",
	ITEM_8: "Item 8",
	ITEM_9: "Item 9",
	CAMERA_UP: "Pan up",
	CAMERA_DOWN: "Pan down",
	CAMERA_LEFT: "Pan left",
	CAMERA_RIGHT: "Pan right",
	ZOOM_IN: "Zoom in",
	ZOOM_OUT: "Zoom out",
	PAUSE: "Pause (spectator)",
	MENU: "Back to setup",
}

## The settings-page section each action is listed under.
const GROUPS := {
	MOVE_UP: "Movement",
	MOVE_DOWN: "Movement",
	MOVE_LEFT: "Movement",
	MOVE_RIGHT: "Movement",
	RUN: "Movement",
	CROUCH: "Movement",
	PUNCH: "Combat",
	KICK: "Combat",
	FIRE: "Combat",
	RELOAD: "Combat",
	INTERACT: "Interaction",
	USE_VEHICLE: "Interaction",
	ITEM_1: "Items",
	ITEM_2: "Items",
	ITEM_3: "Items",
	ITEM_4: "Items",
	ITEM_5: "Items",
	ITEM_6: "Items",
	ITEM_7: "Items",
	ITEM_8: "Items",
	ITEM_9: "Items",
	CAMERA_UP: "Camera",
	CAMERA_DOWN: "Camera",
	CAMERA_LEFT: "Camera",
	CAMERA_RIGHT: "Camera",
	ZOOM_IN: "Camera",
	ZOOM_OUT: "Camera",
	PAUSE: "System",
	MENU: "System",
}

## Action pairs that deliberately share a binding, so `conflicts_of()` doesn't flag them: Interact and
## Pause (the player-less spectator match has nothing to interact with) and each camera pan key with
## its move key (the spectator match has no player to move).
const SHARED := [
	[INTERACT, PAUSE],
	[MOVE_UP, CAMERA_UP],
	[MOVE_DOWN, CAMERA_DOWN],
	[MOVE_LEFT, CAMERA_LEFT],
	[MOVE_RIGHT, CAMERA_RIGHT],
]

## The mouse buttons an action may be bound to, with their display names (the horizontal wheel is not bindable).
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Mouse Left",
	MOUSE_BUTTON_RIGHT: "Mouse Right",
	MOUSE_BUTTON_MIDDLE: "Mouse Middle",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4",
	MOUSE_BUTTON_XBUTTON2: "Mouse 5",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
}


func _ready() -> void:
	# Make sure every action exists in the InputMap and matches its default, even if
	# project.godot drifts. This is the single source of truth at runtime. Saved overrides
	# are layered on top by Main (`Settings.load_file()`), not here, so the headless test
	# runner never reads a developer's settings file.
	reset_all()


## Point `action` at the key or mouse button in `event`, replacing its current binding. A key is stored
## by its physical position (so it survives keyboard layouts); anything else (wheel, gamepad, an empty
## key) is refused. Returns whether the action was rebound.
func bind(action: String, event: InputEvent) -> bool:
	var fresh := _normalized(event)
	if fresh == null:
		return false
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, fresh)
	return true


## Put `action` back on its default binding.
func reset(action: String) -> void:
	bind(action, default_event(action))


## Put every action back on its default binding (and create any that are missing from the InputMap).
func reset_all() -> void:
	for action in actions():
		reset(action)


## Every action that has a default binding (keyboard first, then pointer).
func actions() -> Array:
	return DEFAULTS.keys() + MOUSE_DEFAULTS.keys()


## The binding `action` ships with, or null for an action with none.
func default_event(action: String) -> InputEvent:
	if MOUSE_DEFAULTS.has(action):
		return _mouse_event(MOUSE_DEFAULTS[action])
	if DEFAULTS.has(action):
		return _key_event(DEFAULTS[action])
	return null


## The binding `action` currently has, or null when it has none.
func event_of(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	return null if events.is_empty() else events[0]


## `action`'s current binding as text for a button ("W", "Space", "Mouse Left"), "Unbound" when it has none.
func text_of(action: String) -> String:
	var event := event_of(action)
	if event is InputEventKey:
		var physical: Key = (event as InputEventKey).physical_keycode
		var code: Key = physical
		# The key's label on the player's layout; a headless display server can't map it and logs an error.
		if DisplayServer.get_name() != "headless":
			code = DisplayServer.keyboard_get_keycode_from_physical(physical)
		return OS.get_keycode_string(code if code != KEY_NONE else physical)
	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		return MOUSE_NAMES.get(button, "Mouse %d" % button)
	return "Unbound"


## The other actions that share `action`'s binding, apart from the pairs in `SHARED`.
func conflicts_of(action: String) -> Array:
	var mine := _serialize(event_of(action))
	var out := []
	if mine.is_empty():
		return out
	for other in actions():
		if other != action and not _is_shared(action, other) and _serialize(event_of(other)) == mine:
			out.append(other)
	return out


## Whether `a` and `b` are a pair that may share a binding.
func _is_shared(a: String, b: String) -> bool:
	for pair in SHARED:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


## The bindings that differ from the defaults, as `{ action: { "key": int } | { "mouse": int } }` — what
## `Settings` writes to disk. Only differences are kept, so a changed default still reaches an action
## the player never touched.
func overrides() -> Dictionary:
	var out := {}
	for action in actions():
		var current := _serialize(event_of(action))
		if current != _serialize(default_event(action)):
			out[action] = current
	return out


## Rebind from an `overrides()`-shaped dictionary (as read back from JSON). Unknown actions and malformed
## entries are skipped one by one; actions not named keep their current binding.
func apply_overrides(data: Dictionary) -> void:
	for action in data:
		if actions().has(action):
			bind(action, _deserialize(data[action]))


## A fresh key or mouse-button event for the same input as `event`, or null when it isn't bindable.
func _normalized(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return null if code == KEY_NONE else _key_event(code)
	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		return _mouse_event(button) if MOUSE_NAMES.has(button) else null
	return null


## A key event for the physical `keycode`.
func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


## A mouse-button event for `button`.
func _mouse_event(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


## `{ "key": physical keycode }` / `{ "mouse": button index }` for a binding, `{}` for none.
func _serialize(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return { "key": int((event as InputEventKey).physical_keycode) }
	if event is InputEventMouseButton:
		return { "mouse": int((event as InputEventMouseButton).button_index) }
	return {}


## The binding a `_serialize()` dictionary describes, or null when it isn't one (JSON numbers arrive as floats).
func _deserialize(value: Variant) -> InputEvent:
	if not value is Dictionary:
		return null
	var data := value as Dictionary
	if data.has("key") and typeof(data["key"]) in [TYPE_INT, TYPE_FLOAT]:
		return _key_event(int(data["key"]) as Key)
	if data.has("mouse") and typeof(data["mouse"]) in [TYPE_INT, TYPE_FLOAT]:
		return _mouse_event(int(data["mouse"]) as MouseButton)
	return null


## Movement direction from the four move actions, ready to multiply by speed.
func get_move_vector() -> Vector2:
	return Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN)


## True while the run key is held.
func is_run_pressed() -> bool:
	return Input.is_action_pressed(RUN)


## True on the frame the crouch key is pressed (a toggle). Rebindable like the others.
func is_crouch_just_pressed() -> bool:
	return Input.is_action_just_pressed(CROUCH)



## Manual camera pan direction from the four camera actions (length <= 1).
func get_camera_vector() -> Vector2:
	return Input.get_vector(CAMERA_LEFT, CAMERA_RIGHT, CAMERA_UP, CAMERA_DOWN)


## True on the frame the punch key is pressed. Goes through the same rebindable
## action as movement, so rebinding `PUNCH` with `bind()` just works.
func is_punch_just_pressed() -> bool:
	return Input.is_action_just_pressed(PUNCH)


## True on the frame the kick key is pressed (rebindable through `KICK`).
func is_kick_just_pressed() -> bool:
	return Input.is_action_just_pressed(KICK)


## True on the frame the fire button (left-click) is pressed. Rebindable with `bind()`
## exactly like the keyboard actions.
func is_fire_just_pressed() -> bool:
	return Input.is_action_just_pressed(FIRE)


## True every frame the fire button is held down: how an automatic gun keeps firing.
func is_fire_pressed() -> bool:
	return Input.is_action_pressed(FIRE)


## True on the frame the interact key (space) is pressed. Goes through the same rebindable
## action path as the others.
func is_interact_just_pressed() -> bool:
	return Input.is_action_just_pressed(INTERACT)


## True on the frame the use-vehicle key (E) is pressed: get in, or out. Rebindable like the others.
func is_use_vehicle_just_pressed() -> bool:
	return Input.is_action_just_pressed(USE_VEHICLE)


## True on the frame the reload key (R) is pressed. Rebindable like the others.
func is_reload_just_pressed() -> bool:
	return Input.is_action_just_pressed(RELOAD)


## Item selection (1-9). Returns the item number (1-9) if an item key was pressed
## on this frame, or -1 if none. Only the first pressed item is returned.
func get_selected_item() -> int:
	var items := [ITEM_1, ITEM_2, ITEM_3, ITEM_4, ITEM_5, ITEM_6, ITEM_7, ITEM_8, ITEM_9]
	for i in range(items.size()):
		if Input.is_action_just_pressed(items[i]):
			return i + 1  # 1-indexed: item 1-9, not 0-8.
	return -1  # No item key pressed.
