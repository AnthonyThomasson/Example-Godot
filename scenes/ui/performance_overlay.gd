extends CanvasLayer

## UI domain, performance overlay: a compact stats panel (FPS, frame / physics time, draw calls, nodes,
## memory) with a frame-time graph, toggled by the "Performance" button of the overlay toggle bar. It docks
## directly left of that bar (`OverlayToggles.RESERVED_WIDTH`), below the match HUD's timer and to the right
## of its goal readout, so it overlaps none of the other HUDs until moved: left-drag the panel to put it
## elsewhere. Reads only Godot's `Performance` monitors and the frame delta — it knows nothing of the
## domains. Runs PROCESS_MODE_ALWAYS so it keeps updating (and stays draggable) while the match is paused.

const Toggles := preload("res://scenes/ui/overlay_toggles.gd")
const DragHandle := preload("res://scenes/ui/drag_handle.gd")

## Panel width in px, and its top edge (clears the match HUD's top-centre timer).
const PANEL_WIDTH := 232.0
const PANEL_TOP := 76.0
## Gap between the panel and the toggle bar.
const BAR_GAP := 8.0
const FONT_SIZE := 18
## Frame-time samples kept for the graph and the min / max readout (one per frame).
const SAMPLES := 120
## Graph size in px, and the frame time its full height stands for.
const GRAPH_HEIGHT := 44.0
const GRAPH_MAX_MS := 33.4
## Frame time of a steady 60 fps: the graph's reference line and its green / amber threshold.
const TARGET_MS := 16.7
## Seconds between text refreshes (the graph samples every frame).
const REFRESH := 0.25

var _label: Label
var _graph: Control
var _frame_ms := PackedFloat32Array()  ## Ring buffer of recent frame times in ms.
var _next := 0                         ## Slot the next sample is written to (the oldest one).
var _since_refresh := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 9
	_frame_ms.resize(SAMPLES)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_right = -(Toggles.RESERVED_WIDTH + BAR_GAP)
	panel.offset_left = panel.offset_right - PANEL_WIDTH
	panel.offset_top = PANEL_TOP
	panel.modulate = Color(1, 1, 1, 0.85)
	add_child(panel)
	var drag := DragHandle.new()  # left-drag anywhere on the panel to move it
	panel.add_child(drag)
	drag.setup(panel, panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks fall through to the panel's drag
	panel.add_child(box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	box.add_child(_label)
	_graph = Control.new()
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.custom_minimum_size = Vector2(0.0, GRAPH_HEIGHT)
	_graph.draw.connect(_draw_graph)
	box.add_child(_graph)
	set_shown(false)


## Show or hide the overlay; hidden, it stops processing so it costs nothing.
func set_shown(on: bool) -> void:
	visible = on
	set_process(on)
	if on:
		_since_refresh = REFRESH  # refresh the text on the very next frame


func _process(delta: float) -> void:
	_frame_ms[_next] = delta * 1000.0
	_next = (_next + 1) % SAMPLES
	_graph.queue_redraw()
	_since_refresh += delta
	if _since_refresh >= REFRESH:
		_since_refresh = 0.0
		_refresh_text()


## Rewrite the stats text from the engine's monitors and the sampled frame times.
func _refresh_text() -> void:
	var worst_ms := 0.0
	for ms in _frame_ms:
		worst_ms = maxf(worst_ms, ms)
	var low_fps := (1000.0 / worst_ms) if worst_ms > 0.0 else 0.0
	_label.text = "\n".join([
		"FPS %d  (low %d)" % [Engine.get_frames_per_second(), int(low_fps)],
		"Frame %.1f / max %.1f ms" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, worst_ms],
		"Physics %.1f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"Draws %d  Objs %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)],
		"Nodes %d  Phys %d" % [
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)],
		"Mem %.1f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
	])


## Draw the frame-time bars oldest → newest, with a reference line at TARGET_MS.
func _draw_graph() -> void:
	var size := _graph.size
	var bar_w := size.x / SAMPLES
	for i in SAMPLES:
		var ms := _frame_ms[(_next + i) % SAMPLES]
		var h := clampf(ms / GRAPH_MAX_MS, 0.0, 1.0) * size.y
		var color := Color(0.4, 0.9, 0.4) if ms <= TARGET_MS else Color(1.0, 0.7, 0.2)
		_graph.draw_rect(Rect2(i * bar_w, size.y - h, maxf(bar_w - 0.5, 1.0), h), color)
	var line_y := size.y * (1.0 - TARGET_MS / GRAPH_MAX_MS)
	_graph.draw_line(Vector2(0.0, line_y), Vector2(size.x, line_y), Color(1, 1, 1, 0.4))
