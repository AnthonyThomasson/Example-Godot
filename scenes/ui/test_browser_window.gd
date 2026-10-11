extends CanvasLayer

## UI domain, test browser window: lists every game test grouped by domain, with a search box (matched
## by the host's `matcher`), the last result per test, and a details
## pane. Play (or double-click / Enter) emits `play_requested`; Back emits `back_requested`; Run all
## emits `run_all_requested` and the host answers with `set_run_status` / `set_results`. Built in code like the other UI windows; it knows nothing of the
## Testing domain — only the descriptor dicts
## (`{ id, path, name, domain, description, tags, requires_von, manual, switches, world, error }`) and
## the `{ id: status }` results it is handed.

signal play_requested(path: String)
signal back_requested
## Run every test (the host spawns the run and reports back through `set_run_status` / `set_results`).
signal run_all_requested
## The search text changed (so the host can restore it next time).
signal filter_changed(text: String)

const STATUS_MARKS := { "PASS": "✓", "FAIL": "✗", "TIMEOUT": "⏱", "SKIPPED": "–" }
const STATUS_COLORS := {
	"PASS": Color(0.45, 0.9, 0.45), "FAIL": Color(1.0, 0.4, 0.35), "TIMEOUT": Color(1.0, 0.6, 0.25),
	"SKIPPED": Color(0.75, 0.75, 0.75),
}

var _tests: Array = []
var _matcher: Callable
var _results: Dictionary = {}
var _search: LineEdit
var _tree: Tree
var _details: RichTextLabel
var _play: Button
var _run_all: Button
var _run_status: Label
var _count: Label


## Build the window over `tests`, marking `results`, with `filter` prefilled and `selected` (a test
## path) highlighted. `matcher(test, text) -> bool` decides which tests a search shows.
func open(tests: Array, results: Dictionary, matcher: Callable, filter := "", selected := "") -> void:
	_tests = tests
	_matcher = matcher
	_results = results
	_build_ui()
	_search.text = filter
	_refresh(selected)
	_search.grab_focus()


## Lay out the header (title, search, count), the list + details split and the buttons.
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	box.add_child(header)
	var title := Label.new()
	title.text = "TESTS"
	title.add_theme_font_size_override("font_size", 56)
	header.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search tests (name, domain, tag)…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.add_theme_font_size_override("font_size", 28)
	_search.text_changed.connect(func(t: String):
		filter_changed.emit(t)
		_refresh(_selected_path()))
	_search.text_submitted.connect(func(_t): _play_selected())
	header.add_child(_search)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 22)
	_count.modulate = Color(1, 1, 1, 0.7)
	header.add_child(_count)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(560, 0)
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.add_theme_font_size_override("font_size", 24)
	_tree.item_selected.connect(_show_details)
	_tree.item_activated.connect(_play_selected)
	split.add_child(_tree)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.custom_minimum_size = Vector2(480, 0)
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_theme_font_size_override("normal_font_size", 22)
	_details.add_theme_font_size_override("bold_font_size", 26)
	split.add_child(_details)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_run_all = Button.new()
	_run_all.text = "Run all"
	_run_all.add_theme_font_size_override("font_size", 28)
	_run_all.pressed.connect(run_all_requested.emit)
	buttons.add_child(_run_all)
	_run_status = Label.new()
	_run_status.add_theme_font_size_override("font_size", 22)
	_run_status.modulate = Color(1, 1, 1, 0.8)
	_run_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_run_status.clip_text = true
	buttons.add_child(_run_status)
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 28)
	back.pressed.connect(back_requested.emit)
	buttons.add_child(back)
	_play = Button.new()
	_play.text = "Play"
	_play.add_theme_font_size_override("font_size", 28)
	_play.pressed.connect(_play_selected)
	buttons.add_child(_play)


## Show the host's run progress / outcome next to the buttons; `running` disables Run all.
func set_run_status(text: String, running := false) -> void:
	_run_status.text = text
	_run_all.disabled = running


## Replace the `{ id: status }` marks (after a run) and redraw the list.
func set_results(results: Dictionary) -> void:
	_results = results
	_refresh(_selected_path())
	_show_details()


## Rebuild the list for the current search, keeping `keep` (a path) selected when it is still shown,
## else selecting the first match.
func _refresh(keep: String) -> void:
	_tree.clear()
	var root := _tree.create_item()
	var groups := {}
	var first: TreeItem = null
	var keep_item: TreeItem = null
	var shown := 0
	for t in _tests:
		if not _matcher.call(t, _search.text):
			continue
		shown += 1
		var domain: String = t["domain"]
		if not groups.has(domain):
			var g := _tree.create_item(root)
			g.set_text(0, domain.to_upper())
			g.set_selectable(0, false)
			g.set_custom_color(0, Color(0.7, 0.75, 0.85))
			groups[domain] = g
		var item := _tree.create_item(groups[domain])
		var status: String = _results.get(t["id"], "")
		var mark: String = STATUS_MARKS.get(status, " ")
		var suffix := ""
		if t.get("manual", false):
			suffix += "  [manual]"
		if t.get("requires_von", false):
			suffix += "  [Von]"
		item.set_text(0, "%s  %s%s" % [mark, t["name"], suffix])
		if STATUS_COLORS.has(status):
			item.set_custom_color(0, STATUS_COLORS[status])
		elif t.get("error", "") != "":
			item.set_custom_color(0, STATUS_COLORS["FAIL"])
		item.set_metadata(0, t)
		if first == null:
			first = item
		if t["path"] == keep:
			keep_item = item
	_count.text = "%d / %d" % [shown, _tests.size()]
	var pick := keep_item if keep_item != null else first
	if pick != null:
		pick.select(0)
		_tree.scroll_to_item(pick)
	else:
		_details.text = "[i]No tests match.[/i]"
	_play.disabled = pick == null


## Fill the details pane for the selected test.
func _show_details() -> void:
	var t := _selected()
	if t.is_empty():
		return
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % t["name"])
	lines.append("[color=#9aa]%s[/color]" % t["id"])
	if t.get("error", "") != "":
		lines.append("[color=#ff6a5a]Script %s[/color]" % t["error"])
	if String(t.get("description", "")) != "":
		lines.append("\n" + String(t["description"]))
	lines.append("")
	lines.append("World: %s" % t.get("world", "?"))
	if not (t.get("tags", []) as Array).is_empty():
		lines.append("Tags: %s" % ", ".join(t["tags"]))
	var switches: Dictionary = t.get("switches", {})
	if not switches.is_empty():
		var parts := PackedStringArray()
		for s in switches:
			parts.append("%s %s" % [s, "on" if switches[s] else "[color=#ff8a7a]off[/color]"])
		lines.append("Switches: %s" % ", ".join(parts))
	if t.get("requires_von", false):
		lines.append("Needs the Von decision server (skipped without one).")
	if t.get("manual", false):
		lines.append("Manual sandbox: play it yourself (WASD, mouse, F, Space).")
	var status: String = _results.get(t["id"], "")
	if status != "":
		lines.append("Last result: %s" % status)
	_details.text = "\n".join(lines)


## Emit `play_requested` for the selected test, if any.
func _play_selected() -> void:
	var path := _selected_path()
	if path != "":
		play_requested.emit(path)


## The selected test's descriptor ({} when none).
func _selected() -> Dictionary:
	var item := _tree.get_selected()
	return item.get_metadata(0) if item != null and item.get_metadata(0) is Dictionary else {}


## The selected test's script path ("" when none).
func _selected_path() -> String:
	return String(_selected().get("path", ""))

