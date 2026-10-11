extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: whether the NPC is making progress. A fading trail of its recent positions, and a
## ring under it that fills as it fails to progress while trying to move — green while moving freely,
## shifting to red once it has been stalled (pushing into a wall or a heavy piece, wedged) for a while.
## Reads the controller's `debug_progress()` only; nothing reacts to the stall.

## Whether to draw the stuck overlay.
@export var show_stuck: bool = false

const FREE := Color(0.4, 0.9, 0.5)
const STUCK := Color(1.0, 0.25, 0.2)
## Seconds stalled at which the ring is fully red.
const STUCK_FULL := 3.0
const RING_RADIUS := 20.0


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_stuck


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	var p := _read("debug_progress")
	if p.is_empty():
		return
	var trail: Array = p["trail"]
	for i in range(1, trail.size()):
		var a := float(i) / trail.size()
		_line(trail[i - 1], trail[i], Color(FREE, 0.15 + 0.5 * a), 1.5)
	var stalled: float = p["stalled_for"]
	var t := clampf(stalled / STUCK_FULL, 0.0, 1.0)
	var col := FREE.lerp(STUCK, t)
	_ring(_character.global_position, RING_RADIUS, Color(col, 0.6), 1.5)
	if stalled > 0.0:
		_timer_arc(_character.global_position, RING_RADIUS + 4.0, t, STUCK, 3.0)
		_label(_character.global_position, "stalled %.1fs" % stalled, STUCK, Vector2(-26, 94))
