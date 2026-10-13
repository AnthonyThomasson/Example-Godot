extends GameTest

## A domain with topic folders (`tests/ai/entry/`) shows one row per topic under its domain row: the row ticks only its own
## tests, the domain row goes indeterminate while some of its tests are ticked, a topic row has no ▶ button (so a headless run
## starting or ending touches only the domain rows and logs nothing), and a GAP result shows its own mark. Driven through the
## window's own handlers with hand-made descriptors.

const Browser := preload("res://scenes/ui/testing/test_browser_window.gd")

var _window: CanvasLayer
var _checked: Array = []


func describe() -> Dictionary:
	return {
		"name": "Test browser groups a domain's tests by topic folder",
		"description": "A topic row sits under its domain, ticks only its tests, has no run button, and a GAP result gets its mark.",
		"tags": ["test browser", "ui"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	_window = Browser.new()
	t.world.add_child(_window)
	_window.checked_changed.connect(func(ids): _checked = ids)
	_window.open(_tests(), [], {}, func(_entry, _text): return true, "", "", [])

	var topic: TreeItem = _window._groups["a/x"]
	var domain: TreeItem = _window._groups["a"]
	t.expect_eq(topic.get_text(0), "x", "a topic row shows the folder name")
	t.check(topic.get_parent() == domain, "the topic row sits under its domain row")
	t.check(_window._groups["a/y"].get_parent() == domain, "a second topic gets its own row under the same domain")
	t.check(not _window._groups.has("b/") and _window._groups["b"].get_child_count() == 1, "a test with no topic hangs straight under its domain")
	t.check(domain.get_button_count(0) > 0 and topic.get_button_count(0) == 0, "only the domain row has the run button")

	# Ticking a topic row ticks only its tests; the domain row is then partly ticked.
	topic.set_checked(0, true)
	_window._apply_edit(topic)
	t.expect_eq(_checked, ["a/one", "a/two"], "ticking a topic row ticks only that topic's tests")
	t.check(domain.is_indeterminate(0), "the domain row is indeterminate with some of its tests ticked")
	t.check(not _window._groups["a/y"].is_checked(0), "the other topic stays clear")
	_window._groups["a/y"].set_checked(0, true)
	_window._apply_edit(_window._groups["a/y"])
	t.check(domain.is_checked(0) and not domain.is_indeterminate(0), "every test of the domain ticked shows the domain ticked")

	# A run starting and ending touches only the domain rows (an engine error would fail the test).
	_window.set_run_status("Running…", true)
	t.check(domain.is_button_disabled(0, 0), "a headless run disables the domain's run button")
	_window.set_run_status("", false)
	t.check(not domain.is_button_disabled(0, 0), "and enables it again")

	# A GAP result has its mark.
	_window.set_results({ "a/one": "GAP", "a/two": "PASS" })
	t.check(_window._test_items["a/one"].get_text(0).begins_with("○"), "a GAP test shows the ○ mark")
	t.check(_window._test_items["a/two"].get_text(0).begins_with("✓"), "a passing test shows the ✓ mark")


func _tests() -> Array:
	return [
		_test("a/one", "a", "x", "Alpha one"), _test("a/two", "a", "x", "Alpha two"),
		_test("a/three", "a", "y", "Alpha three"), _test("b/one", "b", "", "Beta one"),
	]


func _test(id: String, domain: String, category: String, test_name: String) -> Dictionary:
	return { "id": id, "path": "res://tests/%s_test.gd" % id, "name": test_name, "domain": domain, "category": category, "description": "",
		"tags": [], "requires_von": false, "manual": false, "switches": {}, "world": "arena", "error": "" }
