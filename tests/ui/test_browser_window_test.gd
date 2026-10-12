extends GameTest

## The test browser's checkboxes are plain data in, signals out: a test row ticks itself, a domain row and
## the header's "Check shown" button tick (or clear) only the tests the search currently shows, ticks survive
## a search, and "Run N checked" hands back the ticked tests' paths in list order. Driven through the
## window's own handlers; the descriptors here are hand-made.

const Browser := preload("res://scenes/ui/testing/test_browser_window.gd")

var _window: CanvasLayer
var _queued: Array = []
var _checked: Array = []


func describe() -> Dictionary:
	return {
		"name": "Test browser ticks tests, bulk-checks what the search shows and queues them",
		"description": "Test and domain checkboxes and the header button tick only the shown tests; ticks survive a search; Run N checked emits the ticked paths in order.",
		"tags": ["test browser", "ui"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	_window = Browser.new()
	t.world.add_child(_window)
	_window.run_queue_requested.connect(func(paths): _queued = paths)
	_window.checked_changed.connect(func(ids): _checked = ids)
	_window.open(_tests(), [], {}, _matcher, "", "", ["a/one"])

	# The rows keep their labels (a check cell must not lose its text).
	t.check(_item("a/one").get_text(0).contains("Alpha one"), "a test row shows its name")
	t.expect_eq(_group("a").get_text(0), "A", "a domain row shows its name")

	t.expect_eq(_window._checked.keys(), ["a/one"], "the host's ticks are restored")
	t.check(_item("a/one").is_checked(0), "a restored tick shows")
	t.expect_eq(_window._run_checked.text, "Run 1 checked", "the run button counts the ticks")

	# A test row ticks itself.
	_item("a/two").set_checked(0, true)
	_window._apply_edit(_item("a/two"))
	t.expect_eq(_checked, ["a/one", "a/two"], "ticking a test reports the set")
	t.check(_group("a").is_checked(0), "a domain with every test ticked shows ticked")

	# A domain row clears its tests.
	_group("a").set_checked(0, false)
	_window._apply_edit(_group("a"))
	t.check(_checked.is_empty(), "clearing a domain row clears its tests")
	t.check(_window._run_checked.disabled, "nothing ticked leaves Run disabled")

	# Under a search, bulk checks touch only the shown tests.
	_window._search.text = "alpha"
	_window._search.text_changed.emit("alpha")
	t.expect_eq(_window._test_items.keys(), ["a/one"], "the search shows one test")
	t.expect_eq(_window._check_shown.text, "Check shown", "the header offers to tick")
	_window._check_shown.pressed.emit()
	t.expect_eq(_checked, ["a/one"], "the header ticks only the shown test")
	t.expect_eq(_window._check_shown.text, "Uncheck shown", "the header then offers to clear")
	_window._search.text = ""
	_window._search.text_changed.emit("")
	t.check(_item("a/one").is_checked(0), "the tick survives clearing the search")
	t.check(_group("a").is_indeterminate(0), "a partly ticked domain shows partial")
	t.check(not _item("a/two").is_checked(0), "the hidden test stayed clear")

	# A domain row under a search ticks only its shown tests.
	_window._search.text = "beta"
	_window._search.text_changed.emit("beta")
	_group("b").set_checked(0, true)
	_window._apply_edit(_group("b"))
	t.expect_eq(_checked.size(), 2, "the domain row ticked its one shown test")
	t.check(not _window._checked.has("b/two"), "the domain row left its hidden test alone")

	# Run hands back every tick, hidden or not, in list order.
	_window._search.text = ""
	_window._search.text_changed.emit("")
	_window._run_checked.pressed.emit()
	t.expect_eq(_queued, ["res://tests/a/one_test.gd", "res://tests/b/one_test.gd"], "Run emits the ticked paths in list order")

	# Real clicks: the box toggles, a double-click on the label opens the test, one on the box does not.
	var played: Array = []
	var root_window := t.world.get_window()
	var window_size := root_window.size
	root_window.size = Vector2i(1280, 720)  # the headless viewport is too small to lay the list out
	_window.play_requested.connect(func(path): played.append(path))
	await t.frames(4)
	var before: bool = _window._checked.has("b/two")
	await _click(t, "b/two", true, false)
	t.check(_window._checked.has("b/two") != before, "clicking the box toggles the test")
	await _click(t, "b/two", true, true)
	t.check(played.is_empty(), "a double-click on the box does not open the test")
	await _click(t, "b/two", false, false)  # a double-click starts with a click that selects the row
	t.check(played.is_empty(), "a single click on the label only selects")
	await _click(t, "b/two", false, true)
	t.expect_eq(played, ["res://tests/b/two_test.gd"], "a double-click on the label opens the test")
	# A real click on a domain row's box ticks every test it holds.
	_window._set_checked(["a/one", "a/two"], false)
	await t.frames(1)
	var arrow_width: float = _window._tree.get_theme_icon(&"arrow").get_width() + _window._tree.get_theme_constant(&"h_separation")  # the fold arrow sits left of the box
	var group_rect: Rect2 = _window._tree.get_item_area_rect(_group("a"), 0)
	var group_at: Vector2 = _window._tree.get_global_rect().position + group_rect.position \
			+ Vector2(arrow_width + 12.0, group_rect.size.y / 2.0)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = group_at
		event.global_position = group_at
		event.pressed = pressed
		TestContext.inject(event)
		await t.frames(1)
	t.check(_window._checked.has("a/one") and _window._checked.has("a/two"), "clicking a domain row's box ticks its tests")
	root_window.size = window_size

	# A headless run in progress blocks the queue button; a script error cannot be ticked.
	_window.set_run_status("Running…", true)
	t.check(_window._run_checked.disabled, "Run checked waits for a headless run")
	t.check(not _window._checked.has("b/broken"), "a test whose script fails is never ticked")


func _tests() -> Array:
	return [
		_test("a/one", "a", "Alpha one"), _test("a/two", "a", "Gamma two"),
		_test("b/one", "b", "Beta one"), _test("b/two", "b", "Delta two"),
		_test("b/broken", "b", "Beta broken", "failed to load"),
	]


func _test(id: String, domain: String, test_name: String, error := "") -> Dictionary:
	return { "id": id, "path": "res://tests/%s_test.gd" % id, "name": test_name, "domain": domain, "description": "",
		"tags": [], "requires_von": false, "manual": false, "switches": {}, "world": "arena", "error": error }


## Matches when every search word starts the test's name (blank matches all).
func _matcher(entry: Dictionary, text: String) -> bool:
	return text == "" or String(entry["name"]).to_lower().begins_with(text.to_lower())


func _item(id: String) -> TreeItem:
	return _window._test_items[id]


func _group(domain: String) -> TreeItem:
	return _window._groups[domain]


## Left-click the row of test `id` on its checkbox (`box`) or its label, as a double-click when `double`.
func _click(t: TestContext, id: String, box: bool, double: bool) -> void:
	var tree: Tree = _window._tree
	var rect := tree.get_item_area_rect(_item(id), 0)
	var at := tree.get_global_rect().position + rect.position + Vector2(10.0 if box else rect.size.x - 20.0, rect.size.y / 2.0)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		event.double_click = double and pressed
		TestContext.inject(event)
		await t.frames(1)
