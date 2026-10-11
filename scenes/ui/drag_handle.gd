extends Node

## UI domain, drag-to-move helper: add it as a child of any Control and left-click-drag that Control (the
## handle) to move `target` (a panel anchored to a screen edge), keeping `target` fully inside the viewport.
## Moves the target by shifting its offsets, so its anchors (and so its place on window resize) are kept.

var _handle: Control
var _target: Control
var _dragging := false


## Make `handle` (this node's parent) drag `target`.
func setup(handle: Control, target: Control) -> void:
	_handle = handle
	_target = target
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.gui_input.connect(_on_gui_input)


## Starts or ends a drag on left-button press or release.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_handle.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_move(event.relative)
		_handle.accept_event()


## Shift the target by `delta`, then back inside the viewport if that pushed it out.
func _move(delta: Vector2) -> void:
	_shift(delta)
	var rect := _target.get_global_rect()
	var view := _target.get_viewport_rect()
	var fix := Vector2.ZERO
	fix.x = clampf(view.position.x - rect.position.x, 0.0, INF) \
		+ clampf(view.end.x - rect.end.x, -INF, 0.0)
	fix.y = clampf(view.position.y - rect.position.y, 0.0, INF) \
		+ clampf(view.end.y - rect.end.y, -INF, 0.0)
	_shift(fix)


## Moves the target panel by `delta`.
func _shift(delta: Vector2) -> void:
	_target.offset_left += delta.x
	_target.offset_right += delta.x
	_target.offset_top += delta.y
	_target.offset_bottom += delta.y
