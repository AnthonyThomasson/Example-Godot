extends Node

## Testing domain: the test browser scene — reached from the setup window's Tests button. Hosts the UI
## domain's browser window over the discovered tests; Play stores the pick and opens the runner, Back
## returns to the main scene. The search text and last results live in Engine metas, so they survive
## the round trip through a test.

const TestCatalog = preload("res://scenes/testing/test_catalog.gd")
const BROWSER_WINDOW := preload("res://scenes/ui/test_browser_window.gd")
const RUNNER_SCENE := "res://scenes/testing/test_runner.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const META_SELECTION := "test_selection"
const META_RESULTS := "test_results"
const META_FILTER := "test_filter"


func _ready() -> void:
	var window: CanvasLayer = BROWSER_WINDOW.new()
	window.name = "TestBrowserWindow"
	add_child(window)
	window.play_requested.connect(_on_play)
	window.back_requested.connect(_on_back)
	window.filter_changed.connect(func(t: String): Engine.set_meta(META_FILTER, t))
	window.open(TestCatalog.discover(), Engine.get_meta(META_RESULTS, {}), TestCatalog.matches,
		String(Engine.get_meta(META_FILTER, "")), String(Engine.get_meta(META_SELECTION, "")))


## Play: remember the pick and open the runner.
func _on_play(path: String) -> void:
	Engine.set_meta(META_SELECTION, path)
	get_tree().change_scene_to_file(RUNNER_SCENE)


## Back: return to the main scene (its setup window).
func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)
