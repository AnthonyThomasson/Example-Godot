extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: the NPC's fight as it runs. The engaged target's last-KNOWN position (a crosshair),
## the committed fire/cover destination, the aim line, the fire line (green = clear shot in range, red =
## blocked / out of range) with the fire-cooldown arc, the punch and shoot range rings, and the
## peek-and-cover phase (peek orange / cover blue, with the duck countdown) or the ambush badge. Reads the
## controller's `debug_combat()` only.

## Whether to draw the combat overlay.
@export var show_combat: bool = false

const TARGET := Color(1.0, 0.3, 0.25)
const CLEAR := Color(0.4, 0.95, 0.45)
const BLOCKED := Color(1.0, 0.35, 0.3)
const PEEK := Color(1.0, 0.6, 0.2)
const COVER := Color(0.4, 0.65, 1.0)
const DEST := Color(0.9, 0.9, 0.3)


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_combat


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	var c: Dictionary = _controller.debug_combat()
	if c.is_empty():
		return
	var me := _character.global_position
	var phase: String = c.get("combat_phase", "")
	var style: String = str(c.get("style", ""))
	var col := COVER if phase == "cover" else PEEK
	if c.get("engaged", false):
		var tp: Vector2 = c["engage_pos"]
		var clear: bool = c["fire_clear"]
		_line(me, tp, Color(CLEAR if clear else BLOCKED, 0.7), 2.0 if clear else 1.0)
		_ring(tp, 12.0, TARGET, 2.0)
		draw_line(to_local(tp) + Vector2(-18, 0), to_local(tp) + Vector2(18, 0), TARGET, 1.5)
		draw_line(to_local(tp) + Vector2(0, -18), to_local(tp) + Vector2(0, 18), TARGET, 1.5)
		var why := "clear shot" if clear else ("line blocked" if c["in_range"] else "out of range")
		_label(tp, "target · %s" % why, TARGET, Vector2(16, -4))
		if str(c["primitive"]) == "melee" or c["punch_range"] > 0.0:
			_ring(tp, c["punch_range"], Color(TARGET, 0.35), 1.0)
	_ring(me, c["shoot_range"], Color(PEEK, 0.18), 1.0)
	var aim: Vector2 = c["aim_point"]
	if aim != Vector2.ZERO and aim.distance_to(me) > 1.0:
		_arrow(me, me + (aim - me).normalized() * 44.0, Color(1, 1, 1, 0.55), 1.5)
	var dest = c.get("combat_dest")
	if dest != null:
		_line(me, dest, Color(DEST, 0.5), 1.0)
		draw_rect(Rect2(to_local(dest) - Vector2(5, 5), Vector2(10, 10)), col, false, 2.0)
		_label(dest, "%s spot" % ("cover" if phase == "cover" else "firing"), col, Vector2(8, -6))
	if phase != "":
		_timer_arc(me, 22.0, c["cover_timer"] / maxf(c["cover_time"], 0.01) if phase == "cover" else 0.0, COVER)
	var cooldown: float = c["fire_timer"]
	if cooldown > 0.0:
		_timer_arc(me, 27.0, cooldown / maxf(c["fire_cooldown"], 0.01), TARGET, 2.0)
	if style == "ambush":
		_label(me, "AMBUSH", COVER, Vector2(-22, 40))
	elif phase != "":
		_label(me, "peek" if phase == "peek" else "cover", col, Vector2(-14, 40))
	if c.get("reloading", false):
		_label(me, "RELOADING", COVER, Vector2(-30, 84))
