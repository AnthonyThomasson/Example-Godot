extends CanvasLayer

## UI domain, test result banner: shown over a game test played from the test browser. While the test
## runs it names it; when it ends it shows the verdict (PASS / FAIL / SKIPPED / TIMEOUT), each check with
## ✓/✗, any logged errors, and Rerun / Back buttons — the world keeps running underneath. Built in code
## like the other HUDs; it knows nothing of the Testing domain, only the descriptor and result dicts it
## is handed.

## Rerun pressed: rebuild and replay the same test.
signal rerun_requested
## Back pressed: return to the test browser.
signal back_requested
## Next pressed during a queued run: skip the pause and start the next test.
signal next_requested
## Pause / Resume pressed: freeze or resume the world under the banner.
signal pause_requested

const STATUS_COLORS := {
	"PASS": Color(0.45, 0.9, 0.45), "FAIL": Color(1.0, 0.4, 0.35), "TIMEOUT": Color(1.0, 0.6, 0.25),
	"SKIPPED": Color(0.75, 0.75, 0.75), "RUNNING": Color(0.6, 0.8, 1.0),
}

var _title: Label
var _status: Label
var _details: RichTextLabel
var _rerun: Button
var _queue_line: Label
var _next: Button
var _pause: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS  # the buttons keep working while the world is paused
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.offset_left = 10.0
	panel.offset_top = 10.0
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_queue_line = Label.new()
	_queue_line.add_theme_font_size_override("font_size", 22)
	_queue_line.modulate = Color(1, 1, 1, 0.7)
	_queue_line.visible = false
	box.add_child(_queue_line)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 34)
	box.add_child(_status)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.fit_content = true
	_details.scroll_active = false
	_details.custom_minimum_size = Vector2(540, 0)
	_details.add_theme_font_size_override("normal_font_size", 20)
	_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_details)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_pause = _button(buttons, "Pause", pause_requested.emit)
	_rerun = _button(buttons, "Rerun", rerun_requested.emit)
	_next = _button(buttons, "Next ▸", next_requested.emit)
	_next.visible = false
	_button(buttons, "Back (Esc)", back_requested.emit)


## A test started: name it (`entry` is a test descriptor dict).
func show_running(entry: Dictionary) -> void:
	_set_status("RUNNING")
	_title.text = "%s  ·  %s" % [entry.get("name", "?"), entry.get("id", "")]
	_details.text = String(entry.get("description", ""))
	_rerun.disabled = true
	_next.disabled = true


## Show or hide the Pause button (a test can lock the interaction).
func set_pause_enabled(on: bool) -> void:
	_pause.visible = on


## Show whether the world is paused: the pause button offers the opposite.
func set_paused(paused: bool) -> void:
	_pause.text = "Resume" if paused else "Pause"


## A queued run is on test `index` of `total` (1-based): show the progress line and Next, hide Rerun.
func show_queue(index: int, total: int) -> void:
	_queue_line.text = "Queue  %d / %d" % [index, total]
	_queue_line.visible = true
	_rerun.visible = false
	_next.visible = true
	_next.disabled = true


## Whether Next may skip the pause (a queued test's verdict is up).
func set_next_ready(ready: bool) -> void:
	_next.disabled = not ready


## The queue finished: show its `summary` and drop Next.
func show_queue_done(summary: String) -> void:
	_queue_line.text = "Queue done  ·  " + summary
	_next.visible = false


## A status line while the test waits on something (e.g. the decision server).
func show_status(text: String) -> void:
	_details.text = text


## The test ended: show `result` (`{ status, name, id, reason, time, checks, logs, manual }`).
func show_result(result: Dictionary) -> void:
	var status: String = result.get("status", "?")
	_set_status("MANUAL" if result.get("manual", false) and status == "PASS" else status)
	_title.text = "%s  ·  %.1fs" % [result.get("name", "?"), float(result.get("time", 0.0))]
	var lines := PackedStringArray()
	if String(result.get("reason", "")) != "":
		lines.append("[i]%s[/i]" % result["reason"])
	for c in result.get("checks", []):
		var mark := "[color=#7be07b]✓[/color]" if c["ok"] else "[color=#ff6a5a]✗[/color]"
		lines.append("%s %s" % [mark, _escape(String(c["message"]))])
	var snapshot: Dictionary = result.get("snapshot", {})
	for id in snapshot.get("actors", {}):
		var a: Dictionary = snapshot["actors"][id]
		lines.append("[color=#9aa7b4]· %s %s  health %s%s[/color]" % [id, a.get("position", ""), a.get("health", "?"), "  " + String(a["act"]) if a.has("act") else ""])
	_details.text = "\n".join(lines)
	_rerun.disabled = false


## Show `status` in its color.
func _set_status(status: String) -> void:
	_status.text = status
	_status.add_theme_color_override("font_color", STATUS_COLORS.get(status, Color.WHITE))


## Add a focus-less button to `parent` that calls `on_press`.
func _button(parent: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep Space/keys for the game underneath
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## Escape BBCode in plain text.
func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
