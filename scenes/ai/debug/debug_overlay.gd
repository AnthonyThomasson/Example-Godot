extends Node2D

## AI domain, debug: the shared base of the draw-only overlays (contacts / hearing / combat / territory /
## targets / brain / routes / stuck). Each subclass declares its own `@export var show_<x>` toggle (found
## by property name, like the older overlays), overrides `_on()` to report it and `_paint()` to draw, and
## reads only the sibling GoalController's public `debug_*` getters — it senses nothing and feeds nothing
## back. The base finds the controller and character, runs PROCESS_MODE_ALWAYS so it keeps drawing while
## the tree is paused, and redraws every frame only while its toggle is on.

const DebugText := preload("res://scenes/ai/debug/debug_text.gd")

const FONT_SIZE := 16

## The GoalController to read from (a sibling under the NPC).
@export var controller_path: NodePath = NodePath("../GoalController")

var _controller: Node  ## The GoalController read for the overlay's data.
var _character: Node2D ## The NPC body this overlay is a child of.


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_character = get_parent() as Node2D
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _on():
		queue_redraw()


func _draw() -> void:
	if not _on() or _controller == null or _character == null or _character.get("is_dead") == true:
		return
	_paint()


## Whether this overlay's toggle is on. Subclasses return their `show_<x>` flag.
func _on() -> bool:
	return false


## Draw the overlay. Called only while the toggle is on and the NPC is alive; subclasses override.
func _paint() -> void:
	pass


## A small text label at world point `world` (drawn in this node's local space).
func _label(world: Vector2, text: String, color: Color, offset := Vector2(6, -6)) -> void:
	DebugText.string(self, ThemeDB.fallback_font, to_local(world) + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


## A ring (circle outline) of world radius `radius` around world point `world`.
func _ring(world: Vector2, radius: float, color: Color, width := 1.5) -> void:
	draw_arc(to_local(world), radius, 0.0, TAU, 40, color, width)


## A line between two world points.
func _line(a: Vector2, b: Vector2, color: Color, width := 1.5) -> void:
	draw_line(to_local(a), to_local(b), color, width)


## An arrow from world point `a` toward `b` with a small head.
func _arrow(a: Vector2, b: Vector2, color: Color, width := 2.0) -> void:
	var la := to_local(a)
	var lb := to_local(b)
	draw_line(la, lb, color, width)
	var dir := (lb - la).normalized()
	if dir == Vector2.ZERO:
		return
	var head := 7.0
	draw_line(lb, lb - dir.rotated(0.45) * head, color, width)
	draw_line(lb, lb - dir.rotated(-0.45) * head, color, width)


## A pie-style countdown arc around world point `world`: `fraction` (0..1) of a full circle, from the top.
func _timer_arc(world: Vector2, radius: float, fraction: float, color: Color, width := 3.0) -> void:
	if fraction <= 0.0:
		return
	draw_arc(to_local(world), radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(fraction, 0.0, 1.0), 24, color, width)
