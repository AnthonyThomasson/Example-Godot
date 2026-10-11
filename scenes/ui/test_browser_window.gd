extends CanvasLayer

## UI domain, test browser window: lists every game test grouped by domain, with a search box (matched
## by the host's `matcher`), the last result per test, and a details
## pane. Play (or double-click / Enter) emits `play_requested`; Back emits `back_requested`; Run all, or
## the ▶ button on a domain's row, emits `run_requested` and the host answers with `set_run_status` /
## `set_results`. Built in code like the other UI windows; it knows nothing of the
## Testing domain — only the descriptor dicts
## (`{ id, path, name, domain, description, tags, requires_von, manual, switches, world, error }`) and
## the `{ id: status }` results it is handed.

signal play_requested(path: String)
signal back_requested
## Run the tests of `domain` — every test when it is "" (the host spawns the run and reports back
## through `set_run_status` / `set_results`).
signal run_requested(domain: String)
## The search text changed (so the host can restore it next time).
signal filter_changed(text: String)

const RESULT_HUD := preload("res://scenes/ui/test_result_hud.gd")
const STATUS_MARKS := { "PASS": "✓", "FAIL": "✗", "TIMEOUT": "⏱", "SKIPPED": "–" }
## Side of the ▶ run button's icon on a domain row, in pixels.
const RUN_ICON_SIZE := 22

static var _icon_cache: Texture2D = null

var _tests: Array = []
## Hand-played sandboxes: their own section below the tests, never part of a run.
var _sandboxes: Array = []
var _matcher: Callable
var _results: Dictionary = {}
var _search: LineEdit
var _tree: Tree
var _details: RichTextLabel
var _play: Button
var _run_all: Button
var _run_status: Label
var _count: Label
## The current list's domain rows (domain → TreeItem), each carrying a ▶ button.
var _groups: Dictionary = {}
## A run is going: Run all and every domain's ▶ are disabled.
var _running := false


## Build the window over `tests`, marking `results`, with `filter` prefilled and `selected` (a test
## path) highlighted. `matcher(test, text) -> bool` decides which tests a search shows.
func open(tests: Array, sandboxes: Array, results: Dictionary, matcher: Callable, filter := "", selected := "") -> void:
	_tests = tests
	_sandboxes = sandboxes
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
	_tree.button_clicked.connect(_on_group_button)
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
	_run_all.pressed.connect(run_requested.emit.bind(""))
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


## Show the host's run progress / outcome next to the buttons; `running` disables Run all and the
## domain ▶ buttons.
func set_run_status(text: String, running := false) -> void:
	_run_status.text = text
	_run_all.disabled = running
	if running != _running:
		_running = running
		for g: TreeItem in _groups.values():
			g.set_button_disabled(0, 0, running)


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
	_groups.clear()
	var first: TreeItem = null
	var keep_item: TreeItem = null
	var shown := 0
	for t in _tests:
		if not _matcher.call(t, _search.text):
			continue
		shown += 1
		var domain: String = t["domain"]
		if not _groups.has(domain):
			var g := _tree.create_item(root)
			g.set_text(0, domain.to_upper())
			g.set_selectable(0, false)
			g.set_custom_color(0, Color(0.7, 0.75, 0.85))
			g.set_metadata(0, domain)
			g.add_button(0, _run_icon(), 0, _running, "Run the %d %s tests" % [_runnable_count(domain), domain])
			_groups[domain] = g
		var item := _tree.create_item(_groups[domain])
		var status: String = _results.get(t["id"], "")
		var mark: String = STATUS_MARKS.get(status, " ")
		var suffix := ""
		if t.get("requires_von", false):
			suffix += "  [Von]"
		item.set_text(0, "%s  %s%s" % [mark, t["name"], suffix])
		if RESULT_HUD.STATUS_COLORS.has(status):
			item.set_custom_color(0, RESULT_HUD.STATUS_COLORS[status])
		elif t.get("error", "") != "":
			item.set_custom_color(0, RESULT_HUD.STATUS_COLORS["FAIL"])
		item.set_metadata(0, t)
		if first == null:
			first = item
		if t["path"] == keep:
			keep_item = item
	var sandbox_group: TreeItem = null
	for t in _sandboxes:
		if not _matcher.call(t, _search.text):
			continue
		shown += 1
		if sandbox_group == null:
			sandbox_group = _tree.create_item(root)
			sandbox_group.set_text(0, "SANDBOXES  (play by hand, not tests)")
			sandbox_group.set_selectable(0, false)
			sandbox_group.set_custom_color(0, Color(0.85, 0.75, 0.5))
		var sandbox_item := _tree.create_item(sandbox_group)
		sandbox_item.set_text(0, "    " + String(t["name"]))
		sandbox_item.set_metadata(0, t)
		if first == null:
			first = sandbox_item
		if t["path"] == keep:
			keep_item = sandbox_item
	_count.text = "%d / %d" % [shown, _tests.size() + _sandboxes.size()]
	var pick := keep_item if keep_item != null else first
	if pick != null:
		pick.select(0)
		_tree.scroll_to_item(pick)
	else:
		_details.text = "[i]No tests match.[/i]"
	_play.disabled = pick == null


## A domain row's ▶ was clicked: ask the host to run that domain (ignored while a run is going).
func _on_group_button(item: TreeItem, _column: int, _id: int, mouse_button: int) -> void:
	if mouse_button == MOUSE_BUTTON_LEFT and not _running and item.get_metadata(0) is String:
		run_requested.emit(item.get_metadata(0))


## How many of `domain`'s tests a run will execute, whatever the search shows.
func _runnable_count(domain: String) -> int:
	return _tests.filter(func(t): return t["domain"] == domain).size()


## The ▶ icon for a domain's run button: a green right-pointing triangle, drawn once.
static func _run_icon() -> Texture2D:
	if _icon_cache == null:
		var size := RUN_ICON_SIZE
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var color: Color = RESULT_HUD.STATUS_COLORS["PASS"]
		for y in size:
			# The triangle's right edge narrows linearly from the full width at the middle row to a point at the ends.
			var reach := int(size * (1.0 - absf((y + 0.5) / size - 0.5) * 2.0))
			for x in reach:
				img.set_pixel(x, y, color)
		_icon_cache = ImageTexture.create_from_image(img)
	return _icon_cache


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
		lines.append("Sandbox: play it yourself (WASD, mouse, F, Space).")
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

