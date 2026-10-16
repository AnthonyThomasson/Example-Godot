extends Node2D

## UI domain: the squad-leaders debug overlay (`docs/leadership.md` LD12), a global toggle of the overlay bar (`OverlayRegistry.LEADERS`,
## `show_leaders`, off by default). A crown over each side's leader, in any match (a played one or Watch / Endless), so who leads, and who
## leads next once a leader falls, can be seen. Main builds one under the match's `World` node (world space), drawn at
## `DrawLayers.ABOVE` (interface 11) so a character never hides its crown.
##
## A decoupled observer like the order markers: `watch(views)` takes the squads' `view()` callables (`{ leader, members }`, interface
## 21), polled each frame while shown; it reads the leader through the Character API only (`global_position`, `is_dead`).
## `PROCESS_MODE_ALWAYS`: the crown stays on the leader while the match is paused.

const CROWN_COLOR := Color(1.0, 0.82, 0.25, 0.95)
## How far above the body the crown floats, and its size.
const LIFT := 30.0
const SIZE := 9.0

## Whether the crowns are drawn (the overlay bar's `show_leaders`).
var show_leaders := false:
	set(on):
		show_leaders = on
		queue_redraw()

var _views: Array = []        ## The squads' `view()` callables.
var _drawn: Array = []        ## What is drawn now: `{ point, node }` per leader.


func _init() -> void:
	z_index = DrawLayers.ABOVE  # Over the floor and the standing world.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Watch the squads through their `view()` callables.
func watch(views: Array) -> void:
	_views = views.duplicate()


## What is drawn right now: `[{ point, node }]`, one per living leader; [] while hidden.
func drawn() -> Array:
	return _drawn


func _process(_delta: float) -> void:
	var now := _crowns() if show_leaders else []
	if now != _drawn:
		_drawn = now
		queue_redraw()


## A crown on each squad's living leader.
func _crowns() -> Array:
	var out: Array = []
	for view_of in _views:
		var view: Dictionary = view_of.call() if view_of is Callable and (view_of as Callable).is_valid() else {}
		var leader = view.get("leader")
		if leader is Node2D and is_instance_valid(leader) and leader.get("is_dead") != true:
			out.append({ "point": leader.global_position, "node": leader })
	return out


func _draw() -> void:
	for c: Dictionary in _drawn:
		var top := to_local(c["point"]) + Vector2(0, -LIFT)
		var crown := PackedVector2Array([top + Vector2(-SIZE, SIZE * 0.6), top + Vector2(-SIZE, -SIZE * 0.4),
			top + Vector2(-SIZE * 0.5, 0), top + Vector2(0, -SIZE), top + Vector2(SIZE * 0.5, 0),
			top + Vector2(SIZE, -SIZE * 0.4), top + Vector2(SIZE, SIZE * 0.6)])
		draw_colored_polygon(crown, CROWN_COLOR)
		draw_polyline(crown + PackedVector2Array([crown[0]]), Color(0, 0, 0, 0.8), 1.5)
