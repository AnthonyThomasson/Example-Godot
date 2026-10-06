extends Camera2D

## Camera behavior: centers on player, but leads toward the mouse when it approaches screen edges.
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


func _ready() -> void:
	_player = get_node_or_null(target_path)
	if not _player:
		push_warning("Camera: could not find target node at %s" % target_path)


func _process(_delta: float) -> void:
	if _frame_mode:
		_frame_combatants()
		return
	if not _player:
		return

	var target_pos := _calculate_target_position()
	global_position = global_position.lerp(target_pos, 1.0 / follow_speed)


## Switch to framing mode: ease to keep every live node in `targets` on screen (used by the
## spectator match view). A General observer — reads only Node2D positions + the `is_dead` property.
func frame(targets: Array) -> void:
	_frame_targets.clear()
	for t in targets:
		if t is Node2D:
			_frame_targets.append(t)
	_frame_mode = not _frame_targets.is_empty()


## Centre on the midpoint of the live framed targets and zoom to fit them plus `frame_margin`. A
## downed combatant drops out of the framing; once all are down it holds on the last positions.
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
	global_position = global_position.lerp(box.get_center(), 1.0 / follow_speed)
	var vp := get_viewport_rect().size
	var fit := minf(vp.x / maxf(box.size.x, 1.0), vp.y / maxf(box.size.y, 1.0))
	var z := clampf(fit, min_zoom, max_zoom)
	zoom = zoom.lerp(Vector2(z, z), 1.0 / follow_speed)


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
	var offset := dir_to_mouse * look_ahead_distance * edge_factor

	return player_pos + offset
