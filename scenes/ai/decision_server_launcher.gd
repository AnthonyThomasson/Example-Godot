extends Node

## AI domain: development convenience that starts a local decision-model server (Von's `von serve`) when the
## game runs from the Godot editor, and stops it when the game exits. Exported builds never
## launch it. If a server is already answering on `port` it is reused and left running. The
## server's output is appended to `user://von_server.log` and, when `echo_to_output` is set,
## printed to the editor Output panel as `[von] …` lines.

## Absolute path to the `von` executable (the editor-launched game doesn't see the shell PATH).
## Empty = never auto-start.
@export_global_file var von_path: String = "/Users/athomasson/.venvs/von/bin/von"
## Port the server listens on (must match the AI controller's `server_url`).
@export var port: int = 8000
## Compute device passed to `von serve --device`. `cpu` is the default because PyTorch's Apple
## GPU backend (`mps`, which `auto` picks on a Mac) crashes the server on its first request.
@export_enum("cpu", "auto", "mps", "cuda", "openvino") var device: String = "cpu"
## Also print each server log line to the Output panel.
@export var echo_to_output: bool = true

## Where the server output is appended.
const LOG_PATH := "user://von_server.log"

var _pid := -1  ## Process id of the server we launched; -1 if none.
var _pipe: FileAccess  ## The server's merged stdout/stderr.
var _reader: Thread  ## Drains `_pipe` into the log file (and Output).


## Probe for a running server, then launch one if none answers.
func _ready() -> void:
	if not OS.has_feature("editor"):
		return
	var probe := HTTPRequest.new()
	probe.timeout = 1.0
	add_child(probe)
	probe.request_completed.connect(_on_probe_completed.bind(probe))
	if probe.request("http://127.0.0.1:%d/" % port) != OK:
		probe.queue_free()
		_launch()


## Any HTTP answer (even a 404) means a server is already up; otherwise start one.
func _on_probe_completed(result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray, probe: HTTPRequest) -> void:
	probe.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS:
		print("[von] Reusing the decision server already running on port %d." % port)
	else:
		_launch()


## Start `von serve` with its output piped back to us, and a thread to read it.
func _launch() -> void:
	if von_path.is_empty():
		print("[von] No server on port %d and von_path is empty — set it on DecisionServerLauncher to auto-start Von." % port)
		return
	# `exec` makes the shell become the server, so the pid we kill is the server itself.
	var command := "exec '%s' serve --host 127.0.0.1 --port %d --device %s 2>&1" % [von_path, port, device]
	var process := OS.execute_with_pipe("/bin/sh", ["-c", command])
	if process.is_empty():
		push_warning("[von] Failed to start %s" % von_path)
		return
	_pid = process["pid"]
	_pipe = process["stdio"]
	_reader = Thread.new()
	_reader.start(_read_output)
	print("[von] Started decision server (pid %d); log: %s" % [_pid, ProjectSettings.globalize_path(LOG_PATH)])


## Reader thread: copy each server line into the log file (and Output) until the pipe closes.
func _read_output() -> void:
	var log_file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if log_file == null:
		log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if log_file != null:
		log_file.seek_end()
	while _pipe.is_open() and _pipe.get_error() == OK:
		var line := _pipe.get_line()
		if line.is_empty() and _pipe.get_error() != OK:
			break
		if log_file != null:
			log_file.store_line(line)
			log_file.flush()
		if echo_to_output:
			print("[von] ", line)


## Stop the server we launched and wait for the reader thread to see the pipe close.
func _exit_tree() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1
	if _reader != null and _reader.is_started():
		_reader.wait_to_finish()
