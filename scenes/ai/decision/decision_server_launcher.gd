extends Node

## AI domain: development convenience that starts a local decision-model server (Von's `von serve`) when the
## game runs from the Godot editor, and stops it when the game exits. Exported builds never
## launch it. A server already answering on `port` is reused and left running, and only a server this
## launcher itself started is stopped on exit. Reuse is decided by probing `port` up to
## `probe_attempts` times so a slow-to-answer existing server is reused rather than racing into a
## duplicate that cannot bind the port. The server's output is appended to `user://von_server.log`
## and, when `echo_to_output` is set, printed to the editor Output panel as `[von] …` lines.
##
## The probe asks the server to DECIDE (see `health_path`), not merely to answer `GET /`, because an
## ORPHANED server is worse than an absent one. A `von serve` left behind by a hard-killed run (which
## skips `_exit_tree`) has a dead stdout pipe, so when it tries to fetch weights the progress output
## raises `EPIPE` and the load fails — permanently. It still serves HTTP, so a liveness check would
## reuse it forever while every decision 422s. Asking for a real decision catches that and resolves
## `false` with the server's own explanation. To clear such a server by hand: `pkill -f "von serve"`.

## Emitted exactly ONCE when the server question settles: `live` is true when a server answered (NPC
## decisions will succeed), false when none is coming — no `von_path`, a failed spawn, an exported
## build, or `ready_timeout` elapsed. Main gates the match start on this, so every terminal path must
## reach `_resolve()`: one that silently never resolved would hang the setup window forever.
signal resolved(live: bool)

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
## just-orphaned or briefly slow server (one that TIMES OUT) be reused instead of racing into a
## duplicate. A port that REFUSES the connection has nothing bound to wait for, so that answer
## short-circuits the retries and launches at once.
@export var probe_attempts: int = 5
## Seconds between probe attempts.
@export var probe_interval: float = 0.5
## How long (s) to keep polling a server we launched for its first answer, so the match can know when
## the brain is live. Model boot dominates this; it is not a hard failure, just when we stop waiting.
@export var ready_timeout: float = 90.0
## Endpoint the readiness check POSTs to. It deliberately exercises the REAL decision endpoint: a
## `GET /` only proves something is listening, and a server that cannot load its weights answers that
## happily (200 in milliseconds) while refusing every actual decision. Asking it to decide is the only
## check that means "the brain works" — and it doubles as a warm-up, so the first in-match decision
## isn't the one paying for model load.
@export var health_path: String = "/v1/systemone"
## Model name sent with the readiness check; keep it in step with the AI controllers' `model`.
@export var health_model: String = "von-1.2.0"

## Where the server output is appended.
const LOG_PATH := "user://von_server.log"

var _pid := -1  ## Process id of the server we launched; -1 if none (including a reused server).
var _pipe: FileAccess  ## The server's merged stdout/stderr.
var _reader: Thread  ## Drains `_pipe` into the log file (and Output).
var _probe: HTTPRequest  ## Reused across probe attempts; freed once the server answers or we give up.
var _attempts_left := 0  ## Reuse-probe attempts remaining before we launch our own server.
var _waiting_ready := false  ## True once we launched and are polling for the server's first answer.
var _ready_deadline_ms := 0  ## When to stop polling a launched server (see `ready_timeout`).
var _start_ms := 0  ## Scene-load time, so the ready line can report how long the brain took.
var _resolved := false  ## Whether the server question has settled (see `resolved`).
var _live := false  ## Whether that settled answer was "a server is up".


## Whether the server question has settled. Main checks this BEFORE awaiting `resolved`, because a
## path that resolves synchronously in `_ready()` (an exported build) fires the signal before any
## parent could connect — children are readied before their parent.
func is_resolved() -> bool:
	return _resolved


## Whether a decision server is up. Only meaningful once `is_resolved()`.
func is_live() -> bool:
	return _live


## Settle the server question once and tell anyone gating on it. Idempotent: the first answer wins.
func _resolve(live: bool) -> void:
	if _resolved:
		return
	_resolved = true
	_live = live
	_waiting_ready = false
	_end_probing()
	resolved.emit(live)


## Probe for a running server (retrying up to `probe_attempts`), then launch one if none answers and
## poll it until it is live. This node sits at the root of `main.tscn`, so all of it runs at SCENE
## LOAD — while the pre-game setup window is still open — giving the server its whole boot time
## before the match builds any NPC.
func _ready() -> void:
	if not OS.has_feature("editor"):
		_resolve(false)  # Exported build: never auto-starts, so the match must not wait on one.
		return
	_start_ms = Time.get_ticks_msec()
	# Fall back to the per-machine project setting when no explicit path is set on the node.
	if von_path.is_empty():
		von_path = ProjectSettings.get_setting("application/von/server_path", "")
	_probe = HTTPRequest.new()
	# Generous: the probe is a real inference, and the first one also pays for loading the weights.
	# A refused connection still returns immediately, so this doesn't slow cold-start detection.
	_probe.timeout = 15.0
	add_child(_probe)
	_probe.request_completed.connect(_on_probe_completed)
	_attempts_left = maxi(1, probe_attempts)
	_probe_once()


## Ask the server to make one throwaway decision; `_on_probe_completed` then decides reuse, retry,
## launch, or "up but useless". This is a real POST to `health_path` rather than a `GET /` so that
## only a server that can actually DECIDE counts as live.
func _probe_once() -> void:
	_attempts_left -= 1
	var payload := {
		"model": health_model,
		"state": "Readiness check.",
		"questions": {
			"act": {
				"type": "choice",
				"instructions": "What should you do right now?",
				"criteria": { "ok": "report that you are ready" },
			},
		},
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := "http://127.0.0.1:%d%s" % [port, health_path]
	if _probe.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload)) != OK:
		# The request couldn't even start (not expected for a fixed localhost URL); treat it as
		# a failed attempt so the retry/launch path still runs.
		_on_probe_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


## Only a 200 — a decision actually returned — counts as live. The other outcomes are distinct faults:
## a non-200 means a server IS bound but cannot decide (it could not load its weights, say), and
## launching our own would merely fail to bind the port, so we retry briefly in case it is still
## warming up and then report its own explanation. A REFUSED connection means nothing is bound, so we
## launch at once rather than spending the retry budget (those retries only pay off for an answer that
## TIMED OUT — a slow or just-orphaned server worth reusing). After launching we poll our own server
## until it decides or `ready_timeout` passes.
func _on_probe_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_announce_ready()
		return
	if result == HTTPRequest.RESULT_SUCCESS:
		if _attempts_left > 0:
			await _wait_then_probe()
			return
		push_warning("[von] Server on port %d is up but cannot decide (HTTP %d): %s" % [port, code, _detail(body)])
		_resolve(false)
		return
	if _waiting_ready:
		if Time.get_ticks_msec() >= _ready_deadline_ms:
			push_warning("[von] Server has not answered within %.0fs; NPCs hold steady until it does." % ready_timeout)
			_resolve(false)
			return
		await _wait_then_probe()
		return
	if result == HTTPRequest.RESULT_CANT_CONNECT or _attempts_left <= 0:
		_launch_and_await_ready()
		return
	await _wait_then_probe()


## The server's own explanation for a non-200 (`{ "detail": … }`), trimmed to keep the warning
## readable; falls back to the raw body. Mirrors `decision_client`'s reporting of the same shape.
func _detail(body: PackedByteArray) -> String:
	var text := body.get_string_from_utf8().strip_edges()
	var data = JSON.parse_string(text)
	if data is Dictionary and data.has("detail"):
		text = str(data["detail"])
	if text == "":
		return "(empty response body)"
	return text if text.length() <= 300 else text.substr(0, 300) + "…"


## Wait out `probe_interval` and probe again, bailing if the node left the tree mid-wait (the game
## quit while we were polling).
func _wait_then_probe() -> void:
	await get_tree().create_timer(probe_interval).timeout
	if _probe == null:
		return
	_probe_once()


## Start our own server, then poll it until it answers so `server_ready` reports a LIVE brain rather
## than merely a spawned process. If nothing started (no `von_path`, or the spawn failed) there is
## nothing to wait for, so probing stops.
func _launch_and_await_ready() -> void:
	_launch()
	if _pid <= 0:
		_resolve(false)  # Nothing started (blank von_path or a failed spawn) — nothing to wait for.
		return
	_waiting_ready = true
	_ready_deadline_ms = Time.get_ticks_msec() + int(ready_timeout * 1000.0)
	await _wait_then_probe()


## The server answered: report how long it took from scene load and let anyone gating on it proceed.
func _announce_ready() -> void:
	var secs: float = (Time.get_ticks_msec() - _start_ms) / 1000.0
	if _pid > 0:
		print("[von] Decision server live on port %d, %.1fs after scene load (pid %d)." % [port, secs, _pid])
	else:
		print("[von] Reusing the decision server already running on port %d." % port)
	_resolve(true)


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
