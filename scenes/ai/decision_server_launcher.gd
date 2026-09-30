extends Node

## AI domain: development convenience that starts a local decision-model server (Von's `von serve`) when the
## game runs from the Godot editor, and stops it when the game exits. Exported builds never
## launch it. A server already answering on `port` is reused and left running — including one
## orphaned by a previous run that was hard-killed before `_exit_tree` could stop it — and only
## a server this launcher itself started is stopped on exit. Reuse is decided by probing `port`
## up to `probe_attempts` times so a slow-to-answer existing server is reused rather than racing
## into a duplicate that cannot bind the port. The server's output is appended to
## `user://von_server.log` and, when `echo_to_output` is set, printed to the editor Output panel
## as `[von] …` lines.

## Absolute path to the `von` executable (the editor-launched game doesn't see the shell PATH).
## Empty = never auto-start. Defaults to the `application/von/server_path` project setting, so the
## path is configured per machine (Project Settings) rather than hard-coded here; set it on the
## node to override.
@export_global_file var von_path: String = ""
## Port the server listens on (must match the AI controller's `server_url`).
@export var port: int = 8000
## Compute device passed to `von serve --device`. `cpu` is the default because PyTorch's Apple
## GPU backend (`mps`, which `auto` picks on a Mac) crashes the server on its first request.
@export_enum("cpu", "auto", "mps", "cuda", "openvino") var device: String = "cpu"
## Also print each server log line to the Output panel.
@export var echo_to_output: bool = true
## How many times to probe `port` before giving up and launching our own server. Retries let a
## just-orphaned or briefly slow server be detected and reused instead of racing into a duplicate.
@export var probe_attempts: int = 5
## Seconds between probe attempts.
@export var probe_interval: float = 0.5

## Where the server output is appended.
const LOG_PATH := "user://von_server.log"

var _pid := -1  ## Process id of the server we launched; -1 if none (including a reused server).
var _pipe: FileAccess  ## The server's merged stdout/stderr.
var _reader: Thread  ## Drains `_pipe` into the log file (and Output).
var _probe: HTTPRequest  ## Reused across probe attempts; freed once we reuse or launch.
var _attempts_left := 0  ## Probe attempts remaining before we launch our own server.


## Probe for a running server (retrying up to `probe_attempts`), then launch one if none answers.
func _ready() -> void:
	if not OS.has_feature("editor"):
		return
	# Fall back to the per-machine project setting when no explicit path is set on the node.
	if von_path.is_empty():
		von_path = ProjectSettings.get_setting("application/von/server_path", "")
	_probe = HTTPRequest.new()
	_probe.timeout = 1.0
	add_child(_probe)
	_probe.request_completed.connect(_on_probe_completed)
	_attempts_left = maxi(1, probe_attempts)
	_probe_once()


## Fire one probe at `port`; `_on_probe_completed` then decides reuse, retry, or launch.
func _probe_once() -> void:
	_attempts_left -= 1
	if _probe.request("http://127.0.0.1:%d/" % port) != OK:
		# The request couldn't even start (not expected for a fixed localhost URL); treat it as
		# a failed attempt so the retry/launch path still runs.
		_on_probe_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


## Any HTTP answer (even a 404) means a server is already up → reuse it. Otherwise retry until
## the attempts run out, then start our own.
func _on_probe_completed(result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS:
		print("[von] Reusing the decision server already running on port %d." % port)
		_end_probing()
		return
	if _attempts_left > 0:
		await get_tree().create_timer(probe_interval).timeout
		if _probe == null:
			return  # Node left the tree mid-wait (game quit while probing).
		_probe_once()
		return
	_end_probing()
	_launch()


## Free the probe node once probing is done (reuse found, attempts exhausted, or on exit).
func _end_probing() -> void:
	if _probe != null:
		_probe.queue_free()
		_probe = null


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


## Stop the server we launched (never a reused one) and wait for the reader thread to see the
## pipe close. A probe still in flight is dropped so its resumed continuation bails.
func _exit_tree() -> void:
	_end_probing()
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1
	if _reader != null and _reader.is_started():
		_reader.wait_to_finish()
