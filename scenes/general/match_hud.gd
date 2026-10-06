extends CanvasLayer

## General domain, spectator-match observer: the HUD for a 2-AI contest (defender vs invader). For
## each combatant it shows the goal, current act, faction and a health bar; across the top a running
## match timer; along the bottom a shared combat feed; and, once one side dies, the winner banner.
##
## It is a decoupled observer, reading only published contracts — the Character public API/signals
## (`faction`, `health`/`max_health`, the `died` signal), the AI controller's `current_act()` and
## exported `goal`, and the EventBus `&"hit"` topic — so it never reaches into any domain's internals.
## Main calls `begin()` with the two combatants when it sets up spectator mode.

const _MAX_FEED := 6                ## Combat-feed lines kept on screen (newest last).

var _combatants: Array = []        ## [{ character, controller, label }] for each side.
var _start_ms: int = 0             ## When the match started (for the timer).
var _end_ms: int = -1              ## When it was decided; -1 while ongoing (freezes the timer).
var _verdict: String = ""          ## Winner banner text once decided.
var _feed: Array[String] = []      ## Recent combat-feed lines.

var _timer_label: Label           ## Top-centre running match time.
var _verdict_label: Label         ## Centre winner banner, empty until the match is decided.
var _feed_label: Label            ## Bottom-left combat feed.


## Begin observing a match between `combatants` (character nodes). Builds the UI, wires each side's
## death signal, and subscribes to the combat feed. Called by Main in spectator mode.
func begin(combatants: Array) -> void:
	_start_ms = Time.get_ticks_msec()
	_build_ui()
	for i in combatants.size():
		var c: Node = combatants[i]
		_combatants.append({ "character": c, "controller": _controller_of(c), "label": _make_panel(i) })
		if c.has_signal("died"):
			c.died.connect(_on_died.bind(c))
	if not EventBus.posted.is_connected(_on_event):
		EventBus.posted.connect(_on_event)


func _process(_delta: float) -> void:
	if _combatants.is_empty():
		return
	var now := _end_ms if _end_ms >= 0 else Time.get_ticks_msec()
	_timer_label.text = "MATCH  %.1fs" % ((now - _start_ms) / 1000.0)
	for entry in _combatants:
		entry["label"].text = _panel_text(entry)
	_verdict_label.text = _verdict
	_feed_label.text = "\n".join(_feed)


## The text block for one combatant panel: name/faction, health bar, current act, and goal.
func _panel_text(entry: Dictionary) -> String:
	var c: Node = entry["character"]
	if not is_instance_valid(c):
		return ""
	var ctrl = entry["controller"]
	var faction: String = str(c.faction) if "faction" in c else "?"
	var hp: float = c.health if "health" in c else 0.0
	var max_hp: float = c.max_health if "max_health" in c else 0.0
	var act: String = ctrl.current_act() if ctrl and ctrl.has_method("current_act") else "?"
	var goal: String = str(ctrl.goal) if ctrl and "goal" in ctrl else ""
	var state := "DEAD" if c.get("is_dead") == true else _health_bar(hp, max_hp)
	return "%s  [%s]\n%s\nact: %s\ngoal: %s" % [c.name, faction, state, act, goal]


## A compact text health bar, e.g. "[######----] 30/50".
func _health_bar(hp: float, max_hp: float) -> String:
	if max_hp <= 0.0:
		return "HP %.0f" % hp
	var filled := int(round(clampf(hp / max_hp, 0.0, 1.0) * 10.0))
	return "[%s%s] %.0f/%.0f" % ["#".repeat(filled), "-".repeat(10 - filled), hp, max_hp]


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
	_end_ms = Time.get_ticks_msec()
	var survivors: Array = []
	for entry in _combatants:
		var c: Node = entry["character"]
		if is_instance_valid(c) and c.get("is_dead") != true:
			survivors.append(c)
	if survivors.is_empty():
		_verdict = "DRAW"
		return
	var wf = survivors[0].get("faction") if "faction" in survivors[0] else null
	if not survivors.all(func(c): return c.get("faction") == wf):
		_verdict = "DRAW"
	elif survivors.size() == 1:
		_verdict = "%s WINS" % str(survivors[0].name)
	else:
		_verdict = "%s WINS" % str(wf).to_upper()


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


## The AI controller child of `character` (the node with `control`), or null (e.g. for the player).
func _controller_of(character: Node) -> Node:
	for child in character.get_children():
		if child.has_method("control"):
			return child
	return null


# --- UI construction (labels anchored like the debug HUD; no scene-side layout) ----------

## Build the shared chrome: the top timer, the centre verdict banner, and the bottom combat feed.
func _build_ui() -> void:
	_timer_label = _add_label(0.5, 0.0, Vector2(-100, 16), Vector2(200, 36), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_verdict_label = _add_label(0.5, 0.4, Vector2(-300, 0), Vector2(600, 60), 44, Color.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_feed_label = _add_label(0.0, 1.0, Vector2(24, -180), Vector2(420, 170), 18, Color.ORANGE, HORIZONTAL_ALIGNMENT_LEFT)


## One combatant panel: left side for the first combatant, right side for the second. Word-wrap is
## on so long goal strings fold within the 380 px width rather than overflowing off-screen.
func _make_panel(index: int) -> Label:
	var label: Label
	if index == 0:
		label = _add_label(0.0, 0.0, Vector2(24, 60), Vector2(380, 200), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		label = _add_label(1.0, 0.0, Vector2(-404, 60), Vector2(380, 200), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	label.autowrap_mode = 3  # TextServer.AUTOWRAP_WORD_ARBITRARY
	label.max_lines_visible = 7
	return label


## Create and return a Label anchored at (`ax`,`ay`) with the given offset, size, font size, colour
## and horizontal alignment.
func _add_label(ax: float, ay: float, pos: Vector2, size: Vector2, font_size: int, color: Color, align: int) -> Label:
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
