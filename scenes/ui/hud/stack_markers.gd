extends Node2D

## UI domain: the stack markers (ticket #41). While the human's stack radio (the AI domain's `PlayerStack`) holds a reserved
## slot, this draws the slots of that doorway on the floor, numbered from the door out: the human's own highlighted, the
## ones the AI holds dimmer, a free one faint. Nothing is drawn without a reservation. A decoupled observer like the
## contact markers: it polls the watched node's `view()` (`{ slots: [{ n, point, mine, held }], ... }`) and never writes.
##
## Added under the match's `World` node (world space), so the positions map straight to the floor. Main builds it and
## calls `watch` with the player's stack.

const RING_RADIUS := 15.0
const FONT_SIZE := 18
## Colour of the human's own slot, of one an AI holds, and of one nobody holds.
const COLOR_MINE := Color(0.35, 1.0, 0.45)
const COLOR_HELD := Color(0.62, 0.72, 0.9)
const COLOR_FREE := Color(0.62, 0.72, 0.9)
const ALPHA_MINE := 0.95
const ALPHA_HELD := 0.5
const ALPHA_FREE := 0.25

var _stack: Node = null
var _slots: Array = []   ## The slots now drawn: { n, point, mine, held }.


## Watch the human's stack (anything with `view()`).
func watch(stack: Node) -> void:
	_stack = stack
	z_index = 1   # Above the floor and the furniture's shadows, under the characters' bodies' labels.


## The slots drawn right now, as `{ n, point, mine, held }`, empty with no reservation.
func drawn() -> Array:
	return _slots


func _process(_delta: float) -> void:
	var slots: Array = []
	if _stack != null and is_instance_valid(_stack):
		slots = (_stack.view() as Dictionary).get("slots", [])
	if slots != _slots:
		_slots = slots.duplicate(true)
		queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for s in _slots:
		var at: Vector2 = s["point"]
		var mine: bool = s["mine"]
		var base := COLOR_MINE if mine else (COLOR_HELD if s["held"] else COLOR_FREE)
		base.a = ALPHA_MINE if mine else (ALPHA_HELD if s["held"] else ALPHA_FREE)
		if mine:
			draw_circle(at, RING_RADIUS, Color(base, 0.22))
		draw_arc(at, RING_RADIUS, 0.0, TAU, 24, base, 3.0 if mine else 2.0)
		var label := str(int(s["n"]))
		var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
		var text_at := at + Vector2(-size.x * 0.5, FONT_SIZE * 0.35)
		draw_string_outline(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color(0, 0, 0, 0.9))
		draw_string(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(base, 1.0))
