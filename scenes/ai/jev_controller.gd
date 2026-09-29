extends Node

## AI domain: controller for a non-player character that asks a Jev-style "System One" decision model
## what to do next. It satisfies the character's controller contract (`control(character,
## delta)`) and writes only the intent fields the player controller writes (`move_input`,
## `aim_point`). Every `decide_interval` seconds it POSTs a short text description of the
## situation to a `/v1/systemone` server (e.g. a local Von) with one `choice` question, then
## samples its next action from the returned probabilities. If the server can't be reached it
## picks an action uniformly at random, so the NPC still acts without it.

## The `/v1/systemone` endpoint to ask.
@export var server_url: String = "http://127.0.0.1:8000/v1/systemone"
## Model name sent with each request.
@export var model: String = "von-1.2.0"
## Seconds between decisions.
@export var decide_interval: float = 1.0
## Distance (px) at which "approach" stops closing in on the target.
@export var approach_stop_distance: float = 40.0

## The actions the model chooses between, with the description the model reads for each.
const ACTIONS := {
	"approach": "Walk toward the player",
	"wander": "Walk around aimlessly",
	"wait": "Stand still",
}

## The node this NPC reasons about (the player), set by Main.
var target: Node2D

var _action := "wait"  ## The action currently being carried out.
var _wander_dir := Vector2.ZERO  ## Direction held while wandering.
var _timer := 0.0  ## Seconds until the next decision.
var _pending := false  ## True while a request is in flight.
var _http: HTTPRequest  ## Client for decision requests.


## Build the HTTP client used for decision requests.
func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 3.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## Called each physics frame by the character: ask for a new decision when due, then carry out
## the current action.
func control(character, delta: float) -> void:
	if target == null:
		return

	_timer -= delta
	if _timer <= 0.0 and not _pending:
		_timer = decide_interval
		_request_decision(character)

	var to_target: Vector2 = target.global_position - character.global_position
	match _action:
		"approach":
			var close := to_target.length() <= approach_stop_distance
			character.move_input = Vector2.ZERO if close else to_target.normalized()
			character.aim_point = target.global_position
		"wander":
			character.move_input = _wander_dir
			character.aim_point = character.global_position + _wander_dir * 50.0
		_:
			character.move_input = Vector2.ZERO
			character.aim_point = target.global_position


## POST the current situation and the "what next?" question to the decision server.
func _request_decision(character) -> void:
	var distance := int(character.global_position.distance_to(target.global_position))
	var body := {
		"model": model,
		"state": "You are a person in a house. The player is %d pixels away. You are currently: %s." % [distance, _action],
		"questions": {
			"action": {
				"type": "choice",
				"instructions": "What should you do next?",
				"criteria": ACTIONS,
			},
		},
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _http.request(server_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		_pending = true
	else:
		_set_action(ACTIONS.keys().pick_random())
		print("NPC (Jev) request failed to start — random fallback: %s" % _action)


## Read the answer's probabilities and sample the next action; fall back to a random action
## on any failure.
func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	var probabilities := _parse_probabilities(result, code, body)
	if probabilities.is_empty():
		_set_action(ACTIONS.keys().pick_random())
		print("NPC (Jev) server unreachable (result %d, HTTP %d) — random fallback: %s" % [result, code, _action])
		return

	_set_action(_sample(probabilities))
	var parts := PackedStringArray()
	for key in probabilities:
		parts.append("%s: %.2f" % [key, probabilities[key]])
	print("NPC (Jev) chose %s  {%s}" % [_action, ", ".join(parts)])


## The `answers.action.probabilities` dict of a successful response, keeping only known
## actions; empty if the request failed or the response is malformed.
func _parse_probabilities(result: int, code: int, body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return {}
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("answers") is Dictionary:
		return {}
	var answer = data["answers"].get("action")
	if not answer is Dictionary or not answer.get("probabilities") is Dictionary:
		return {}
	var probabilities := {}
	for key in answer["probabilities"]:
		if ACTIONS.has(key):
			probabilities[key] = float(answer["probabilities"][key])
	return probabilities


## Pick a key at random, weighted by its probability.
func _sample(probabilities: Dictionary) -> String:
	var total := 0.0
	for p in probabilities.values():
		total += p
	var roll := randf() * total
	for key in probabilities:
		roll -= probabilities[key]
		if roll <= 0.0:
			return key
	return probabilities.keys().back()


## Switch to an action, choosing a fresh direction when it is "wander".
func _set_action(action: String) -> void:
	_action = action
	if action == "wander":
		_wander_dir = Vector2.RIGHT.rotated(randf() * TAU)
