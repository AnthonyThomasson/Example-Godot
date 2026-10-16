extends Node2D

## UI domain: the order markers (`docs/leadership.md` LD12, D5), what the human leader sees of its squad: each living member's order
## target (a line from the member to the doorway it stacks on or the room it defends, the target ringed and named, with the member's
## latest progress), and a ring round each teammate selected in the command menu. Who leads is the squad-leaders debug overlay's
## (`ui/overlays/leader_overlay.gd`). Main builds it only when the human leads, under the match's `World` node (world space), drawn at
## `DrawLayers.ABOVE` (interface 11) so a character never hides its marker.
##
## A decoupled observer like the stack markers: `watch(view)` takes the squad's `view()` callable (`{ leader, members: [{ node, order,
## step }] }`, an order carrying its target point `pos`), polled each frame; `set_selection(nodes)` is the command menu's selection. It
## reads the members through the Character API only (`global_position`, `is_dead`). An order that is done is no longer drawn; one the
## member refused is drawn in red. `PROCESS_MODE_ALWAYS`: the selection changes while the menu holds the tree paused.

const ORDER_COLOR := Color(0.45, 0.85, 1.0, 0.8)
const REFUSED_COLOR := Color(1.0, 0.35, 0.3, 0.85)
const SELECTED_COLOR := Color(0.35, 1.0, 0.55, 0.9)
## The order target's ring, and the selection ring round a body.
const TARGET_RADIUS := 12.0
const SELECTED_RADIUS := 22.0
const FONT_SIZE := 16
## The dashes of the line from a member to its target (px).
const DASH := 10.0

var _view: Callable           ## The squad's `view()`; invalid = nothing watched.
var _selection: Array = []    ## The teammates selected in the command menu.
var _drawn: Array = []        ## What is drawn now: `{ kind, point, node?, from?, label?, refused? }`.


func _init() -> void:
	z_index = DrawLayers.ABOVE  # Over the floor and the standing world.
	process_mode = Node.PROCESS_MODE_ALWAYS  # The selection is made while the command menu holds the tree paused.


## Watch the squad through its `view()` callable.
func watch(view: Callable) -> void:
	_view = view


## The teammates to ring as selected ([] for none).
func set_selection(nodes: Array) -> void:
	_selection = nodes.duplicate()


## What is drawn right now: `[{ kind, point, node }]`, `kind` `order` (a member's order target: `point` the target, `node` the member)
## or `selected` (a selected teammate, where it stands).
func drawn() -> Array:
	return _drawn


func _process(_delta: float) -> void:
	var now := _markers()
	if now != _drawn:
		_drawn = now
		queue_redraw()


## The markers of the view and the selection as they stand.
func _markers() -> Array:
	var out: Array = []
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	for row: Dictionary in view.get("members", []):
		var member = row.get("node")
		var order: Dictionary = row.get("order", {})
		var step := String(row.get("step", ""))
		if not _alive(member) or order.is_empty() or step == "done" or not order.get("pos") is Vector2:
			continue
		out.append({ "kind": "order", "point": order["pos"], "node": member, "from": member.global_position,
			"label": _label_of(order, step), "refused": step == "refused" })
	for mate in _selection:
		if _alive(mate):
			out.append({ "kind": "selected", "point": mate.global_position, "node": mate })
	return out


## The words at an order's target: what it is and how it goes ("Stack (stun) · moving").
func _label_of(order: Dictionary, step: String) -> String:
	var what := "Defend"
	if String(order.get("kind", "")) == "stack":
		what = "Stack (stun)" if bool(order.get("bang", false)) else "Stack (quiet)"
	return what if step == "" else "%s · %s" % [what, step.replace("_", " ")]


## Whether `n` is a living character.
func _alive(n) -> bool:
	return n is Node2D and is_instance_valid(n) and n.get("is_dead") != true


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var labelled := {}  # One label per target point, however many members share it.
	for m: Dictionary in _drawn:
		var at := to_local(m["point"])
		match String(m["kind"]):
			"order":
				var color := REFUSED_COLOR if m["refused"] else ORDER_COLOR
				var from := to_local(m["from"])
				_dashed(from, at, color)
				draw_arc(at, TARGET_RADIUS, 0.0, TAU, 24, color, 2.5)
				if not labelled.has(at):
					labelled[at] = true
					var text: String = m["label"]
					var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
					var text_at := at + Vector2(-size.x * 0.5, -TARGET_RADIUS - 6.0)
					draw_string_outline(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color(0, 0, 0, 0.9))
					draw_string(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(color, 1.0))
			"selected":
				draw_arc(at, SELECTED_RADIUS, 0.0, TAU, 32, SELECTED_COLOR, 3.0)


## A dashed line from `a` to `b`.
func _dashed(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dir := (b - a) / length
	var d := 0.0
	while d < length:
		draw_line(a + dir * d, a + dir * minf(d + DASH, length), color, 2.0)
		d += DASH * 2.0
