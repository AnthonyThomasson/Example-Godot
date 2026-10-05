extends Node

## AI domain: a generic, goal-driven controller for a non-player character, driven by a Jev-style
## "System One" decision model (a local Von server). It satisfies the character's controller contract
## (`control(character, delta)`) and writes only the intent the player controller writes
## (`move_input`/`aim_point`) plus the same public actions (`select_slot`, `melee`, `shoot`,
## `interact_with`, `end_interaction`). The behaviour is pure DATA: `goal` is a plain-language
## sentence (e.g. "watch tv", "make some food", "hunt down the player", or the default "defend the
## house"), injected by Main. There is no per-goal code — the same machinery serves any behaviour.
##
## The decision is ACT-centric. Von ranks distinct, verb-like options reliably but ranks many
## near-identical spatial points almost at random, so the controller asks it WHAT TO DO — fire, punch,
## hold, or use one of the nearby objects (Watch TV, Cook, …) — and then DERIVES the movement itself:
## walk to the object it chose to use, close on the player it chose to shoot. (A small `move` menu of
## named rooms/post is consulted only when the act implies no movement, i.e. holding.) It adopts Von's
## TOP pick (argmax `choice`); the distributions are flat, so the top pick keeps the NPC decisive.
## Von is stateless and cannot sequence, so a COMMITMENT layer here supplies the memory: once it heads
## for an object or interaction it sticks with it until it arrives/finishes (a safety cap aside) or a
## salient event fires (the player crossing the house boundary), which lets multi-step goals advance
## instead of oscillating. Movement is real pathfinding through a NavigationAgent2D. When the server
## is unreachable it holds a steady stance (watch the player).

const AgentPerception := preload("res://scenes/ai/agent_perception.gd")
const AgentMemory := preload("res://scenes/ai/agent_memory.gd")

## The behaviour to pursue, in plain language. Injected by Main; the default keeps the house-guard
## behaviour when none is set.
@export_multiline var goal: String = ("You are the armed guard of this house. The player is an " +
	"intruder — shoot them with your pistol on sight to stop them. If you are fired upon, return fire, " +
	"but hold your ground inside the house; do not chase the intruder outside.")
## House-guard gate: when true, a shoot/punch choice made while the player is OUTSIDE the house
## becomes "hold" instead, so the guard only engages an intruder once they are inside. Other actions
## pass through unchanged. Turn off for a goal that should engage the player anywhere (e.g. hunt).
## This exists because Von (a single-shot ranker) can't reliably apply an "only if inside" condition
## itself, so the controller enforces it from the inside/outside fact it already senses.
@export var engage_only_inside: bool = true
## The `/v1/systemone` endpoint to ask.
@export var server_url: String = "http://127.0.0.1:8000/v1/systemone"
## Model name sent with each request.
@export var model: String = "von-1.2.0"
## Minimum seconds between decisions (the re-decide cadence once free to change).
@export var decide_interval: float = 1.0
## Seconds to stay in a chosen interaction before ending it and re-deciding (covers Von's
## statelessness so multi-step goals advance).
@export var interaction_dwell: float = 3.0
## Safety cap (s) on committing to reach a chosen object, so a blocked path still re-decides.
@export var max_commit_time: float = 6.0
## Range (px) within which a chosen shot is fired instead of advancing on the player.
@export var shoot_range: float = 500.0
## Range (px) within which a chosen punch lands instead of advancing on the player.
@export var punch_range: float = 48.0
## Radius (px) of the ring of candidate fire/cover positions sampled during combat.
@export var combat_ring_radius: float = 80.0
## Number of candidate positions sampled on that ring.
@export var combat_ring_count: int = 12
## Seconds to stay behind cover between shots (the duck half of peek-and-cover).
@export var cover_time: float = 1.2
## Minimum seconds between shots/punches while engaging.
@export var fire_cooldown: float = 0.5
## Seconds a chosen fire/cover position is committed to before a new one may be picked. Prevents
## per-frame re-selection of the nearest spot (which makes the NPC vibrate).
@export var reposition_interval: float = 0.5
## Radius (px) within which a hit on something else still registers as gunfire near the NPC.
@export var hit_awareness_radius: float = 160.0
## Seconds an incoming/nearby hit keeps the NPC on "under fire" alert (reported to Von, which
## re-decides at once). Also the window during which self-defense suspends the inside-gate.
@export var under_fire_time: float = 3.0
## Seconds the NPC stays committed to a fight after the last shot it fired or took, before it
## re-asks Von. Stops it dropping out of combat between the once-a-cadence decisions.
@export var engage_dwell: float = 3.0
## Memory cleanup: hard cap on remembered events (oldest evicted past it); <= 0 = unlimited.
@export var memory_capacity: int = 64
## Memory cleanup: fallback lifetime (s) for remembered events given no explicit ttl; <= 0 = no age
## expiry (events then persist until evicted by capacity).
@export var memory_default_ttl: float = 0.0
## How close (px) counts as "arrived" when steering straight-line (no nav agent).
@export var arrive_dist: float = 10.0
## NavigationAgent2D used for pathing (a sibling under the character); set in the NPC scene.
@export var nav_agent_path: NodePath
## How long (s) the NPC stays blocked against furniture before it shoves straight through as a last
## resort (when no route around exists, or it is wedged and barely moving).
@export var push_through_delay: float = 1.0
## Movement speed (px/s) under which the NPC counts as blocked while trying to follow a path.
@export var stuck_speed: float = 20.0

## The player the NPC senses and may act on, set by Main.
var target: Node2D
## World-space room rects (`{ key, type, rect }`) from Main — the sensor's map of the house.
var rooms: Array = []

var _perception: Node             ## Builds the state + menu each decision.
var _agent: NavigationAgent2D     ## Pathfinding agent, or null (falls back to straight-line).
var _safe_velocity := Vector2.ZERO ## Latest avoidance-adjusted velocity from the agent (RVO callback).
var _avoid_ready := false          ## Whether the agent's avoidance (max_speed) has been configured.
var _last_pos := Vector2.ZERO      ## Character position last path-move frame, for stuck detection.
var _stuck_time := 0.0             ## Seconds the NPC has been blocked while following a path.
var _push_through := false         ## True while shoving straight through a blocker (the last resort).
var _moves := {}                  ## This tick's move options by id (from the sensor).
var _acts := {}                   ## This tick's act options by id.
var _intent := "idle"             ## What the current act means to do: interact / combat / idle.
var _act_verb := "hold"           ## The chosen act's verb (shoot / punch / interact / hold).
var _target_obj: Node             ## The object to approach + use (interact intent), else null.
var _interact_id := ""            ## The interaction id to run on `_target_obj`.
var _move_point := Vector2.ZERO   ## Destination for an idle reposition.
var _has_move := false            ## Whether an idle move destination is set.
var _act_armed := false           ## Delays an interaction one frame so facing settles first.
var _combat_phase := "peek"       ## Peek-and-cover phase: "peek" (seek a shot) or "cover" (duck).
var _cover_timer := 0.0           ## Seconds left ducking behind cover before peeking again.
var _fire_timer := 0.0            ## Seconds left before the next shot/punch may be thrown.
var _combat_dest := Vector2.ZERO  ## Committed fire/cover position the NPC is steering toward.
var _combat_dest_timer := 0.0     ## Seconds left before a new combat position may be chosen.
var _hold_ground := false         ## Combat: return fire but stay inside the house (defending an outside attacker).
var _move_id := ""                ## Chosen move id, for the decision log.
var _act_log := "hold"            ## Chosen act id, for the decision log.
var _gated_hold := false          ## True when combat was gated to a hold (intruder still outside).
# Commitment state (the memory Von lacks).
var _in_interaction := false      ## Committed to an active object interaction.
var _interaction_timer := 0.0     ## Seconds left before ending the current interaction.
var _commit_timer := 0.0          ## Seconds left on the current approach commitment (safety cap).
var _decide_timer := 0.0          ## Seconds until the next decision is allowed.
var _force := false               ## Force a decision now (task resolved or salient event).
var _last_inside := false         ## Last-seen "player inside the house" state, for edge detection.
var _inside_init := false         ## Whether _last_inside has been seeded.
# Combat awareness (fed by EventBus &"hit" events, stored in _memory).
var _character: Node              ## The character this controller drives, captured on first control.
var _hit_queue: Array = []        ## Hit events awaiting processing once _character is known.
var _memory: RefCounted           ## Remembered events (under fire, engaged, …); see agent_memory.gd.
var _pending := false             ## True while a request is in flight.
var _http: HTTPRequest            ## Client for decision requests.


## Build the perception component, the HTTP client, and resolve the navigation agent.
func _ready() -> void:
	_perception = AgentPerception.new()
	add_child(_perception)
	_memory = AgentMemory.new()
	_memory.capacity = memory_capacity
	_memory.default_ttl = memory_default_ttl
	_http = HTTPRequest.new()
	_http.timeout = 3.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	EventBus.posted.connect(_on_event)
	if nav_agent_path != NodePath():
		_agent = get_node_or_null(nav_agent_path) as NavigationAgent2D
	if _agent != null:
		# RVO avoidance steers the NPC around furniture (tagged with NavigationObstacle2D by the
		# Navigation domain); max_speed is set from the character on the first control() tick.
		_agent.avoidance_enabled = true
		_agent.velocity_computed.connect(_on_avoidance_velocity)


## Buffer a world hit event for processing on the next control() tick (the signal can fire before
## the controller knows which character it drives).
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic == &"hit":
		_hit_queue.append(data)


## Called each physics frame by the character. Advances timers, honours the current commitment, asks
## for a new decision only when free to, then carries out the current act.
func control(character, delta: float) -> void:
	if target == null:
		return
	if _character == null:
		_character = character
	if _agent != null and not _avoid_ready:
		_agent.max_speed = character.speed
		_avoid_ready = true
	_decide_timer -= delta
	_commit_timer -= delta
	_process_hits(character)
	_check_salient()

	# An active interaction is held until its dwell runs out, the character leaves it, or a salient
	# event forces a rethink; then it ends and we fall through to decide.
	if _in_interaction:
		_interaction_timer -= delta
		if _force or not character.is_busy() or _interaction_timer <= 0.0:
			character.end_interaction()
			_in_interaction = false
			_force = true  # Pick the next step right away rather than wait out the cadence.
		else:
			return

	if _should_decide(character):
		_force = false
		_decide_timer = decide_interval
		_request_decision(character)

	_apply(character, delta)


## Whether a new decision may be issued now: never while one is in flight; always when forced; held
## back while committed to reaching a chosen object, to an idle destination (until the safety cap),
## or to a fight (while the `engaged` memory is fresh, so it keeps fighting rather than re-rolling a
## flat shoot/hold choice every cadence — peek-and-cover keeps tracking the player meanwhile).
func _should_decide(character) -> bool:
	if _pending:
		return false
	if _force:
		return true
	if _intent == "combat":
		return not _memory.is_fresh(&"engaged")
	if _intent == "interact":
		return _commit_timer <= 0.0
	if _intent == "idle" and _has_move and _commit_timer > 0.0 and not _reached(character, _move_point):
		return false
	return _decide_timer <= 0.0


## Classify buffered hit events against the character and remember them: a hit on the NPC itself, or
## a hit on anything within `hit_awareness_radius` (a shot landing close — being shot at and missed),
## both count as being fired upon and record the incoming direction. Each also refreshes the combat
## engagement so sustained fire keeps the NPC fighting. Any fresh hit forces an immediate
## re-decision (a salient event).
func _process_hits(character) -> void:
	if _hit_queue.is_empty():
		return
	var self_pos: Vector2 = character.global_position
	for data in _hit_queue:
		var hit_me: bool = data.get("victim") == character
		if not hit_me and self_pos.distance_to(data.get("position", self_pos)) > hit_awareness_radius:
			continue  # A hit too far away to notice.
		var from: Vector2 = -(data.get("direction", Vector2.RIGHT) as Vector2)
		_memory.remember(&"under_fire", {"from": from}, under_fire_time)
		_memory.remember(&"engaged", {}, engage_dwell)
		_force = true
	_hit_queue.clear()


## Whether the NPC is being fired upon right now — shot, or a shot landing close (shot at and missed)
## within the remembered window. Drives self-defense: it suspends the inside-gate and the state reads
## "under fire".
func _under_attack() -> bool:
	return _memory.is_fresh(&"under_fire")


## Force a re-decision when the player crosses the house boundary (the one event worth interrupting a
## commitment for). Seeded on the first call so the initial state isn't treated as a crossing.
func _check_salient() -> void:
	var inside := _inside_house(target.global_position)
	if not _inside_init:
		_last_inside = inside
		_inside_init = true
		return
	if inside != _last_inside:
		_last_inside = inside
		_force = true


## Whether a world point lies within any of the house's rooms (the "inside the house" test).
func _inside_house(p: Vector2) -> bool:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return true
	return false


## Carry out the current act. Movement and aim are both derived from what the NPC chose to do.
func _apply(character, delta: float) -> void:
	match _intent:
		"interact":
			_apply_interact(character)
		"combat":
			_apply_combat(character, delta)
		_:
			_apply_idle(character)


## Interact intent: face and walk to the chosen object; once its action is in reach, run it and hold
## the interaction. Drops to idle if the object is gone or the action can't start.
func _apply_interact(character) -> void:
	if _target_obj == null or not is_instance_valid(_target_obj):
		_intent = "idle"
		character.move_input = Vector2.ZERO
		return
	character.aim_point = _target_obj.global_position
	if not _interaction_in_reach(character):
		_path_move(character, _target_obj.global_position)
		return
	character.move_input = Vector2.ZERO
	if not _act_armed:
		_act_armed = true  # Let facing settle before acting.
		return
	if character.interact_with(_target_obj, _interact_id):
		_in_interaction = true
		_interaction_timer = interaction_dwell
	else:
		_intent = "idle"


## Combat intent: always face the player, then fight tactically. A punch just closes and swings; a
## shot runs the peek-and-cover cycle below. Firing is gated on a real line of sight, so the guard
## never shoots through walls, and paced by `fire_cooldown`. When combat is only happening because
## self-defense suspended the inside-gate (the attacker is still outside), the NPC returns fire but
## holds its ground inside the house rather than chasing the attacker out.
func _apply_combat(character, delta: float) -> void:
	character.aim_point = target.global_position
	_fire_timer -= delta
	_hold_ground = engage_only_inside and not _last_inside
	if _act_verb == "punch":
		_apply_melee(character)
		return
	_apply_peek_cover(character, delta)


## Peek-and-cover shooting: in the PEEK phase, move to a spot with a clear shot and fire, then duck;
## in the COVER phase, hold behind a shielding object for `cover_time` before peeking again. The
## fire/cover destination is committed for `reposition_interval` rather than re-picked every frame,
## so the NPC steers smoothly instead of vibrating between near-equal candidates.
func _apply_peek_cover(character, delta: float) -> void:
	var dist: float = character.global_position.distance_to(target.global_position)
	_combat_dest_timer -= delta
	if _combat_phase == "cover":
		_cover_timer -= delta
		if _combat_dest_timer <= 0.0:
			_combat_dest = _choose_combat_dest(character, "cover")
			_combat_dest_timer = reposition_interval
		_path_move(character, _combat_dest)
		if _cover_timer <= 0.0:
			_combat_phase = "peek"
			_combat_dest_timer = 0.0  # Re-pick a firing spot immediately on peeking out.
		return
	# PEEK: take the shot if we have a clear line in range, else reposition to get one.
	if dist <= shoot_range and _perception.has_shot(character, target):
		character.move_input = Vector2.ZERO
		if _fire_timer <= 0.0:
			_fire(character)
			_fire_timer = fire_cooldown
			_combat_phase = "cover"
			_cover_timer = cover_time
			_combat_dest_timer = 0.0  # Pick a cover spot immediately after shooting.
		return
	if _combat_dest_timer <= 0.0:
		_combat_dest = _choose_combat_dest(character, "peek")
		_combat_dest_timer = reposition_interval
	_path_move(character, _combat_dest)


## The committed destination for the current phase: the nearest spot with a clear shot (peek) or the
## nearest shielded spot (cover); falls back to closing on the player (peek) or holding (cover) when
## no suitable spot exists this sample. While holding ground (defending an outside attacker), spots
## are restricted to inside the house and the peek fallback holds position instead of advancing out,
## so the NPC returns fire from inside rather than pursuing the attacker.
func _choose_combat_dest(character, phase: String) -> Vector2:
	var spots: Dictionary = _perception.combat_spots(character, target, combat_ring_radius, combat_ring_count)
	var fire: Array = spots["fire"]
	var cover: Array = spots["cover"]
	if _hold_ground:
		fire = fire.filter(func(p): return _inside_house(p))
		cover = cover.filter(func(p): return _inside_house(p))
	if phase == "cover":
		return cover[0] if not cover.is_empty() else character.global_position
	if not fire.is_empty():
		return fire[0]
	return character.global_position if _hold_ground else target.global_position


## Melee combat: close to punch range and swing on the fire cooldown (no cover cycle for fists).
## While holding ground it won't chase an attacker out of the house — it only swings if one is
## already in reach.
func _apply_melee(character) -> void:
	if character.global_position.distance_to(target.global_position) > punch_range:
		if not _hold_ground:
			_path_move(character, target.global_position)
		else:
			character.move_input = Vector2.ZERO
		return
	character.move_input = Vector2.ZERO
	if _fire_timer <= 0.0:
		_fire(character)
		_fire_timer = fire_cooldown


## Equip the act's slot and throw one shot/punch, refreshing the combat engagement so an active
## fight stays committed.
func _fire(character) -> void:
	_memory.remember(&"engaged", {}, engage_dwell)
	var slot: int = _acts.get(_act_log, {}).get("slot", 0)
	if slot > 0:
		character.select_slot(slot)
	if _act_verb == "shoot":
		character.shoot()
	else:
		character.melee()


## Idle intent (hold): watch the player, and move to the chosen named destination if there is one.
func _apply_idle(character) -> void:
	character.aim_point = target.global_position
	if _has_move and not _reached(character, _move_point):
		_path_move(character, _move_point)
		return
	if _has_move:
		_has_move = false
		_force = true  # Arrived; pick the next step.
	character.move_input = Vector2.ZERO


## Whether the chosen interaction on `_target_obj` is currently reachable (lets the approach stop and
## the action begin).
func _interaction_in_reach(character) -> bool:
	for entry in character.interactions_in_reach():
		if entry["object"] != _target_obj:
			continue
		for spec in entry["specs"]:
			if spec.get("id", "") == _interact_id:
				return true
	return false


## Whether the NPC has reached `point` (nav path finished, or within arrive_dist straight-line).
func _reached(character, point: Vector2) -> bool:
	if _agent != null:
		_agent.target_position = point
		return _agent.is_navigation_finished()
	return character.global_position.distance_to(point) < arrive_dist


## Steer `character.move_input` toward `dest` along a navigated path (around walls and furniture,
## through doorways). The navmesh carves out furniture, so the path routes around a piece and reroutes
## through another doorway when one is blocked; RVO avoidance (fed each frame, applied from the
## previous frame's safe velocity) smooths steering around a piece just shoved. When no route exists
## at all (`is_target_reachable()` false) or the NPC stays wedged for `push_through_delay`, it shoves
## straight through the blocker as a last resort, using the character's own push physics.
## Falls back to plain straight-line steering when there is no navigation agent.
func _path_move(character, dest: Vector2) -> void:
	if _agent == null:
		var straight: Vector2 = dest - character.global_position
		character.move_input = Vector2.ZERO if straight.length() < arrive_dist else straight.normalized()
		return
	_agent.target_position = dest
	if _agent.is_navigation_finished():
		character.move_input = Vector2.ZERO
		_reset_stuck(character)
		return
	var next := _agent.get_next_path_position()
	var desired: Vector2 = next - character.global_position
	desired = desired.normalized() if desired.length() > 0.001 else Vector2.ZERO
	_agent.velocity = desired * character.speed  # Request this frame's avoidance-safe velocity.
	_update_stuck(character)
	if _push_through:
		# No route around (or wedged): drive straight at the blocker so the character shoves it.
		var aim: Vector2 = dest if not _agent.is_target_reachable() else next
		character.move_input = (aim - character.global_position).normalized()
	elif character.speed > 0.0:
		character.move_input = _safe_velocity / character.speed  # Length <= 1 (push-strength scaling).
	else:
		character.move_input = desired


## Store the agent's avoidance-adjusted velocity; `_path_move` applies it the next frame (writing
## move_input synchronously there, like every other act, rather than from this async callback).
func _on_avoidance_velocity(safe_velocity: Vector2) -> void:
	_safe_velocity = safe_velocity


## Track whether the NPC is blocked while pathing and flip `_push_through` once it has been blocked
## for `push_through_delay`. Blocked = the target is unreachable (furniture seals every route) or the
## character advanced less than `stuck_speed` this frame.
func _update_stuck(character) -> void:
	var step := get_physics_process_delta_time()
	var moved: float = character.global_position.distance_to(_last_pos)
	_last_pos = character.global_position
	if not _agent.is_target_reachable() or moved < stuck_speed * step:
		_stuck_time += step
	else:
		_stuck_time = 0.0
	_push_through = _stuck_time >= push_through_delay


## Clear stuck/push-through state when the NPC arrives or stops pathing.
func _reset_stuck(character) -> void:
	_stuck_time = 0.0
	_push_through = false
	_last_pos = character.global_position


## Sense the situation and POST it with the `move` and `act` `choice` questions. Falls back to a
## steady stance if the request can't even be started.
func _request_decision(character) -> void:
	var ctx: Dictionary = _perception.sense(character, target, rooms, goal, _memory)
	_moves = ctx["moves"]
	_acts = ctx["acts"]
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
	else:
		_fallback()
		print("NPC (Von) request failed to start — holding steady")


## A `choice` question whose criteria map each option id to its human-readable description.
func _question(instructions: String, options: Dictionary) -> Dictionary:
	var criteria := {}
	for id in options:
		criteria[id] = options[id]["desc"]
	return { "type": "choice", "instructions": instructions, "criteria": criteria }


## Read the answers and adopt Von's top pick for each; fall back to a steady stance on failure.
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
	_set_act(_pick(answers, "act", _acts))
	_set_move(_pick(answers, "move", _moves))
	print("NPC (Von) act=%s move=%s intent=%s" % [_act_log, _move_id, _intent])


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


## Adopt the chosen act: resolve its verb into an intent (interact / combat / idle), capture the
## object + id for an interaction, commit to reaching it, and re-arm the one-frame action delay.
func _set_act(id: String) -> void:
	var opt: Dictionary = _acts.get(id, {})
	_act_verb = opt.get("verb", "hold")
	_act_log = id if id != "" else "hold"
	_act_armed = false
	_gated_hold = false
	if (_act_verb == "shoot" or _act_verb == "punch") and engage_only_inside and not _last_inside \
			and not _under_attack():
		# House guard: hold rather than engage an intruder who is still outside the house — unless
		# fired upon (hit or shot at), when self-defense overrides the restraint and it may engage.
		_act_verb = "hold"
		_act_log = "hold(outside)"
		_gated_hold = true
	match _act_verb:
		"interact":
			_intent = "interact"
			_target_obj = opt.get("object")
			_interact_id = opt.get("id", "")
			_commit_timer = max_commit_time
		"shoot", "punch":
			_intent = "combat"
			_target_obj = null
			_memory.remember(&"engaged", {}, engage_dwell)  # Commit to the fight (refreshed by firing).
		_:
			_intent = "idle"
			_target_obj = null


## Adopt the chosen idle destination (used only when the act is "hold").
func _set_move(id: String) -> void:
	_move_id = id
	_has_move = not _gated_hold and id != "" and _moves.has(id)
	if _has_move:
		_move_point = _moves[id]["point"]
		if _intent == "idle":
			_commit_timer = max_commit_time


## A steady, non-chaotic stance for when Von is unreachable (server-down path): stop and watch the
## player rather than thrash between random options.
func _fallback() -> void:
	_intent = "idle"
	_target_obj = null
	_has_move = false
	_act_verb = "hold"
	_act_log = "hold"
	_move_id = ""
