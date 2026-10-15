extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: where a move / interact / hold is actually going. The requested destination versus
## the navmesh-snapped point it really steers to (red when the nav agent says the target is unreachable),
## the room a room-entry move is waiting to enter, the object an interact walks to or uses (with the
## dwell countdown), the hostile a hold watches, and the leads it has already checked. Reads the
## controller's `debug_combat()` and `debug_memory()` only.

## Whether to draw the targets overlay.
@export var show_targets: bool = false

const REQUESTED := Color(0.8, 0.8, 0.8)
const SNAPPED := Color(0.4, 0.9, 0.9)
const UNREACHABLE := Color(1.0, 0.3, 0.3)
const OBJECT := Color(1.0, 0.85, 0.3)
const WATCH := Color(0.8, 0.5, 1.0)


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_targets


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	var c: Dictionary = _controller.debug_combat()
	if c.is_empty():
		return
	var me := _character.global_position
	var prim := str(c["primitive"])
	var req = c.get("requested_point")
	var snapped_to = c.get("point")
	if req != null and snapped_to != null and prim in ["move", "engage"]:
		var reachable: bool = c["reachable"]
		var col := SNAPPED if reachable else UNREACHABLE
		_line(me, snapped_to, Color(col, 0.35), 1.0)
		draw_circle(to_local(snapped_to), 5.0, col)
		_ring(snapped_to, 11.0, col, 2.0)
		var moved: float = (req as Vector2).distance_to(snapped_to)
		if moved > 4.0:
			# The requested point was off the navmesh (inside furniture / a wall): show the snap.
			draw_circle(to_local(req), 3.0, REQUESTED)
			_line(req, snapped_to, Color(REQUESTED, 0.6), 1.0)
		var tag := ("arrived" if c["arrived"] else "→ destination") if reachable else "UNREACHABLE"
		if str(c["arrive_room"]) != "":
			tag += " · until in room"
		_label(snapped_to, tag, col, Vector2(14, 4))
	var obj = c.get("object_pos")
	if obj != null:
		_line(me, obj, Color(OBJECT, 0.6), 1.5)
		_ring(obj, 14.0, OBJECT, 2.0)
		if c["in_interaction"]:
			_timer_arc(obj, 19.0, c["interaction_timer"] / maxf(c["interaction_dwell"], 0.01), OBJECT)
			_label(obj, "using %.1fs" % c["interaction_timer"], OBJECT, Vector2(20, 4))
		else:
			_label(obj, "walking to use", OBJECT, Vector2(20, 4))
	var watch = c.get("watch_pos")
	if watch != null:
		_line(me, watch, Color(WATCH, 0.5), 1.0)
		_ring(watch, 10.0, WATCH)
		_label(watch, "watching", WATCH, Vector2(14, 4))
	var checked: Array = _controller.debug_memory().get("checked_leads", [])
	if not checked.is_empty():
		_label(me, "%d leads checked" % checked.size(), Color(1, 1, 1, 0.55), Vector2(-30, 76))
