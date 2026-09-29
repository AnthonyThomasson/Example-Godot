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


func _ready() -> void:
	_player = get_node_or_null(target_path)
	if not _player:
		push_warning("Camera: could not find target node at %s" % target_path)


func _process(_delta: float) -> void:
	if not _player:
		return

	var target_pos := _calculate_target_position()
	global_position = global_position.lerp(target_pos, 1.0 / follow_speed)


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
