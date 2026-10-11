@tool
extends EditorPlugin

## Editor tooling (outside the game domains): when the editor was started by `tools/editor.sh --autorun`
## (`GAME_AUTORUN` set), runs the main scene once the editor has finished its first scan. Inert otherwise.


func _enter_tree() -> void:
	if OS.get_environment("GAME_AUTORUN").is_empty():
		return
	# Deferred a beat so the first filesystem scan finishes before the game is launched.
	get_tree().create_timer(2.0).timeout.connect(_play, CONNECT_ONE_SHOT)


## Run the project's main scene in the editor, once.
func _play() -> void:
	EditorInterface.play_main_scene()
