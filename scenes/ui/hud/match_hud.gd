extends CanvasLayer

## UI domain, spectator-match observer: the HUD for an N-AI contest (defenders vs invaders).
## Across the top is a running match timer; top-left is a goal readout listing every NPC's goal;
## along the bottom a shared combat feed; and, once one side dies, the winner banner.
##
## It is a decoupled observer, reading only published contracts — the Character public API/signals
## (`faction`, the `died` signal), the AI controller's exported `goal`, and
## the EventBus `&"hit"` topic — so it never reaches into any domain's internals.
## Main calls `begin()` with the combatants when it sets up a match (and again for each new one in an
## endless run). `match_ended` tells Main the verdict, so it never has to work out a winner itself.

## Emitted once per match when it is decided: `verdict` is the banner text ("DEFENDER WINS", "TIME UP - DRAW", …).
signal match_ended(verdict: String)

const _MAX_FEED := 6                ## Combat-feed lines kept on screen (newest last).

const HudProbe := preload("res://scenes/ui/hud/hud_probe.gd")

var _combatants: Array = []        ## [{ character, controller }] for each side.
var _elapsed: float = 0.0          ## Match time so far (s); stops once decided.
var _end_ms: int = -1              ## When it was decided; -1 while ongoing (freezes the timer).
var _verdict: String = ""          ## Winner banner text once decided.
var _feed: Array[String] = []      ## Recent combat-feed lines.
var _time_limit: float = 0.0       ## Seconds before an undecided match is called a draw; 0 = no limit.
var _countdown: String = ""        ## Footer line under the verdict (e.g. the next-match countdown).

var _timer_label: Label           ## Top-centre running match time.
var _verdict_label: Label         ## Centre winner banner, empty until the match is decided.
var _feed_label: Label            ## Bottom-left combat feed.
var _goal_label: Label            ## Top-left per-NPC goal readout.
var _countdown_label: Label       ## Under the verdict banner; blank unless Main set a countdown.


## Begin observing a match between `combatants` (character nodes). Builds the UI, wires each side's
## death signal, and subscribes to the combat feed. Safe to call again for a new match: the previous
## match's UI, combatants, feed and verdict are dropped first. A `time_limit` > 0 calls a match still
## undecided after that many seconds a draw. `show_details` off leaves just the timer and the result
## (no goal readout or combat feed), for a match a human is playing in: those would spoil what the AI
## is thinking and crowd the player's own panel.
func begin(combatants: Array, time_limit := 0.0, show_details := true) -> void:
	for c in get_children():
		c.queue_free()
	_combatants.clear()
	_feed.clear()
	_verdict = ""
	_countdown = ""
	_end_ms = -1
	_time_limit = time_limit
	_elapsed = 0.0
	_build_ui()
	_goal_label.visible = show_details
	_feed_label.visible = show_details
	for i in combatants.size():
		var c: Node = combatants[i]
		_combatants.append({ "character": c, "controller": HudProbe.controller_of(c) })
		if c.has_signal("died"):
			c.died.connect(_on_died.bind(c))
	if not EventBus.posted.is_connected(_on_event):
		EventBus.posted.connect(_on_event)


## Show `text` under the verdict banner (blank clears it). Main uses it for the next-match countdown.
func set_countdown(text: String) -> void:
	_countdown = text


func _process(delta: float) -> void:
	if _combatants.is_empty():
		return
	if _end_ms < 0:
		_elapsed += delta  # frame time, so pausing the tree (Space) also pauses the clock and the limit
		if _time_limit > 0.0 and _elapsed >= _time_limit:
			_decide("TIME UP - DRAW")
	_timer_label.text = "MATCH  %.1fs" % _elapsed
	_verdict_label.text = _verdict
	_countdown_label.text = _countdown
	_feed_label.text = "\n".join(_feed)
	var goal_lines: Array[String] = []
	for entry in _combatants:
		var c: Node = entry["character"]
		if not is_instance_valid(c):
			continue
		var ctrl = entry["controller"]
		var goal: String = str(ctrl.goal_text()) if ctrl and ctrl.has_method("goal_text") else "—"
		goal_lines.append("%s: %s" % [c.name, goal])
	_goal_label.text = "\n".join(goal_lines)


## Record the outcome when a combatant dies. The match waits until the victim's whole faction is
## eliminated before declaring a result — a single death does not end a multi-NPC side. Once a faction
## is down, all surviving combatants are checked: if they share one faction that faction wins (by name
## for a 1v1, by faction label for a larger match); no survivors or survivors from multiple factions is
## a draw.
func _on_died(victim: Node) -> void:
	if _end_ms >= 0:
		return
	var victim_faction = victim.get("faction") if "faction" in victim else null
	for entry in _combatants:
		var c: Node = entry["character"]
		if c != victim and is_instance_valid(c) and c.get("is_dead") != true \
				and c.get("faction") == victim_faction:
			return  # Victim's faction still has living members; match continues.
	var survivors: Array = []
	for entry in _combatants:
		var c: Node = entry["character"]
		if is_instance_valid(c) and c.get("is_dead") != true:
			survivors.append(c)
	if survivors.is_empty():
		_decide("DRAW")
		return
	var wf = survivors[0].get("faction") if "faction" in survivors[0] else null
	if not survivors.all(func(c): return c.get("faction") == wf):
		_decide("DRAW")
	elif survivors.size() == 1:
		_decide("%s WINS" % str(survivors[0].name))
	else:
		_decide("%s WINS" % str(wf).to_upper())


## Fix the result: freeze the timer, show `verdict` and tell the observers (once).
func _decide(verdict: String) -> void:
	if _end_ms >= 0:
		return
	_end_ms = Time.get_ticks_msec()
	_verdict = verdict
	match_ended.emit(verdict)


## Append a line to the combat feed for each damaging hit (EventBus `&"hit"` — the same event the AI
## consumes), keeping only the most recent few.
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic != &"hit":
		return
	var attacker := _name_of(data.get("attacker"), data.get("source"))
	var victim := _name_of(data.get("victim"), null)
	_feed.append("%s -> %s  %.0f dmg" % [attacker, victim, float(data.get("damage", 0.0))])
	while _feed.size() > _MAX_FEED:
		_feed.pop_front()


## A readable name for a hit participant, falling back through an alternate node then "?".
func _name_of(primary: Variant, fallback: Variant) -> String:
	for n in [primary, fallback]:
		if n is Node and is_instance_valid(n):
			return str(n.name)
	return "?"


# --- UI construction (labels anchored like the debug HUD; no scene-side layout) ----------

## Build the shared chrome: the top timer, top-left goal readout, the centre verdict banner, and the
## bottom combat feed.
func _build_ui() -> void:
	_timer_label = _add_label(0.5, 0.0, Vector2(-130, 16), Vector2(260, 52), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_goal_label = _add_label(0.0, 0.0, Vector2(24, 76), Vector2(560, 280), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	# Span the left half of the screen (right edge at the centre line, small gap) and wrap onto more lines.
	_goal_label.anchor_right = 0.5
	_goal_label.offset_right = -8.0
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict_label = _add_label(0.5, 0.4, Vector2(-350, 0), Vector2(700, 88), 62, Color.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown_label = _add_label(0.5, 0.4, Vector2(-350, 96), Vector2(700, 48), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_feed_label = _add_label(0.0, 1.0, Vector2(24, -250), Vector2(520, 240), 28, Color.ORANGE, HORIZONTAL_ALIGNMENT_LEFT)


## Create and return a Label anchored at (`ax`,`ay`) with the given offset, size, font size, colour
## and horizontal alignment.
func _add_label(ax: float, ay: float, pos: Vector2, size: Vector2, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	add_child(label)
	label.anchor_left = ax
	label.anchor_right = ax
	label.anchor_top = ay
	label.anchor_bottom = ay
	label.offset_left = pos.x
	label.offset_top = pos.y
	label.offset_right = pos.x + size.x
	label.offset_bottom = pos.y + size.y
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
