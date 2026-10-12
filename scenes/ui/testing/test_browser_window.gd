extends CanvasLayer

## UI domain, test browser window: lists every game test grouped by domain, with a search box (matched
## by the host's `matcher`), the last result per test, and a details
## pane. Play (or double-click / Enter) emits `play_requested`; Back emits `back_requested`; Run all, or
## the ▶ button on a domain's row, emits `run_requested` and the host answers with `set_run_status` /
## `set_results`. Built in code like the other UI windows; it knows nothing of the
## Testing domain — only the descriptor dicts
## (`{ id, path, name, domain, description, tags, requires_von, manual, switches, world, locked, error }`) and
## the `{ id: status }` results it is handed.
## Each test (not sandbox) row has a checkbox; a domain row's box and the header's "Check shown" button
## tick or clear the tests the search currently shows. "Run N checked" emits `run_queue_requested` with
## the ticked tests' paths for a headed, one-by-one run (the host persists the ticks via `checked_changed`).

signal play_requested(path: String)
signal back_requested
## Run the tests of `domain` — every test when it is "" (the host spawns the run and reports back
## through `set_run_status` / `set_results`).
signal run_requested(domain: String)
## Run the ticked tests one after another in the real (headed) runner: their script paths, in list order.
signal run_queue_requested(paths: Array)
## The set of ticked test ids changed (so the host can restore it next time).
signal checked_changed(ids: Array)
## The search text changed (so the host can restore it next time).
signal filter_changed(text: String)

const RESULT_HUD := preload("res://scenes/ui/testing/test_result_hud.gd")
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
## Ticked test ids (id → true); kept across searches, and stale ids are dropped on `open`.
var _checked: Dictionary = {}
## The tick-able tests the search shows: id → its TreeItem, and domain → [ids].
var _test_items: Dictionary = {}
var _shown_by_domain: Dictionary = {}
var _shown_count := 0
var _check_shown: Button
var _run_checked: Button
## A run is going: Run all and every domain's ▶ are disabled.
var _running := false


## Build the window over `tests`, marking `results`, with `filter` prefilled and `selected` (a test
## path) highlighted and `checked` (test ids) ticked. `matcher(test, text) -> bool` decides which tests a
## search shows.
func open(tests: Array, sandboxes: Array, results: Dictionary, matcher: Callable, filter := "", selected := "", checked: Array = []) -> void:
	_tests = tests
	for t in tests:
		if checked.has(t["id"]) and t.get("error", "") == "":
			_checked[t["id"]] = true
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
	_check_shown = Button.new()
	_check_shown.add_theme_font_size_override("font_size", 24)
	_check_shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_check_shown.pressed.connect(_on_check_shown)
	header.add_child(_check_shown)
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
	_tree.gui_input.connect(_on_tree_input)
	_tree.button_clicked.connect(_on_group_button)
	_tree.item_edited.connect(_on_item_edited)
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
	_run_checked = Button.new()
	_run_checked.add_theme_font_size_override("font_size", 28)
	_run_checked.pressed.connect(func(): run_queue_requested.emit(_checked_paths()))
	buttons.add_child(_run_checked)
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
	_update_buttons()


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
	_test_items.clear()
	_shown_by_domain.clear()
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
			# The mode comes first: changing a cell's mode clears its text.
			g.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			g.set_editable(0, true)
			g.set_text(0, domain.to_upper())
			g.set_selectable(0, false)
			g.set_custom_color(0, Color(0.7, 0.75, 0.85))
			g.set_metadata(0, domain)
			g.add_button(0, _run_icon(), 0, _running, "Run the %d %s tests" % [_runnable_count(domain), domain])
			_groups[domain] = g
		var item := _tree.create_item(_groups[domain])
		if t.get("error", "") == "":
			item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)  # before the text: a mode change clears it
			item.set_editable(0, true)
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
		if t.get("error", "") == "":
			_test_items[t["id"]] = item
			if not _shown_by_domain.has(domain):
				_shown_by_domain[domain] = []
			_shown_by_domain[domain].append(t["id"])
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
	_shown_count = shown
	_sync_checks()
	var pick := keep_item if keep_item != null else first
	if pick != null:
		pick.select(0)
		_tree.scroll_to_item(pick)
	else:
		_details.text = "[i]No tests match.[/i]"
	_play.disabled = pick == null


## A double-click on a test's label opens it. Godot raises `item_activated` for rows without a checkbox (and
## for Enter), but not for a double-click on an editable check cell, so that case is handled here; on the
## checkbox itself a double-click just toggles.
func _on_tree_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click):
		return
	var item := _tree.get_item_at_position(event.position)
	if item != null and item.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK and item.get_metadata(0) is Dictionary \
			and not _over_checkbox(event.position, item):
		play_requested.emit(item.get_metadata(0)["path"])


## Whether tree-local `pos` is over `item`'s checkbox (the left edge of its label cell).
func _over_checkbox(pos: Vector2, item: TreeItem) -> bool:
	var box := _tree.get_theme_icon(&"checked").get_width() + _tree.get_theme_constant(&"h_separation")
	return pos.x < _tree.get_item_area_rect(item, 0).position.x + box


## A checkbox was toggled: a test row ticks itself, a domain row ticks or clears every shown test it holds.
func _on_item_edited() -> void:
	_apply_edit(_tree.get_edited())


## Apply the new state of the checkbox on `item` (the row the user just toggled).
func _apply_edit(item: TreeItem) -> void:
	if item == null:
		return
	var on := item.is_checked(0)
	if item.get_metadata(0) is Dictionary:
		_set_checked([item.get_metadata(0)["id"]], on)
	elif item.get_metadata(0) is String:
		_set_checked(_shown_by_domain.get(item.get_metadata(0), []), on)


## The header button: tick every shown test, or clear them when they are all ticked already.
func _on_check_shown() -> void:
	_set_checked(_test_items.keys(), not _all_shown_checked())


## Tick or clear `ids`, redraw the boxes in place (the list keeps its scroll and selection) and tell the host.
func _set_checked(ids: Array, on: bool) -> void:
	for id in ids:
		if on:
			_checked[id] = true
		else:
			_checked.erase(id)
	_sync_checks()
	checked_changed.emit(_checked.keys())


## Whether at least one test is shown and every shown test is ticked.
func _all_shown_checked() -> bool:
	return not _test_items.is_empty() and _test_items.keys().all(func(id): return _checked.has(id))


## Bring every checkbox, the domain rows' partial state and the buttons in line with `_checked`.
func _sync_checks() -> void:
	for id in _test_items:
		(_test_items[id] as TreeItem).set_checked(0, _checked.has(id))
	for domain in _groups:
		var ids: Array = _shown_by_domain.get(domain, [])
		var ticked := ids.filter(func(id): return _checked.has(id)).size()
		var g: TreeItem = _groups[domain]
		g.set_checked(0, not ids.is_empty() and ticked == ids.size())
		g.set_indeterminate(0, ticked > 0 and ticked < ids.size())
	_update_buttons()


## The header and "Run N checked" buttons' text and enabled state, and the count line.
func _update_buttons() -> void:
	_check_shown.text = "Uncheck shown" if _all_shown_checked() else "Check shown"
	_check_shown.disabled = _test_items.is_empty()
	_run_checked.text = "Run %d checked" % _checked.size()
	_run_checked.disabled = _checked.is_empty() or _running
	_count.text = "%d / %d" % [_shown_count, _tests.size() + _sandboxes.size()] \
		+ ("" if _checked.is_empty() else "  ·  %d checked" % _checked.size())


## The ticked tests' script paths in list order (including ticked tests the search hides).
func _checked_paths() -> Array:
	return _tests.filter(func(t): return _checked.has(t["id"])).map(func(t): return t["path"])


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
	if not (t.get("locked", []) as Array).is_empty():
		lines.append("Locked while it runs: %s" % ", ".join(t["locked"]))
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

