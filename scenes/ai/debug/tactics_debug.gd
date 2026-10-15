extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain: an optional debug overlay for the NPC's tactical geometry, in two independent aspects. The
## point ZONES (`show_tactics`) are every candidate position its perception laid out for the last
## decision (fire spots, flank sides, ways to advance or retreat, leads, rooms to search, objects), each
## a coloured marker tagged by kind. The ROOM zones (`show_room_zones`) are every room of the house drawn
## as a rectangle tinted by how the NPC regards it now (the room it is in, searched, unsearched, or not
## yet seen) — the room reasoning the search / room / flank points are placed against. It reads the
## sibling GoalController's `debug_zones()` / `debug_room_zones()` through its public API, senses nothing
## and feeds nothing back (the "draw on its own child Node2D" convention, like vision_debug.gd).

## Whether to draw the candidate point zones. Off by default — it is the densest overlay.
@export var show_tactics: bool = false
## Whether to draw the room zones (each room tinted by how the NPC regards it). Off by default.
@export var show_room_zones: bool = false

## Marker colour per zone category (the categories `debug_zones()` tags each point with). A colour is
## drawn once as an in-world label beside its first marker, so the palette reads as a legend.
const ZONE_COLORS := {
	&"fire": Color(1.0, 0.3, 0.2),       # red — a spot to shoot the hostile from
	&"flank": Color(1.0, 0.6, 0.1),      # orange — a side to take around it
	&"advance": Color(1.0, 0.9, 0.2),    # yellow — a point part-way in, closing on it
	&"retreat": Color(0.3, 0.6, 1.0),    # blue — somewhere to fall back to
	&"lead": Color(0.8, 0.4, 1.0),       # purple — an investigation lead (last seen / gunfire)
	&"search": Color(0.5, 0.9, 0.5),     # green — a room or unexplored area to search
	&"entry": Color(0.2, 0.9, 0.9),      # cyan — a stack slot beside a doorway to enter a room by
	&"room": Color(0.4, 0.8, 0.8),       # teal — a known room to go to
	&"interaction": Color(0.9, 0.9, 0.9),# white — an object to use
	&"waypoint": Color(0.9, 0.3, 0.8),   # magenta — a non-room go-to (starting post / entrance / approach)
}
## Outline / tint colour per room status (how the NPC regards each room), from `debug_room_zones()`.
const ROOM_COLORS := {
	&"current": Color(1.0, 0.85, 0.2),   # gold — the room the NPC is standing in
	&"searched": Color(0.4, 0.8, 0.5),   # green — seen and searched recently
	&"unsearched": Color(0.95, 0.5, 0.2),# orange — seen but not searched (a place to search)
	&"unknown": Color(0.5, 0.5, 0.6),    # grey — not yet seen at all
}
## Radius (px) of a zone's translucent disc.
const ZONE_RADIUS := 15.0
## Radius (px) of the solid dot at a zone's exact point.
const DOT_RADIUS := 3.0
## Inset (px) of a room's tag from its top-left corner.
const ROOM_LABEL_INSET := 6.0

var _focus := Vector2.INF   ## A tactical point the inspector asked to highlight, or INF for none.


## Whether either toggle is on, or the inspector has a point highlighted (its ring draws with both off).
func _on() -> bool:
	return show_tactics or show_room_zones or _focus != Vector2.INF


## Draw the room zones (behind) then the candidate point zones (in front), then the highlighted point.
func _paint() -> void:
	if show_room_zones and _controller.has_method("debug_room_zones"):
		_draw_room_zones()
	if show_tactics and _controller.has_method("debug_zones"):
		_draw_point_zones()
	if _focus != Vector2.INF:
		_draw_focus()


## Draw each room as a rectangle tinted and outlined by how the NPC regards it (current / searched /
## unsearched / unknown), with its type + status tagged in the corner — so the room reasoning the
## tactical points are placed against is visible, and the colours read as a legend.
func _draw_room_zones() -> void:
	var font: Font = ThemeDB.fallback_font
	for room in _controller.debug_room_zones():
		var status: StringName = room["status"]
		var color: Color = ROOM_COLORS.get(status, Color.WHITE)
		var rect: Rect2 = room["rect"]
		var local := Rect2(to_local(rect.position), rect.size)
		draw_rect(local, Color(color, 0.08), true)
		draw_rect(local, color, false, 2.0)
		DebugText.string(self, font, local.position + Vector2(ROOM_LABEL_INSET, ROOM_LABEL_INSET + FONT_SIZE),
			"%s · %s" % [room["type"], String(status)], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


## Highlight the inspector's clicked tactical point with a bright double ring, so which point the detail
## panel describes is unmistakable. Set via `set_focus` / cleared via `clear_focus`.
func _draw_focus() -> void:
	var p := to_local(_focus)
	draw_arc(p, ZONE_RADIUS + 5.0, 0.0, TAU, 24, Color.WHITE, 2.0)
	draw_arc(p, ZONE_RADIUS + 8.0, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 1.0)


## Highlight the tactical point at world `point` (the inspector's clicked zone).
func set_focus(point: Vector2) -> void:
	_focus = point
	queue_redraw()


## Clear the highlighted tactical point.
func clear_focus() -> void:
	_focus = Vector2.INF
	queue_redraw()


## Draw each candidate zone as a translucent disc + outline + a dot at its exact point, and label each
## category once (beside its first marker) so the colours read as a legend.
func _draw_point_zones() -> void:
	var font: Font = ThemeDB.fallback_font
	var labelled := {}
	for zone in _controller.debug_zones():
		var category: StringName = zone["category"]
		var color: Color = ZONE_COLORS.get(category, Color.WHITE)
		var p := to_local(zone["point"] as Vector2)
		draw_circle(p, ZONE_RADIUS, Color(color, 0.18))
		draw_arc(p, ZONE_RADIUS, 0.0, TAU, 20, color, 1.0)
		draw_circle(p, DOT_RADIUS, color)
		if not labelled.has(category):
			labelled[category] = true
			DebugText.string(self, font, p + Vector2(ZONE_RADIUS + 2.0, FONT_SIZE * 0.4), String(category),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
