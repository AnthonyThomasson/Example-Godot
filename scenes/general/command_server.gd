extends Node

## General domain, development-only: a small TCP server that lets an external tool (the agent /
## MCP, driven from `tools/gcmd.py`) control the running game with text commands. It never exists
## in an exported build — `_ready()` returns unless running from the editor binary — and stays off
## unless a listen port is set, so it is opt-in like the decision-server launcher.
##
## Commands are line-delimited over 127.0.0.1. Each line is either a curated verb (see `help`) or,
## if it matches no verb, a GDScript `Expression` evaluated against this node. Movement and actions
## are driven by injecting real input (`Input.action_press`/`release`), the exact path a human's
## keyboard/mouse uses, so any controller that reads `Keybinds` obeys them with no coupling here.
## `command_server.gd` is, by design, the second file besides `player_controller.gd` that touches
## `Keybinds` — it needs the action names to inject input.

## Port to listen on; 0 falls back to the `application/debug/command_port` project setting, and 0
## there too means the server never starts.
@export var port: int = 0

var _server: TCPServer  ## The listening socket; null when the server is off.
## Connected clients, each `{ peer: StreamPeerTCP, buf: String }` (buffered until a full line).
var _clients: Array = []
## Actions tapped this frame, released at the start of the next so they read as "just pressed" once.
var _release_next_frame: Array = []
## Move direction word -> Keybinds action, so movement verbs never hard-code action strings.
var _move_actions: Dictionary = {}
## Item slot 1-9 -> Keybinds action, indexed by slot minus one.
var _item_actions: Array = []
## When this server (hence the scene) started, so the `match` verb can report elapsed match time.
var _match_start_ms: int = Time.get_ticks_msec()


## Start listening only from an editor run and only when a port is configured; otherwise stay off.
func _ready() -> void:
	if not OS.has_feature("editor"):
		return
	_move_actions = {
		"up": Keybinds.MOVE_UP, "down": Keybinds.MOVE_DOWN,
		"left": Keybinds.MOVE_LEFT, "right": Keybinds.MOVE_RIGHT,
	}
	_item_actions = [
		Keybinds.ITEM_1, Keybinds.ITEM_2, Keybinds.ITEM_3, Keybinds.ITEM_4, Keybinds.ITEM_5,
		Keybinds.ITEM_6, Keybinds.ITEM_7, Keybinds.ITEM_8, Keybinds.ITEM_9,
	]
	if port <= 0:
		port = int(ProjectSettings.get_setting("application/debug/command_port", 0))
	if port <= 0:
		return
	_server = TCPServer.new()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_warning("[cmd] failed to listen on port %d (error %d)" % [port, err])
		_server = null
		return
	print("[cmd] listening on 127.0.0.1:%d" % port)


## Release last frame's taps, accept new clients, then read and run any complete command lines.
func _process(_delta: float) -> void:
	for action in _release_next_frame:
		Input.action_release(action)
	_release_next_frame.clear()

	if _server == null:
		return
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "buf": ""})

	var dead: Array = []
	for client in _clients:
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			dead.append(client)
			continue
		if status != StreamPeerTCP.STATUS_CONNECTED:
			continue  # Still connecting; try again next frame.
		var available := peer.get_available_bytes()
		var buf: String = client["buf"]
		if available > 0:
			buf += peer.get_utf8_string(available)
		while buf.contains("\n"):
			var nl := buf.find("\n")
			var line := buf.substr(0, nl).strip_edges()
			buf = buf.substr(nl + 1)
			var result := _execute(line)
			peer.put_data((result + "\n").to_utf8_buffer())
			print("[cmd] %s -> %s" % [line, result])
		client["buf"] = buf
	for client in dead:
		_clients.erase(client)


## Run one command line: a curated verb, or a GDScript expression when it matches no verb.
func _execute(line: String) -> String:
	if line.is_empty():
		return ""
	var parts := line.split(" ", false)
	match parts[0]:
		"help":
			return "verbs: help, pos, tp X Y, slot N, move up|down|left|right [off], stop, " \
				+ "fire, punch, interact, aim X Y, match, restart [seed], eval EXPR; " \
				+ "anything else = GDScript expression"
		"match":
			return _match_status()
		"restart":
			# Reload for a fresh matchup. An optional seed pins the next layout; Engine meta survives
			# the scene reload, and main.gd reads it on start.
			if parts.size() >= 2:
				Engine.set_meta("match_seed", parts[1].to_int())
			get_tree().reload_current_scene()
			return "ok"
		"pos":
			var p := player()
			return "no player" if p == null else str(p.global_position)
		"tp":
			if parts.size() < 3:
				return "usage: tp X Y"
			var p := player()
			if p == null:
				return "no player"
			p.global_position = Vector2(parts[1].to_float(), parts[2].to_float())
			return "ok"
		"slot":
			if parts.size() < 2:
				return "usage: slot N"
			var n := parts[1].to_int()
			if n < 1 or n > _item_actions.size():
				return "usage: slot 1-9"
			tap(_item_actions[n - 1])
			return "ok"
		"move":
			if parts.size() < 2 or not _move_actions.has(parts[1]):
				return "usage: move up|down|left|right [off]"
			var action: StringName = _move_actions[parts[1]]
			if parts.size() >= 3 and parts[2] == "off":
				release(action)
			else:
				press(action)
			return "ok"
		"stop":
			for action in _move_actions.values():
				release(action)
			return "ok"
		"fire":
			tap(Keybinds.FIRE)
			return "ok"
		"punch":
			tap(Keybinds.PUNCH)
			return "ok"
		"interact":
			tap(Keybinds.INTERACT)
			return "ok"
		"aim":
			if parts.size() < 3:
				return "usage: aim X Y"
			return _aim(Vector2(parts[1].to_float(), parts[2].to_float()))
		"eval":
			return _eval(line.substr(5))
		_:
			return _eval(line)


## Evaluate `text` as a GDScript expression against this node, returning the result or an error.
func _eval(text: String) -> String:
	var expr := Expression.new()
	if expr.parse(text) != OK:
		return "parse error: " + expr.get_error_text()
	var result: Variant = expr.execute([], self)
	if expr.has_execute_failed():
		return "error: " + expr.get_error_text()
	return var_to_str(result)


## One-line, parseable match status for the headless harness: each combatant's health/act/alive,
## then the verdict and elapsed seconds. Reads only the characters' public API (`health`, `is_dead`)
## and their controller's `current_act()`, so the server stays a decoupled observer.
func _match_status() -> String:
	var lines := PackedStringArray()
	var dead := PackedStringArray()
	var alive := PackedStringArray()
	for cname in ["Defender", "Invader"]:
		var c := node(cname)
		if c == null:
			continue
		var hp: float = c.health if "health" in c else -1.0
		var is_dead: bool = c.get("is_dead") == true
		lines.append("%s hp=%.0f act=%s alive=%s" % [cname, hp, _act_of(c), str(not is_dead)])
		(dead if is_dead else alive).append(cname)
	var verdict := "none"
	if not dead.is_empty():
		verdict = alive[0] if alive.size() == 1 else "draw"
	var elapsed := (Time.get_ticks_msec() - _match_start_ms) / 1000.0
	return "%s | verdict=%s elapsed=%.1f" % [" | ".join(lines), verdict, elapsed]


## The current act of `character`'s AI controller child, or "?" when it has none (e.g. the player).
func _act_of(character: Node) -> String:
	for child in character.get_children():
		if child.has_method("current_act"):
			return child.current_act()
	return "?"


# --- Helpers, callable both from the verbs and from `eval` expressions --------------------

## The player character node, or null if the current scene has none.
func player() -> Node:
	var s := scene()
	return null if s == null else s.get_node_or_null("Player")


## The running scene's root (the composition-root Main node).
func scene() -> Node:
	return get_tree().current_scene


## The node at `path` under the scene root, or null if absent.
func node(path: String) -> Node:
	var s := scene()
	return null if s == null else s.get_node_or_null(path)


## Hold `action` down (used for sustained movement) until a matching `release`.
func press(action: StringName) -> void:
	Input.action_press(action)


## Let go of `action`.
func release(action: StringName) -> void:
	Input.action_release(action)


## Press `action` for one frame — released at the start of next `_process` — so a controller
## reading `is_action_just_pressed` fires it exactly once (fire, punch, interact, item select).
func tap(action: StringName) -> void:
	Input.action_press(action)
	_release_next_frame.append(action)


## Warp the mouse so the character aims at world point `world`. Windowed runs only — a headless
## run has no real cursor, so aim has no effect there.
func _aim(world: Vector2) -> String:
	var vp := get_viewport()
	if vp == null:
		return "no viewport"
	Input.warp_mouse(vp.get_canvas_transform() * world)
	return "ok (windowed only)"


## Stop the server and drop any input the commands were still holding.
func _exit_tree() -> void:
	for action in _release_next_frame:
		Input.action_release(action)
	_release_next_frame.clear()
	for action in _move_actions.values():
		Input.action_release(action)
	if _server != null:
		_server.stop()
		_server = null
	_clients.clear()
