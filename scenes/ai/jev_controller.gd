extends Node

## AI domain: guard controller for a non-player character, driven by a Jev-style "System One" decision
## model (a local Von server). It satisfies the character's controller contract (`control(character,
## delta)`) and writes only the intent the player controller writes (`move_input`/`aim_point`) plus the
## same public actions (`select_slot`, `melee`, `shoot`). Its goal is to DEFEND THE HOUSE: it must not
## engage or attack the player unless the player is inside the house.
##
## Every `decide_interval` seconds it senses the world through GuardPerception and POSTs one request
## with three `choice` questions — where to move, where to aim, and what to do — to `/v1/systemone`,
## then adopts Von's TOP pick for each (its argmax `choice`). Von's distributions over these options are
## flat, so taking the top pick rather than sampling is what keeps the guard decisive instead of
## thrashing between near-equal options. The full option set (move ring + key points, aim ring +
## at-intruder, shoot/punch/hold) is offered every tick with NO mode gating: the goal and the intruder's
## position live in the state text, and Von applies the "only engage once inside" rule itself. Movement
## to the chosen point is real pathfinding through a NavigationAgent2D (around walls, through doorways),
## degrading to straight-line steering when no agent is set. When the server is unreachable it holds a
## steady stance (hold at post, watch the intruder) so the NPC never thrashes.

const GuardPerception := preload("res://scenes/ai/guard_perception.gd")

## The `/v1/systemone` endpoint to ask.
@export var server_url: String = "http://127.0.0.1:8000/v1/systemone"
## Model name sent with each request.
@export var model: String = "von-1.2.0"
## Seconds between decisions.
@export var decide_interval: float = 1.0
## Distance (px) projected along a chosen look-direction to build its aim point.
@export var aim_project_dist: float = 120.0
## NavigationAgent2D used for pathing (a sibling under the character); set in the NPC scene.
@export var nav_agent_path: NodePath

## The player this NPC defends the house against, set by Main.
var target: Node2D
## World-space room rects (`{ key, type, rect }`) from Main — the sensor's map of the house.
var rooms: Array = []

var _perception: Node             ## Builds the state + candidate sets each decision.
var _agent: NavigationAgent2D     ## Pathfinding agent, or null (falls back to straight-line).
var _moves := {}                  ## This tick's move options by id (from the sensor).
var _aims := {}                   ## This tick's aim options by id.
var _acts := {}                   ## This tick's act options by id.
var _move_point := Vector2.ZERO   ## Destination the current move choice steers toward.
var _has_move := false            ## Whether a move destination is set.
var _aim_dir := Vector2.ZERO      ## Direction the current aim choice looks along.
var _at_intruder := false         ## True when the aim choice is "aim at the intruder".
var _act := "hold"                ## The current act choice (shoot / punch / hold).
var _act_armed := false           ## Delays an act one frame so it fires along fresh facing.
var _move_id := ""                ## Ids of the current choices, for the decision log.
var _aim_id := ""
var _timer := 0.0                 ## Seconds until the next decision.
var _pending := false             ## True while a request is in flight.
var _http: HTTPRequest            ## Client for decision requests.


## Build the perception component, the HTTP client, and resolve the navigation agent.
func _ready() -> void:
	_perception = GuardPerception.new()
	add_child(_perception)
	_http = HTTPRequest.new()
	_http.timeout = 3.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	if nav_agent_path != NodePath():
		_agent = get_node_or_null(nav_agent_path) as NavigationAgent2D


## Called each physics frame by the character: ask for a new decision when due, then carry out the
## current move / aim / act choices.
func control(character, delta: float) -> void:
	if target == null:
		return
	_timer -= delta
	if _timer <= 0.0 and not _pending:
		_timer = decide_interval
		_request_decision(character)
	_apply(character)


## Carry out the current choices. Movement and aim are written every frame; the act fires once per
## decision, one frame after aim is applied so the shot/punch follows the freshly aimed facing.
func _apply(character) -> void:
	if _at_intruder:
		character.aim_point = target.global_position
	elif _aim_dir != Vector2.ZERO:
		character.aim_point = character.global_position + _aim_dir * aim_project_dist

	if _has_move:
		_path_move(character, _move_point)
	else:
		character.move_input = Vector2.ZERO

	if _act == "shoot" or _act == "punch":
		if _act_armed:
			var slot: int = _acts.get(_act, {}).get("slot", 0)
			if slot > 0:
				character.select_slot(slot)
			if _act == "shoot":
				character.shoot()
			else:
				character.melee()
			_act = "hold"  # One shot / punch per decision.
		else:
			_act_armed = true  # Let this frame's aim settle into facing first.


## Steer `character.move_input` toward `dest` along a navigated path (around walls, through doorways).
## Falls back to straight-line steering when there is no navigation agent.
func _path_move(character, dest: Vector2) -> void:
	if _agent == null:
		var straight: Vector2 = dest - character.global_position
		character.move_input = Vector2.ZERO if straight.length() < 4.0 else straight.normalized()
		return
	_agent.target_position = dest
	if _agent.is_navigation_finished():
		character.move_input = Vector2.ZERO
		return
	var next := _agent.get_next_path_position()
	character.move_input = (next - character.global_position).normalized()


## Sense the situation and POST it with the three `choice` questions. Falls back to a steady stance
## if the request can't even be started.
func _request_decision(character) -> void:
	var ctx: Dictionary = _perception.sense(character, target, rooms)
	_moves = ctx["moves"]
	_aims = ctx["aims"]
	_acts = ctx["acts"]
	var body := {
		"model": model,
		"state": ctx["state_text"],
		"questions": {
			"move": _question("Where should you move to best defend the house?", _moves),
			"aim": _question("Where should you look or point?", _aims),
			"act": _question("What should you do right now?", _acts),
		},
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _http.request(server_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		_pending = true
	else:
		_fallback()
		print("NPC (Von) request failed to start — holding steady")


## A `choice` question whose criteria map each option id to its human-readable description.
func _question(instructions: String, options: Dictionary) -> Dictionary:
	var criteria := {}
	for id in options:
		criteria[id] = options[id]["desc"]
	return { "type": "choice", "instructions": instructions, "criteria": criteria }


## Read the three answers and adopt Von's top pick for each; fall back to a steady stance on failure.
func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fallback()
		print("NPC (Von) server unreachable (result %d, HTTP %d) — holding steady" % [result, code])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("answers") is Dictionary:
		_fallback()
		print("NPC (Von) malformed response — holding steady")
		return
	var answers: Dictionary = data["answers"]
	_set_move(_pick(answers, "move", _moves))
	_set_aim(_pick(answers, "aim", _aims))
	_set_act(_pick(answers, "act", _acts))
	print("NPC (Von) move=%s aim=%s act=%s" % [_move_id, _aim_id, _act])


## The offered option id Von ranks highest for question `key`: its argmax `choice` when that is one of
## this tick's options, else the highest-probability offered id. Von's distributions over these options
## are flat (low confidence), so taking the top pick — rather than sampling — is what keeps the guard
## decisive and goal-coherent instead of jittering between near-equal options. Empty when no offered
## option carries any probability.
func _pick(answers: Dictionary, key: String, options: Dictionary) -> String:
	var answer = answers.get(key)
	if not answer is Dictionary:
		return ""
	var choice = answer.get("choice")
	if choice is String and options.has(choice):
		return choice
	return _argmax(answer, options)


## The offered id with the greatest probability in `answer.probabilities` (ignoring ids not offered
## this tick, so a stale or foreign id can never be chosen); empty if none are present.
func _argmax(answer: Dictionary, options: Dictionary) -> String:
	if not answer.get("probabilities") is Dictionary:
		return ""
	var best := ""
	var best_p := -1.0
	for id in answer["probabilities"]:
		if options.has(id) and float(answer["probabilities"][id]) > best_p:
			best_p = float(answer["probabilities"][id])
			best = id
	return best


## Adopt the chosen move: steer toward its destination point (or stop if the id is unknown/empty).
func _set_move(id: String) -> void:
	_move_id = id
	_has_move = id != "" and _moves.has(id)
	if _has_move:
		_move_point = _moves[id]["point"]


## Adopt the chosen aim: look along its direction, flagging the special "aim at the intruder" case.
func _set_aim(id: String) -> void:
	_aim_id = id
	if id != "" and _aims.has(id):
		_aim_dir = _aims[id]["dir"]
		_at_intruder = id == "at_intruder"
	else:
		_aim_dir = Vector2.ZERO
		_at_intruder = false


## Adopt the chosen act (defaulting to hold) and re-arm the one-frame fire delay.
func _set_act(id: String) -> void:
	_act = id if id != "" and _acts.has(id) else "hold"
	_act_armed = false


## A steady, non-chaotic stance for when Von is unreachable (server-down path): hold at post and watch
## the intruder rather than thrash between random options. Falls back to whatever ids exist this tick.
func _fallback() -> void:
	_set_move("post" if _moves.has("post") else "")
	_set_aim("at_intruder" if _aims.has("at_intruder") else "")
	_set_act("hold")
