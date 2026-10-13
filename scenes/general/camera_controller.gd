extends Camera2D

## Camera behavior: centers on player, but leads toward the mouse when it approaches screen edges.
## The mouse wheel zooms, in either mode, as a lasting scale on the automatic zoom. In framing mode
## (the spectator view) the viewer can also take the camera by hand — pan with the camera keys or by
## pushing the mouse to a screen edge — and after `manual_hold` seconds without panning the
## automatic framing eases back in.
## An explosion on the EventBus shakes the view (through `Camera2D.offset`, so the follow and the framing are untouched).
## This file owns all camera tuning and follows the input pattern.

## Higher = slower, smoother follow (the camera lerps by 1/follow_speed each frame).
@export var follow_speed: float = 8.0
## How far toward the mouse to lead the camera (world units).
@export var look_ahead_distance: float = 60.0
## Distance from screen center the mouse must reach to trigger look-ahead (0-1 fraction of screen).
@export var look_ahead_threshold: float = 0.6

## The node to follow. Set in the scene; defaults to a sibling "Player".
@export var target_path: NodePath = ^"../Player"
var _player: Node2D  ## The resolved target node.

## Framing group: extra world-space padding kept around the framed combatants so they aren't flush
## to the screen edge.
@export var frame_margin: float = 160.0
## Clamp for the fit-to-combatants zoom (Camera2D zoom: larger = more zoomed in).
@export var min_zoom: float = 0.4   ## Most zoomed-out the framing is allowed to get.
@export var max_zoom: float = 2.0   ## Most zoomed-in the framing is allowed to get.
var _frame_mode: bool = false       ## When on, frames `_frame_targets` instead of following `_player`.
var _frame_targets: Array[Node2D] = []  ## The nodes to keep framed (the match combatants).

## Each wheel notch scales the zoom by this factor (> 1; larger = bigger steps).
@export var zoom_step: float = 1.1
## Notches of zoom per unit of a trackpad's two-finger scroll (its pan-gesture delta).
@export var trackpad_zoom_sensitivity: float = 0.03
## Limits on the zoom the wheel can reach, whatever the automatic zoom is.
@export var wheel_min_zoom: float = 0.25  ## Most zoomed-out.
@export var wheel_max_zoom: float = 4.0   ## Most zoomed-in.
## Whether the viewer may pan a framing camera by hand. Off where WASD already drives a character.
@export var pan_enabled: bool = true
## Hand-pan speed, in screen pixels per second (so it feels the same at any zoom).
@export var pan_speed: float = 700.0
## Width (px) of the screen-edge band where the mouse pans the camera; 0 turns edge panning off.
@export var edge_pan_margin: float = 24.0
## Seconds without camera input before a hand-steered framing camera returns to automatic framing.
@export var manual_hold: float = 5.0
var _manual: bool = false        ## Framing mode only: the viewer has taken over the position.
var _idle: float = 0.0           ## Seconds since the last pan while `_manual`.
var _base_zoom: float = 1.0      ## The automatic zoom the wheel scales: 1 when following, the fit when framing.
var _zoom_bias: float = 1.0      ## The wheel's lasting scale on `_base_zoom`.
var _mouse_pos := Vector2.ZERO   ## Last mouse position seen over the window.
var _mouse_in_window: bool = false  ## Edge panning needs a live pointer: not yet seen, or left, = off.

## Explosion shake (`&"explosion"` events). A burst adds trauma (0..1) by its kind and how far it is from the camera, and the
## view is thrown about by `shake_max_offset * trauma^2` screen px, trauma draining at `shake_decay` a second.
## A frag at the camera is trauma 1 (`shake_frag`); a burst farther off than its range does not shake it at all.
@export var shake_frag: float = 1.0           ## Trauma of a frag's blast beside the camera.
@export var shake_stun: float = 0.5           ## Trauma of a stun's bang beside the camera.
@export var shake_frag_range: float = 1500.0  ## World px beyond which a frag does not shake the camera.
@export var shake_stun_range: float = 900.0   ## The same for a stun.
@export var shake_max_offset: float = 28.0    ## Screen px of the worst shake (trauma 1).
@export var shake_decay: float = 1.2          ## Trauma lost per second.
@export var shake_speed: float = 38.0         ## How fast the view is thrown about (rad/s of the fastest wobble).
var _trauma: float = 0.0                      ## 0..1, how much the camera is shaking now.
var _shake_clock: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the viewer can still pan and zoom while the match is paused
	_player = get_node_or_null(target_path)
	if not _player:
		push_warning("Camera: could not find target node at %s" % target_path)
	EventBus.posted.connect(_on_posted)


## A pointer that left the window (or a window that lost focus) keeps its last edge position, so
## it stops counting as an edge pan.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_mouse_in_window = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
		_mouse_in_window = true


## The mouse wheel (or whatever ZOOM_IN / ZOOM_OUT are bound to) and a trackpad's two-finger scroll
## scale the zoom in either mode and the scale stays; UI that scrolls gets the event first.
func _unhandled_input(event: InputEvent) -> void:
	var notches := 0.0  # signed: positive zooms in
	if event is InputEventPanGesture:
		# Scrolling up (negative delta) zooms in, like wheel-up.
		notches = -event.delta.y * trackpad_zoom_sensitivity
	elif event.is_action_pressed(Keybinds.ZOOM_IN):
		notches = _wheel_notches(event)
	elif event.is_action_pressed(Keybinds.ZOOM_OUT):
		notches = -_wheel_notches(event)
	else:
		return
	_zoom_bias = clampf(_zoom_bias * pow(zoom_step, notches),
			wheel_min_zoom / _base_zoom, wheel_max_zoom / _base_zoom)


## How many notches a zoom press counts for: a wheel's own amount (fractional for some mice), else 1.
func _wheel_notches(event: InputEvent) -> float:
	if event is InputEventMouseButton and event.factor > 0.0:
		return event.factor
	return 1.0


func _process(delta: float) -> void:
	_shake(delta)
	if _frame_mode:
		_steer_by_hand(delta)
		_frame_combatants()
	elif _player:
		var target_pos := _calculate_target_position()
		global_position = global_position.lerp(target_pos, 1.0 / follow_speed)
		_ease_zoom()


## A grenade went off: shake by its kind and how near it is (linear to nothing at the kind's range, felt squared).
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if topic != &"explosion":
		return
	var frag: bool = data.get("kind", &"") == &"frag"
	var reach := shake_frag_range if frag else shake_stun_range
	var near := 1.0 - global_position.distance_to(data.get("position", global_position)) / maxf(reach, 1.0)
	if near > 0.0:
		_trauma = minf(_trauma + (shake_frag if frag else shake_stun) * near * near, 1.0)


## Throw the view about by the trauma left (two out-of-step wobbles per axis, so it does not read as a pattern) and drain it.
## Divided by the zoom, so the shake is the same size on screen whatever the framing.
func _shake(delta: float) -> void:
	if _trauma <= 0.0:
		offset = Vector2.ZERO
		return
	_shake_clock += delta * shake_speed
	var wobble := Vector2(sin(_shake_clock) * 0.7 + sin(_shake_clock * 1.7 + 1.3) * 0.3,
			sin(_shake_clock * 1.3 + 2.1) * 0.7 + sin(_shake_clock * 2.3 + 0.4) * 0.3)
	offset = wobble * shake_max_offset * _trauma * _trauma / zoom.x
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)


## Switch to framing mode: ease to keep every live node in `targets` on screen (used by the
## spectator match view). A General observer — reads only Node2D positions + the `is_dead` property.
func frame(targets: Array) -> void:
	_frame_targets.clear()
	for t in targets:
		if t is Node2D:
			_frame_targets.append(t)
	_frame_mode = not _frame_targets.is_empty()
	_manual = false


## Framing mode: pan by the camera keys / screen edge, handing control to the viewer while they do
## and back to the automatic framing once `manual_hold` seconds pass without any camera input.
func _steer_by_hand(delta: float) -> void:
	var pan := (Keybinds.get_camera_vector() + _edge_pan()).limit_length(1.0) if pan_enabled else Vector2.ZERO
	if pan != Vector2.ZERO:
		_take_over()
		global_position += pan * pan_speed * delta / zoom.x
	elif _manual:
		_idle += delta
		if _idle >= manual_hold:
			_manual = false


## Framing mode: the viewer just panned. Freeze the automatic position where it is and restart the
## idle clock.
func _take_over() -> void:
	_idle = 0.0
	_manual = true


## Ease the zoom toward the automatic zoom scaled by the wheel.
func _ease_zoom() -> void:
	var z := clampf(_base_zoom * _zoom_bias, wheel_min_zoom, wheel_max_zoom)
	zoom = zoom.lerp(Vector2(z, z), 1.0 / follow_speed)


## Pan direction from the mouse pushing against a screen edge: each axis -1, 0 or 1.
func _edge_pan() -> Vector2:
	if edge_pan_margin <= 0.0 or not _mouse_in_window:
		return Vector2.ZERO
	var size := get_viewport_rect().size
	return Vector2(
		float(_mouse_pos.x >= size.x - edge_pan_margin) - float(_mouse_pos.x <= edge_pan_margin),
		float(_mouse_pos.y >= size.y - edge_pan_margin) - float(_mouse_pos.y <= edge_pan_margin))


## Centre on the midpoint of the live framed targets (unless the viewer holds the position) and zoom
## to fit them plus `frame_margin`. A downed combatant drops out of the framing; once all are down it
## holds on the last positions.
func _frame_combatants() -> void:
	var live: Array[Node2D] = []
	for t in _frame_targets:
		if is_instance_valid(t) and t.get("is_dead") != true:
			live.append(t)
	if live.is_empty():
		for t in _frame_targets:
			if is_instance_valid(t):
				live.append(t)
	if live.is_empty():
		return
	var box := Rect2(live[0].global_position, Vector2.ZERO)
	for t in live:
		box = box.expand(t.global_position)
	box = box.grow(frame_margin)
	if not _manual:
		global_position = global_position.lerp(box.get_center(), 1.0 / follow_speed)
	var vp := get_viewport_rect().size
	var fit := minf(vp.x / maxf(box.size.x, 1.0), vp.y / maxf(box.size.y, 1.0))
	_base_zoom = clampf(fit, min_zoom, max_zoom)
	_ease_zoom()


## The point the camera eases toward: the target, offset toward the mouse as it nears a
## screen edge.
func _calculate_target_position() -> Vector2:
	var player_pos := _player.global_position
	var mouse_world_pos := get_global_mouse_position()
	var to_mouse := mouse_world_pos - player_pos

	if to_mouse.length() < 0.1:
		# Mouse too close to player, don't look ahead.
		return player_pos

	var dir_to_mouse := to_mouse.normalized()

	# Determine how far from screen center the mouse is (screen space, 0-1).
	var screen_size := get_viewport_rect().size
	var mouse_screen := get_viewport().get_mouse_position()
	var screen_center := screen_size / 2.0
	var edge_offset := (mouse_screen - screen_center).abs()

	# Ramp up look-ahead as mouse approaches edges. Use the longer axis (x or y).
	var threshold_pixels := maxf(screen_size.x, screen_size.y) * 0.5 * look_ahead_threshold
	var edge_factor := minf(1.0, edge_offset.length() / threshold_pixels) if threshold_pixels > 0 else 0.0

	# Offset camera toward the mouse.
	var look_offset := dir_to_mouse * look_ahead_distance * edge_factor

	return player_pos + look_offset
