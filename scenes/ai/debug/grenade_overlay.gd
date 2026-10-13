extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: the NPC's GRENADE awareness (docs/grenades.md G19). Each live grenade it knows of is a dot with its danger
## radius ringed round it, a label (kind, fuse left, how it knows of it) and a countdown arc; the safe spot it is running to is
## a green ring with a line to it; and a planned throw is an arc from the thrower's hand to the landing spot with the grenade's
## danger radius round that. Reads the controller's `debug_grenades()` only.

## Whether to draw the grenade overlay.
@export var show_grenades: bool = false

const KNOWN := Color(1.0, 0.5, 0.15)
const ESCAPE := Color(0.35, 0.9, 0.5)
const THROW := Color(1.0, 0.85, 0.3)
## How high (px) the drawn arc of a planned throw bows over its straight line.
const ARC_HEIGHT := 36.0
const ARC_POINTS := 20


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_grenades


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	var g := _read("debug_grenades")
	if g.is_empty():
		return
	var me := _character.global_position
	for k: Dictionary in g.get("known", []):
		var point: Vector2 = k["point"]
		_ring(point, float(k["radius"]), Color(KNOWN, 0.55), 1.5)
		draw_circle(to_local(point), 4.0, KNOWN)
		_timer_arc(point, 12.0, float(k["fuse_left"]) / maxf(float(k["fuse"]), 0.01), KNOWN, 3.0)
		_label(point, "%s %.1fs (%s)" % [str(k["kind"]), float(k["fuse_left"]), str(k["source"])], KNOWN, Vector2(16, -8))
	var escape: Vector2 = g.get("escape", Vector2.INF)
	if escape != Vector2.INF:
		_line(me, escape, Color(ESCAPE, 0.7), 2.0)
		_ring(escape, 14.0, ESCAPE, 2.5)
		_label(escape, "escape", ESCAPE, Vector2(16, 4))
	var plan: Dictionary = g.get("throw", {})
	if not plan.is_empty():
		var from: Vector2 = plan["from"]
		var to: Vector2 = plan["to"]
		_arc(from, to)
		_ring(to, float(plan["radius"]), Color(THROW, 0.6), 1.5)
		draw_circle(to_local(to), 4.0, THROW)
		_label(to, "throw: %s" % str(plan["kind"]), THROW, Vector2(16, -8))


## The lob of a planned throw from `from` to `to`: a polyline bowed over the straight line, and an arrow head at the landing.
func _arc(from: Vector2, to: Vector2) -> void:
	var lift := (to - from).orthogonal().normalized() * -ARC_HEIGHT
	var previous := from
	for i in range(1, ARC_POINTS + 1):
		var t := float(i) / ARC_POINTS
		var p := from.lerp(to, t) + lift * sin(PI * t)
		_line(previous, p, Color(THROW, 0.9), 2.0)
		previous = p
