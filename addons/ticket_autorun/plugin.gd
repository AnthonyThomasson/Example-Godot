@tool
extends EditorPlugin

## Editor tooling (outside the game domains): shows which worktree this editor is open on (a label in the
## editor toolbar, also printed once) and, when the editor was started by `tools/editor.sh --autorun`
## (`GAME_AUTORUN` set), runs the main scene once the editor has finished its first scan.

## Toolbar label naming the worktree.
var _label: Label


func _enter_tree() -> void:
	var worktree := _worktree_name()
	print("[worktree] editor open on '%s'" % worktree)
	_label = Label.new()
	_label.text = "Worktree: %s" % worktree
	_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	add_control_to_container(CONTAINER_TOOLBAR, _label)
	if OS.get_environment("GAME_AUTORUN").is_empty():
		return
	# Deferred a beat so the first filesystem scan finishes before the game is launched.
	get_tree().create_timer(2.0).timeout.connect(_play, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	if _label:
		remove_control_from_container(CONTAINER_TOOLBAR, _label)
		_label.queue_free()


## The worktree's name: `GAME_TICKET` (set by `tools/editor.sh`), else the project directory's name.
func _worktree_name() -> String:
	var named := OS.get_environment("GAME_TICKET").strip_edges()
	if named.is_empty():
		named = ProjectSettings.globalize_path("res://").trim_suffix("/").get_file()
	return named


## Run the project's main scene in the editor, once.
func _play() -> void:
	print("[worktree] autorun: playing the main scene")
	EditorInterface.play_main_scene()
