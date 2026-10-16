extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: what the NPC HEARS and is TOLD. Rings for its hearing and hit-awareness radii; every
## gunfire event it heard as a fading yellow point (an investigation lead); an incoming-fire arrow and
## shot origin while it is under fire; each ally callout heard as a speaker→destination line (with the
## callout range as a ring); and the last callout this NPC radioed itself. Reads the controller's
## `debug_memory()` and `debug_sent_callout()` only.

## Whether to draw the hearing overlay.
@export var show_hearing: bool = false

const HEARING := Color(1.0, 0.85, 0.2)
const UNDER_FIRE := Color(1.0, 0.25, 0.2)
const CALLOUT_IN := Color(0.35, 0.8, 1.0)
const CALLOUT_OUT := Color(1.0, 0.55, 0.9)
## How long (s) a sent-callout marker stays drawn.
const SENT_SHOW := 6.0


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_hearing


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	var mem: Dictionary = _controller.debug_memory()
	if mem.is_empty():
		return
	var me := _character.global_position
	_ring(me, mem.get("hearing_radius", 0.0), Color(HEARING, 0.25), 1.0)
	_ring(me, mem.get("hit_awareness_radius", 0.0), Color(UNDER_FIRE, 0.25), 1.0)
	_label(me + Vector2.RIGHT * mem.get("hearing_radius", 0.0), "hearing", Color(HEARING, 0.6), Vector2(-40, -4))
	var lead_ttl: float = mem.get("lead_memory_ttl", 20.0)
	for g in mem.get("gunfire", []):
		var fade := clampf(1.0 - g["age"] / maxf(lead_ttl, 0.1), 0.2, 1.0)
		draw_circle(to_local(g["pos"]), 5.0, Color(HEARING, fade))
		_ring(g["pos"], 10.0, Color(HEARING, fade * 0.7))
		_label(g["pos"], "shot %.0fs" % g["age"], Color(HEARING, fade))
	var under: Dictionary = mem.get("under_fire", {})
	if not under.is_empty():
		var from: Vector2 = under["from"]
		var origin := me + from * 90.0
		_arrow(origin, me + from * 20.0, UNDER_FIRE, 3.0)
		_label(origin, "under fire%s %.1fs" % [" (hit)" if under.get("hit", false) else "", under["left"]], UNDER_FIRE)
	var range_: float = mem.get("callout_range", 0.0)
	if range_ > 0.0:
		_ring(me, range_, Color(CALLOUT_IN, 0.2), 1.0)
	for c in mem.get("callouts", []):
		_line(c["pos"], c["point"], Color(CALLOUT_IN, 0.7), 1.5)
		draw_circle(to_local(c["point"]), 4.0, CALLOUT_IN)
		_ring(c["pos"], 12.0, CALLOUT_IN)
		_label(c["pos"], "%s: %s (%.0fs)" % [c["name"], c["label"], c["age"]], CALLOUT_IN, Vector2(14, 4))
	var sent: Dictionary = _controller.debug_sent_callout()
	if not sent.is_empty() and (GameClock.msec() - sent["at"]) / 1000.0 <= SENT_SHOW:
		_line(sent["position"], sent["point"], Color(CALLOUT_OUT, 0.7), 2.0)
		_ring(sent["point"], 9.0, CALLOUT_OUT, 2.0)
		_label(sent["position"], "radioed: %s" % sent["label"], CALLOUT_OUT, Vector2(14, -14))
