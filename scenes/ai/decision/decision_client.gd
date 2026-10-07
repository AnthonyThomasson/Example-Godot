extends Node

## AI DECISION sub-domain: the external-model boundary. This wraps the round-trip to the local Von
## ("System One") decision server. It takes the decision context the PERCEPTION sub-domain built
## (`{ state_text, acts, moves }`), POSTs it as two `choice` questions, and resolves Von's answer into
## the top-ranked `act` and `move` option ids. Von is a stateless single-shot ranker, so all the
## reasoning lives server-side; this only brokers the HTTP request and the argmax pick. It emits
## `decided(act_id, move_id)` on success and `failed()` on any error (request couldn't start, server
## unreachable, or malformed response) so the controller can fall back to a steady stance. It holds
## NO policy: it never interprets what an id MEANS — the behaviour sub-domain does that.

## Von's top-ranked ids for this tick's questions (argmax of each `choice`).
signal decided(act_id: String, move_id: String)
## A request could not start, the server was unreachable, or the response was malformed.
signal failed()

## The `/v1/systemone` endpoint to ask (set by the controller from its export).
var server_url: String = "http://127.0.0.1:8000/v1/systemone"
## Model name sent with each request.
var model: String = "von-1.2.0"

var _http: HTTPRequest             ## Client for decision requests.
var _pending := false             ## True while a request is in flight.
var _acts := {}                   ## Act options sent with the in-flight request (to validate the pick).
var _moves := {}                  ## Move options sent with the in-flight request.
var _npc_name := "NPC"            ## Name of the driven NPC, for log lines.


## Configure the endpoint + request timeout and build the HTTP client. Called once by the controller.
func configure(url: String, model_name: String, timeout: float) -> void:
	server_url = url
	model = model_name
	_http = HTTPRequest.new()
	_http.timeout = timeout
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## Whether a request is in flight (the controller issues no new decision until it completes).
func is_pending() -> bool:
	return _pending


## POST the decision context (`{ state_text, acts, moves }`) with the `act` and `move` `choice`
## questions. `npc_name` is kept for log lines. Returns whether the request started; on failure to
## start it also emits `failed()` so the controller holds steady.
func request(ctx: Dictionary, npc_name: String) -> bool:
	_npc_name = npc_name
	_acts = ctx["acts"]
	_moves = ctx["moves"]
	var body := {
		"model": model,
		"state": ctx["state_text"],
		"questions": {
			"act": _question("What should you do right now?", _acts),
			"move": _question("If you are just holding, which place should you go to?", _moves),
		},
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _http.request(server_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		_pending = true
		return true
	failed.emit()
	print("%s (Von) request failed to start — holding steady" % _npc_name)
	return false


## A `choice` question whose criteria map each option id to its human-readable description.
func _question(instructions: String, options: Dictionary) -> Dictionary:
	var criteria := {}
	for id in options:
		criteria[id] = options[id]["desc"]
	return { "type": "choice", "instructions": instructions, "criteria": criteria }


## Read the answers and emit Von's top pick for each; emit `failed()` on transport or parse error.
func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit()
		print("%s (Von) server unreachable (result %d, HTTP %d) — holding steady" % [_npc_name, result, code])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("answers") is Dictionary:
		failed.emit()
		print("%s (Von) malformed response — holding steady" % _npc_name)
		return
	var answers: Dictionary = data["answers"]
	decided.emit(_pick(answers, "act", _acts), _pick(answers, "move", _moves))


## The offered option id Von ranks highest for question `key`: its argmax `choice` when that is one of
## this tick's options, else the highest-probability offered id. Von's distributions over these
## options are flat (low confidence), so taking the top pick — rather than sampling — keeps the NPC
## decisive and goal-coherent instead of jittering. Empty when no offered option has any probability.
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
