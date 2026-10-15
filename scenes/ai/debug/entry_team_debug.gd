extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: the team and the entry guard, as this NPC knows them (`docs/tactical-entry.md` E2, E6, E8, E9).
## While it enters: each ally's claim on the doorway off the radio (from where it last radioed to its stack slot,
## tagged with its slot and step, and the doorway on it covers once the room is clear), the order the stack crosses
## in, and who the point is still waiting for. Whatever it does: the entry guard's view of the walk — the next
## doorway into an uncleared room on it and how far (cyan once within the guard's range, where the walk will be paused
## for an entry), a running detour with the order it paused, and the doorways the guard is leaving alone for a while.
## Reads the controller's `debug_entry_view()` only.

## Whether to draw the entry team & guard overlay.
@export var show_entry_team: bool = false

const ALLY := Color(0.55, 0.85, 1.0)
const THROUGH := Color(0.4, 0.95, 0.5)
const WAITING := Color(1.0, 0.75, 0.3)
const GUARD := Color(0.3, 0.9, 1.0)
const BEYOND := Color(0.7, 0.7, 0.7)
const PAUSED := Color(0.85, 0.6, 1.0)


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_entry_team


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	var view: Dictionary = _controller.debug_entry_view()
	if view.is_empty():
		return
	var e: Dictionary = view["entry"]
	if not e.is_empty():
		_team(e)
	_guard(view["guard"], not e.is_empty())


## Each ally's claim: a line from where it radioed to its slot, `slot N · step` (the slots are the order the stack
## crosses in), the doorway on it covers; and who the point is still waiting for.
func _team(e: Dictionary) -> void:
	var slots: Dictionary = e["slots"]
	var doors := {}
	for w in e["watch"]:
		doors[w["id"]] = w["pos"]
	for m in e["team"]:
		var step := str(m["step"])
		var col := THROUGH if m.get("through", false) else (WAITING if step == "claim" else ALLY)
		var at: Vector2 = m["pos"]
		var side: int = m["side"] if int(m["side"]) != 0 else int(e["side"])
		var row: Array = slots.get(side, slots.get(int(e["side"]), []))
		if not row.is_empty() and int(m["slot"]) >= 1:
			var slot_at: Vector2 = row[clampi(int(m["slot"]) - 1, 0, row.size() - 1)]
			_line(at, slot_at, Color(col, 0.4), 1.0)
		_ring(at, 12.0, col, 2.0)
		_label(at, "%s · slot %d · %s" % [m["name"], m["slot"], step.replace("_", " ")], col, Vector2(14, -14))
		var covers := str(m.get("covering", ""))
		if covers != "" and doors.has(covers):
			_arrow(at, doors[covers], Color(col, 0.7), 1.5)
	var me := _character.global_position
	var waiting: Array = e["waiting_for"]
	if not waiting.is_empty() and e["phase"] in ["stack", "pie"]:
		var text := "waiting for: " + ", ".join(waiting)
		if float(e["ready_left"]) >= 0.0:
			text += " · %.1fs" % e["ready_left"]
		_label(me, text, WAITING, Vector2(-60, -46))


## The entry guard: the next doorway into an uncleared room on the walk (cyan within `range`, grey beyond), a running
## detour and the order it paused, and the doorways it is leaving alone.
func _guard(g: Dictionary, entering: bool) -> void:
	var me := _character.global_position
	var ahead: Dictionary = g["ahead"]
	if not entering and not ahead.is_empty():
		var within: bool = float(ahead["dist"]) <= float(g["range"])
		var col := GUARD if within else BEYOND
		_arrow(me, ahead["pos"], Color(col, 0.8), 2.0 if within else 1.0)
		_ring(ahead["pos"], 16.0, col, 2.0)
		_label(ahead["pos"], "%s › %s · %d px%s" % [ahead["opening"], ahead["into"], roundi(float(ahead["dist"])),
			" · ENTRY HERE" if within else ""], col, Vector2(18, 4))
	if g["detour"]:
		_label(me, "GUARD: entering before %s" % g["resume_label"], PAUSED, Vector2(-60, -82))
		var resume: Vector2 = g["resume_point"]
		if resume != Vector2.INF:
			_dashed(me, resume, PAUSED)
			_ring(resume, 10.0, PAUSED, 1.5)
			_label(resume, "paused order", PAUSED, Vector2(14, 4))
	var y := 94.0
	for r in g["rearm"]:
		_label(me, "guard off %s · %.1fs" % [r["opening"], r["left"]], BEYOND, Vector2(-60, y))
		y += 18.0


## A dashed line between two world points.
func _dashed(a: Vector2, b: Vector2, color: Color) -> void:
	draw_dashed_line(to_local(a), to_local(b), Color(color, 0.7), 1.5, 8.0)
