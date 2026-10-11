extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: what the NPC knows about OTHER characters. For every contact in its memory it draws a
## ghost at the last-KNOWN position — green ring for a non-hostile, red for a hostile with the reason it is
## hostile — fading as the sighting ages toward `lead_memory_ttl`, with a facing arrow, a velocity arrow,
## a wound pip and a sight line while the NPC sees it right now. Hostiles it has lost track of get a dashed
## heading line to where it would have got to (the investigation lead the snapshot offers). Reads the
## controller's `known_contacts_for_display()`, `debug_memory()` and `debug_state()` only.

## Whether to draw the contacts overlay.
@export var show_contacts: bool = false

const HOSTILE := Color(1.0, 0.3, 0.25)
const FRIENDLY := Color(0.4, 0.85, 0.5)
const LOST := Color(0.75, 0.45, 1.0)
const GHOST_RADIUS := 14.0


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_contacts


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	if not _controller.has_method("known_contacts_for_display"):
		return
	var mem := _read("debug_memory")
	var ttl: float = mem.get("lead_memory_ttl", 20.0)
	var live_ttl: float = mem.get("contact_memory_ttl", 4.0)
	var reasons := {}
	for c in _read("debug_state").get("contacts", []):
		reasons[c["name"]] = c.get("reason", "")
	for c in _controller.known_contacts_for_display():
		var pos: Vector2 = c["pos"]
		var age: float = c["age"]
		var fade := clampf(1.0 - age / maxf(ttl, 0.1), 0.15, 1.0)
		var base := HOSTILE if c["hostile"] else FRIENDLY
		var col := Color(base, fade)
		var stale: bool = age > live_ttl
		if c["visible"]:
			_line(_character.global_position, pos, Color(base, 0.35), 1.0)
		_ring(pos, GHOST_RADIUS, col, 2.0 if not stale else 1.0)
		draw_circle(to_local(pos), 3.0, col)
		var facing: Vector2 = c.get("facing", Vector2.ZERO)
		if facing != Vector2.ZERO:
			_arrow(pos, pos + facing * 26.0, Color(1, 1, 1, fade * 0.7), 1.5)
		var vel: Vector2 = c.get("vel", Vector2.ZERO)
		if vel.length() > 5.0:
			_arrow(pos, pos + vel.limit_length(120.0) * 0.4, Color(1.0, 0.85, 0.2, fade), 1.5)
		if c.get("wound_dmg", 0.0) > 0.0:
			draw_circle(to_local(pos) + Vector2(GHOST_RADIUS, -GHOST_RADIUS), 3.5, Color(0.9, 0.1, 0.1, fade))
		var tag: String = str(c["name"])
		if c["hostile"]:
			tag += " [%s]" % str(reasons.get(c["name"], "hostile"))
		tag += " %.1fs%s" % [age, "" if not stale else " (stale)"]
		_label(pos, tag, col, Vector2(GHOST_RADIUS + 2, 4))
	# Hostiles it has lost track of: where they were, and the heading it would extrapolate them along.
	var cap: float = mem.get("extrapolate_cap", 3.0)
	for l in mem.get("lost", []):
		var pos: Vector2 = l["pos"]
		var vel: Vector2 = l["vel"]
		if vel.length() > 5.0:
			var ahead: float = minf(l["age"], cap)
			_line(pos, pos + vel * ahead, Color(LOST, 0.7), 1.5)
			draw_circle(to_local(pos + vel * ahead), 3.0, Color(LOST, 0.7))
		_label(pos, "lost %s" % l["name"], Color(LOST, 0.8), Vector2(GHOST_RADIUS + 2, -8))
