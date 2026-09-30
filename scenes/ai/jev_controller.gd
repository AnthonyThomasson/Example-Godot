extends Node

## AI domain: controller for a non-player character that asks a Jev-style "System One" decision model
## what to do next. It satisfies the character's controller contract (`control(character, delta)`)
## and writes only the intent the player controller writes (`move_input`, `aim_point`) plus the same
## public actions (`select_slot`, `melee`, `shoot`, `interact_with`). Every `decide_interval` seconds
## it POSTs a short text description of the situation to a `/v1/systemone` server (e.g. a local Von)
## with one `choice` question, then samples its next action from the returned probabilities. If the
## server can't be reached it picks an action uniformly at random, so the NPC still acts without it.
##
## Movement is real pathfinding: a NavigationAgent2D routes around walls through doorways (see the
## Navigation domain). Actions compose the character's abilities — approach/flee path to a spot,
## shoot/punch equip the right item then aim and fire, interact triggers a specific object action.

## The `/v1/systemone` endpoint to ask.
@export var server_url: String = "http://127.0.0.1:8000/v1/systemone"
## Model name sent with each request.
@export var model: String = "von-1.2.0"
## Seconds between decisions.
@export var decide_interval: float = 1.0
## Distance (px) at which "approach" stops closing in on the target.
@export var approach_stop_distance: float = 40.0
## Max distance (px) to open fire; farther than this, "shoot" paths closer first.
@export var shoot_range: float = 420.0
## Seconds between shots while in the "shoot" action.
@export var fire_interval: float = 0.5
## NavigationAgent2D used for pathing (a sibling under the character); set in the NPC scene.
@export var nav_agent_path: NodePath

## Inventory slots (see ItemRegistry): fists melee, pistol shoots.
const SLOT_FISTS := 2
const SLOT_PISTOL := 3

## The actions the model chooses between, with the description the model reads for each.
const ACTIONS := {
	"approach": "Walk toward the player",
	"wander": "Walk around aimlessly",
	"wait": "Stand still",
	"flee": "Run away from the player",
	"equip_pistol": "Draw the pistol",
	"equip_fists": "Raise your fists",
	"shoot": "Shoot the player with the pistol",
	"punch": "Punch the player",
	"interact": "Use a nearby object (sit, hide, ...)",
}

## The node this NPC reasons about (the player), set by Main.
var target: Node2D

var _action := "wait"  ## The action currently being carried out.
var _wander_dir := Vector2.ZERO  ## Direction held while wandering.
var _timer := 0.0  ## Seconds until the next decision.
var _fire_timer := 0.0  ## Seconds until the next shot may fire.
var _pending := false  ## True while a request is in flight.
var _http: HTTPRequest  ## Client for decision requests.
var _agent: NavigationAgent2D  ## Pathfinding agent, or null (falls back to straight-line).


## Build the HTTP client and resolve the navigation agent.
func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 3.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	if nav_agent_path != NodePath():
		_agent = get_node_or_null(nav_agent_path) as NavigationAgent2D


## Called each physics frame by the character: ask for a new decision when due, then carry out
## the current action.
func control(character, delta: float) -> void:
	if target == null:
		return

	_timer -= delta
	_fire_timer -= delta
	if _timer <= 0.0 and not _pending:
		_timer = decide_interval
		_request_decision(character)

	# Leaving an interaction: release the object before doing anything else.
	if _action != "interact" and character.is_busy():
		character.end_interaction()

	match _action:
		"approach":
			character.aim_point = target.global_position
			if character.global_position.distance_to(target.global_position) <= approach_stop_distance:
				character.move_input = Vector2.ZERO
			else:
				_path_move(character, target.global_position)
		"flee":
			var away: Vector2 = character.global_position - target.global_position
			character.aim_point = target.global_position
			_path_move(character, character.global_position + away.normalized() * 200.0)
		"equip_pistol":
			character.select_slot(SLOT_PISTOL)
			character.move_input = Vector2.ZERO
			character.aim_point = target.global_position
		"equip_fists":
			character.select_slot(SLOT_FISTS)
			character.move_input = Vector2.ZERO
			character.aim_point = target.global_position
		"shoot":
			_do_shoot(character)
		"punch":
			_do_punch(character)
		"interact":
			_do_interact(character)
		"wander":
			character.aim_point = character.global_position + _wander_dir * 50.0
			_path_move(character, character.global_position + _wander_dir * 120.0)
		_:
			character.move_input = Vector2.ZERO
			character.aim_point = target.global_position


## Equip the pistol, aim at the target, and fire on the cooldown once within range and aligned;
## path closer while out of range.
func _do_shoot(character) -> void:
	character.select_slot(SLOT_PISTOL)
	character.aim_point = target.global_position
	var to_target: Vector2 = target.global_position - character.global_position
	if to_target.length() > shoot_range:
		_path_move(character, target.global_position)
		return
	character.move_input = Vector2.ZERO
	# The character derives `facing` from `aim_point` after this call within the same frame, so fire
	# only once `facing` already points at the target (it converges one frame after aiming).
	if _fire_timer <= 0.0 and character.facing.dot(to_target.normalized()) > 0.98:
		character.shoot()
		_fire_timer = fire_interval


## Equip fists, close to melee range, and swing when in reach and not already mid-swing.
func _do_punch(character) -> void:
	character.select_slot(SLOT_FISTS)
	character.aim_point = target.global_position
	var to_target: Vector2 = target.global_position - character.global_position
	if to_target.length() > approach_stop_distance:
		_path_move(character, target.global_position)
		return
	character.move_input = Vector2.ZERO
	if not character.is_attacking():
		character.melee()


## Trigger a specific action on a reachable object; path toward the target to find one when
## nothing is in reach. Stays in the interaction once started (until the action changes).
func _do_interact(character) -> void:
	if character.is_busy():
		character.move_input = Vector2.ZERO
		return
	var reachable: Array = character.interactions_in_reach()
	if reachable.is_empty():
		character.aim_point = target.global_position
		_path_move(character, target.global_position)
		return
	var entry: Dictionary = reachable[0]
	var spec: Dictionary = entry["specs"][0]
	character.aim_point = entry["object"].global_position
	character.move_input = Vector2.ZERO
	character.interact_with(entry["object"], spec.get("id", ""))


## Steer `character.move_input` toward `dest` along a navigated path (around walls, through
## doorways). Falls back to straight-line steering if there is no navigation agent.
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
