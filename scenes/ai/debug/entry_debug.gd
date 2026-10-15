extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: this NPC's plan for the doorway it is entering (`docs/tactical-entry.md`). The doorway and its
## fatal funnel, the stack slots (each side the stack holds numbered, its own slot ringed), the approach waypoints, the pie arc
## (steps done / to go) and the room points still unseen from outside, the room's corners (red hard / green soft,
## filled once the pie saw them) and the corner it enters to, its gaze, and once the room is clear the doorways on it
## covers (the one it holds bright) or the rear it holds; rooms it regards as cleared are outlined; the views of the doorways its walks keep
## out of (E18) are shaded red. A badge under the
## NPC gives the doorway, role, phase and progress, with timer arcs for the ready wait, the follow gap and the hold.
## Reads the controller's `debug_entry_view()` only.

## Whether to draw the entry plan overlay.
@export var show_entry: bool = false

const DOOR := Color(0.3, 0.9, 1.0)
const FUNNEL := Color(1.0, 0.25, 0.2)
const SLOT := Color(0.6, 0.8, 1.0)
const APPROACH := Color(1.0, 0.9, 0.3)
const PIE := Color(0.75, 0.55, 1.0)
const UNSEEN := Color(1.0, 0.8, 0.25)
const HARD := Color(1.0, 0.3, 0.25)
const SOFT := Color(0.4, 0.95, 0.5)
const GAZE := Color(1.0, 1.0, 1.0)
const COVER := Color(1.0, 0.6, 0.2)
const CLEARED := Color(0.3, 0.9, 1.0)
const VIEW := Color(1.0, 0.35, 0.3)
## How deep (px) the funnel is drawn either side of the wall plane (the tests' `FUNNEL_DEPTH`).
const FUNNEL_DEPTH := 40.0
## Half the angle (rad) of the wedge drawn toward the room beyond a covered doorway.
const COVER_WEDGE := 0.26
const PHASE_NAMES := {
	"approach": "APPROACH", "stack": "STACKED", "pie": "PIE", "cross": "CROSSING", "corner": "CORNER",
	"clear": "CLEARING", "cover": "COVERING", "rear": "REAR SECURITY",
}


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_entry


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	var view: Dictionary = _controller.debug_entry_view()
	if view.is_empty():
		return
	for v in view["guard"]["views"]:
		_door_view(v, bool(view["guard"]["round_views"]))
	for rect in view["guard"]["cleared_rooms"]:
		_cleared_room(rect)
	var e: Dictionary = view["entry"]
	if e.is_empty():
		return
	_doorway(e)
	_stack(e)
	_approach(e)
	_pie(e)
	_corners(e)
	_covering(e)
	_gaze(e)
	_badge(e)


## The view of a doorway the NPC's walks keep out of (E18): a faint red polygon with the doorway's id, bold while the walk goes round the views.
func _door_view(v: Dictionary, round_views: bool) -> void:
	var poly := PackedVector2Array()
	for p in (v["poly"] as PackedVector2Array):
		poly.append(to_local(p))
	if poly.size() < 3:
		return
	draw_colored_polygon(poly, Color(VIEW, 0.2 if round_views else 0.08))
	draw_polyline(PackedVector2Array(Array(poly) + [poly[0]]), Color(VIEW, 0.7 if round_views else 0.35), 1.5)
	_label(v["poly"][0], "view %s" % v["id"], Color(VIEW, 0.7), Vector2(4, -4))


## A cleared room: a cyan outline tagged "cleared".
func _cleared_room(rect: Rect2) -> void:
	var local := Rect2(to_local(rect.position), rect.size)
	draw_rect(local.grow(-6.0), Color(CLEARED, 0.35), false, 2.0)
	_label(rect.position, "cleared", Color(CLEARED, 0.7), Vector2(10, 22))


## The doorway (a thick line across it), its outward normal and the fatal funnel either side of the wall plane.
func _doorway(e: Dictionary) -> void:
	var d: Dictionary = e["door"]
	var pos: Vector2 = d["pos"]
	var along: Vector2 = d["along"]
	var out: Vector2 = d["out"]
	var half: float = float(d["width"]) * 0.5
	var funnel := PackedVector2Array([
		to_local(pos + along * half + out * FUNNEL_DEPTH), to_local(pos - along * half + out * FUNNEL_DEPTH),
		to_local(pos - along * half - out * FUNNEL_DEPTH), to_local(pos + along * half - out * FUNNEL_DEPTH),
	])
	draw_colored_polygon(funnel, Color(FUNNEL, 0.12))
	_line(pos - along * half, pos + along * half, DOOR, 4.0)
	_arrow(pos, pos + out * 30.0, Color(DOOR, 0.7), 1.5)
	# Named on the side away from the stack, clear of the slots and the NPC's badge.
	_label(pos - along * float(e["side"]) * (half + 26.0), "%s › %s" % [e["opening"], e["into"]], DOOR, Vector2(-40, 6))


## The stack slots in use (and the next one free) in the file on each side the stack holds (both, when it is split: E19),
## numbered from the door out; a lone entrant's first slots on the far side, which it slices from too, faint; this NPC's
## slot ringed twice.
func _stack(e: Dictionary) -> void:
	var slots: Dictionary = e["slots"]
	var side: int = e["side"]
	var used := { side: int(e.get("place", e["slot"])) }
	for m in e["team"]:
		var s := int(m["side"]) if int(m["side"]) != 0 else side
		used[s] = maxi(int(used.get(s, 0)), int(m.get("place", m["slot"])))
	for s in used:
		var row: Array = slots.get(s, [])
		for i in mini(int(used[s]) + 1, row.size()):
			draw_circle(to_local(row[i]), 4.0, Color(SLOT, 0.8))
			_label(row[i], str(i + 1), SLOT, Vector2(-4, -8))
	if e["role"] == "solo":
		var far: Array = slots.get(-side, [])
		for i in mini(2, far.size()):
			_ring(far[i], 4.0, Color(SLOT, 0.3), 1.0)
	var mine: Vector2 = e["my_slot"]
	_ring(mine, 9.0, SLOT, 2.0)
	_ring(mine, 13.0, Color(SLOT, 0.5), 1.0)


## The approach: from the NPC through the waypoints still to walk, to its slot.
func _approach(e: Dictionary) -> void:
	if e["phase"] != "approach":
		return
	var pts: Array = [_character.global_position]
	pts.append_array(e["waypoints"])
	pts.append(e["my_slot"])
	for i in range(1, pts.size()):
		_line(pts[i - 1], pts[i], Color(APPROACH, 0.7), 1.5)
	for p in e["waypoints"]:
		draw_circle(to_local(p), 3.0, APPROACH)


## The pie: the arc on the side being sliced (steps done dim, steps to go bright, the current one ringed), the line of
## sight through the doorway, and the room points still unseen from outside.
func _pie(e: Dictionary) -> void:
	var queue: Array = e["pie_queue"]
	var pie: Dictionary = e["pie"]
	for s in pie:
		var arc: Array = pie[s]
		var active: bool = e["phase"] == "pie" and s == int(e["pie_side"])
		for i in range(1, arc.size()):
			_line(arc[i - 1], arc[i], Color(PIE, 0.6 if active else 0.15), 1.5)
		for p in arc:
			var todo := active and queue.has(p)
			draw_circle(to_local(p), 3.0 if todo else 2.0, Color(PIE, 0.95 if todo else 0.3))
	if e["phase"] != "pie":
		return
	for p in e["unseen"]:
		draw_circle(to_local(p), 2.5, Color(UNSEEN, 0.5))
	if not queue.is_empty():
		_ring(queue[0], 8.0, PIE, 2.0)
	var door: Vector2 = e["door"]["pos"]
	var me := _character.global_position
	_line(me, door + (door - me).normalized() * 260.0, Color(PIE, 0.35), 1.0)


## The room's corners: red hard / green soft, filled once seen from outside (by this NPC's own pie: a follower never
## slices one), tagged "hidden" while the pie runs; the corner this NPC enters to, with an arrow from the NPC while it
## crosses or takes it.
func _corners(e: Dictionary) -> void:
	for c in e["corners"]:
		var col := HARD if c["hard"] else SOFT
		var rect := Rect2(to_local(c["pos"]) - Vector2(6, 6), Vector2(12, 12))
		if c["seen"]:
			draw_rect(rect, Color(col, 0.85))
		else:
			draw_rect(rect, Color(col, 0.9), false, 2.0)
			if e["phase"] == "pie":
				_label(c["pos"], "hidden", Color(col, 0.8), Vector2(9, 4))
	var corner: Vector2 = e["corner"]
	if corner == Vector2.INF:
		return
	_ring(corner, 14.0, Color(1, 1, 1, 0.9), 2.0)
	if e["phase"] in ["cross", "corner"]:
		_arrow(_character.global_position, corner, Color(1, 1, 1, 0.7), 1.5)


## Once the room is clear: each doorway on, a line from where it would be covered through it and a wedge into the room
## beyond (the one this NPC holds bright, the rest faint; a lone entrant's sweep numbered), or the rear it holds.
func _covering(e: Dictionary) -> void:
	if e["phase"] == "rear":
		var spot: Vector2 = e["rear_spot"]
		var d: Dictionary = e["door"]
		_ring(spot, 10.0, COVER, 2.0)
		_arrow(spot, (d["pos"] as Vector2) + (d["out"] as Vector2) * 80.0, COVER, 2.0)
		_label(spot, "rear", COVER, Vector2(12, 4))
		return
	if e["phase"] != "cover":
		return
	var sweep: Array = e["sweep"]
	for w in e["watch"]:
		var held: bool = w["id"] == e["covering"] or sweep.has(w["id"])
		var col := Color(COVER, 0.95 if held else 0.25)
		var from: Vector2 = w["spot"] if sweep.is_empty() else _character.global_position
		var pos: Vector2 = w["pos"]
		_line(from, pos, col, 1.5 if held else 1.0)
		var dir := (pos - from).normalized()
		var far := 160.0
		var wedge := PackedVector2Array([to_local(pos),
			to_local(pos + dir.rotated(COVER_WEDGE) * far), to_local(pos + dir.rotated(-COVER_WEDGE) * far)])
		draw_colored_polygon(wedge, Color(COVER, 0.18 if held else 0.05))
		if w["id"] == e["covering"]:
			_ring(w["spot"], 9.0, COVER, 2.0)
		var at := sweep.find(w["id"])
		if at >= 0:
			_label(pos, "look %d" % (at + 1), COVER, Vector2(8, -8))


## Where the NPC is looking (and so where its gun points).
func _gaze(e: Dictionary) -> void:
	var me := _character.global_position
	_line(me, me + (e["gaze"] as Vector2) * 120.0, Color(GAZE, 0.6), 1.5)


## The badge under the NPC: doorway, slot and role, phase and progress; timer arcs for the ready wait, the follow
## gap and the hold.
func _badge(e: Dictionary) -> void:
	var me := _character.global_position
	var phase := str(e["phase"])
	var text := "ENTRY · slot %d %s · %s" % [e["slot"], e["role"], PHASE_NAMES.get(phase, phase.to_upper())]
	if phase == "pie":
		var arc: Array = e["pie"][int(e["pie_side"])]
		text += " %d/%d (side %d/2)" % [arc.size() - (e["pie_queue"] as Array).size(), arc.size(), e["pie_sides"]]
	if phase in ["pie", "cross", "corner", "clear"]:
		text += " · seen %d%%" % roundi(float(e["seen_fraction"]) * 100.0)
	if phase == "cover" and str(e["covering"]) != "":
		text += " %s" % e["covering"]
	_label(me, text, DOOR, Vector2(-60, 58))
	var timers := []
	if float(e["ready_left"]) >= 0.0:
		timers.append(["ready wait %.1fs" % e["ready_left"], float(e["ready_left"]) / maxf(float(e["ready_total"]), 0.01), SLOT])
	if float(e["follow_left"]) >= 0.0:
		timers.append(["follow in %.1fs" % e["follow_left"], float(e["follow_left"]) / maxf(float(e["follow_total"]), 0.01), APPROACH])
	if float(e["hold_left"]) >= 0.0:
		timers.append(["hold %.1fs" % e["hold_left"], float(e["hold_left"]) / maxf(float(e["hold_total"]), 0.01), COVER])
	for i in timers.size():
		var t: Array = timers[i]
		_timer_arc(me, 26.0 + 5.0 * i, clampf(t[1], 0.0, 1.0), t[2], 2.5)
		_label(me, t[0], t[2], Vector2(-60, 76 + 18 * i))
