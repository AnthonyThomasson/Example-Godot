extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: the territorial leash. Outlines the house (the union of the rooms), shows whether the
## NPC is holding ground (`hold_ground` — it will not chase an outside contact out) and whether the
## engaged contact was last seen inside or outside, and marks every tactical zone that sits outside the
## house (the ones a territorial NPC filters out). Reads the controller's `debug_combat()`,
## `debug_room_zones()` and `debug_zones()` only.

## Whether to draw the territory overlay.
@export var show_territory: bool = false

const INSIDE := Color(0.4, 0.85, 0.5)
const OUTSIDE := Color(1.0, 0.5, 0.3)
const HOLD := Color(0.4, 0.65, 1.0)


func _on() -> bool:
	return show_territory


func _paint() -> void:
	var rooms: Array = _controller.debug_room_zones() if _controller.has_method("debug_room_zones") else []
	if rooms.is_empty():
		return
	var bounds: Rect2 = rooms[0]["rect"]
	for r in rooms:
		bounds = bounds.merge(r["rect"])
		draw_rect(Rect2(to_local(r["rect"].position), r["rect"].size), Color(INSIDE, 0.06), true)
	draw_rect(Rect2(to_local(bounds.position), bounds.size), Color(INSIDE, 0.5), false, 2.0)
	_label(bounds.position, "house", INSIDE, Vector2(4, -6))
	var c := _read("debug_combat")
	var holding: bool = c.get("hold_ground", false)
	var me := _character.global_position
	var me_inside := rooms.any(func(r): return (r["rect"] as Rect2).has_point(me))
	_label(me, "%s%s" % ["inside" if me_inside else "outside", " · HOLDING GROUND" if holding else ""],
		HOLD if holding else (INSIDE if me_inside else OUTSIDE), Vector2(-30, 64))
	if c.get("engaged", false):
		var tp: Vector2 = c["engage_pos"]
		var inside: bool = c["engage_inside"]
		_ring(tp, 18.0, INSIDE if inside else OUTSIDE, 2.0)
		_label(tp, "target %s" % ("inside" if inside else "outside"), INSIDE if inside else OUTSIDE, Vector2(20, 14))
		if holding:
			_line(me, tp, Color(HOLD, 0.5), 1.0)
	# Zones outside the house: what a territorial NPC would drop from its combat options.
	if _controller.has_method("debug_zones"):
		for z in _controller.debug_zones():
			if not z.get("tags", {}).get("inside", true):
				var p: Vector2 = z["point"]
				_line(p + Vector2(-6, -6), p + Vector2(6, 6), OUTSIDE, 2.0)
				_line(p + Vector2(-6, 6), p + Vector2(6, -6), OUTSIDE, 2.0)
