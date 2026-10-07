extends Node

## AI domain ORCHESTRATOR: a generic, goal-driven controller for a non-player character. It is the AI's
## own composition root (the `main.gd` of the AI domain): it wires the three AI sub-domains and runs the
## SENSE → THINK → ACT loop, but holds almost no behaviour itself. It satisfies the character's
## controller contract (`control(character, delta)`) and writes only the intent the player controller
## writes (`move_input`/`aim_point`) plus the same public actions — all of that done by the behaviour
## sub-domain. It is the single authoring surface: every tunable below is an export here (so a defender
## or invader preset is all data on this one node), copied into the sub-modules it builds.
##
## The three sub-domains (see their `domain-ai-<name>` skills):
##   • PERCEPTION (perception/) — SENSE. What the NPC knows: the sight sense, hostility rules and event
##     memory, the known-contacts view, the decision context (state + act/move menus) and combat
##     geometry. The NPC is NOT omniscient — it acts on last-KNOWN positions and forgets what decays.
##   • DECISION (decision/) — THINK. The round-trip to the local Von "System One" server: it POSTs the
##     context as two `choice` questions (WHAT to do, and — only if holding — WHERE), and reports Von's
##     top pick back via `decided` / `failed`.
##   • BEHAVIOUR (behavior/) — ACT. Turns the chosen act into movement + actions, and holds the
##     System-Two state Von lacks: the engaged contact, peek-and-cover, patrol, the interaction in
##     progress, and the COMMITMENT timers that let multi-step goals advance instead of oscillating.
##
## This file keeps only the ORCHESTRATION: the control loop, the decide cadence, forcing a re-decision
## on a salient event (the known-hostile set changing) or a resolved task, and the EventBus hit intake.
## The behaviour is pure DATA — `goal` plus the generic primitives exported below (hostility, pursuit,
## territory, flanking); a house defender and a house invader are the same code with different data.

const AgentPerception := preload("res://scenes/ai/perception/agent_perception.gd")
const DecisionClient := preload("res://scenes/ai/decision/decision_client.gd")
const Behavior := preload("res://scenes/ai/behavior/behavior.gd")

## The behaviour to pursue, in plain language — what Von ranks the act menu against.
@export_multiline var goal: String = ("Deal with hostile characters: shoot them with your pistol. " +
	"Otherwise go about your business.")
## Pursuit primitive: when true this NPC actively hunts hostiles instead of doing chores. While no
## hostile is known it patrols the house to search (rather than settling into a passive interaction,
## which freezes its facing and blinds it); once one is known it ENGAGES rather than picking an
## unrelated interaction — the large object-interaction menu otherwise dilutes Von's choice. Turn off
## for an NPC whose goal is unrelated to fighting (e.g. "watch tv"). Like the other primitives, this
## is a controller policy Von (a single-shot ranker) can't apply itself.
@export var pursue_hostiles: bool = true
## Territory primitive: when true, while engaging a contact that is OUTSIDE the house the NPC returns
## fire from inside (fire/cover spots restricted to the house, no advancing out) instead of chasing it.
@export var defend_territory: bool = false
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
## Range (px) within which a chosen shot is fired instead of advancing on the engaged contact.
@export var shoot_range: float = 500.0
## Range (px) within which a chosen punch lands instead of advancing on the engaged contact.
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
## Flanking primitive: when true, firing spots are chosen to attack from the target's side/rear and
## to spread allied attackers around it (a pincer), rather than always taking the nearest spot. It
## re-ranks the peek fire spots by angular openness — distance from the bearings the NPC should avoid
## (where a visible target is FACING, and where each nearby ally already stands) — traded against
## travel distance. Off, or with no such bearings to avoid, it reverts to nearest-spot (the old
## behaviour), so flanking is purely additive.
@export var flank: bool = true
## How far (px) the NPC will travel for a fully-open flanking angle: the px-value of going from the
## worst angle (right on an avoided bearing) to the best (opposite it). Higher = flanks harder.
@export var flank_weight: float = 140.0
## An ally within this distance (px) of the engaged target counts as holding an angle on it, so this
## NPC spreads to a different bearing instead of stacking alongside the ally.
@export var flank_ally_radius: float = 500.0
## Radius (px) within which a hit on something else still registers as gunfire near the NPC.
@export var hit_awareness_radius: float = 160.0
## Seconds an incoming/nearby hit keeps the NPC on "under fire" alert (reported to Von, which
## re-decides at once).
@export var under_fire_time: float = 3.0
## Seconds the NPC stays committed to a fight after the last shot it fired or took, before it
## re-asks Von. Stops it dropping out of combat between the once-a-cadence decisions.
@export var engage_dwell: float = 3.0
## Memory cleanup: hard cap on remembered events (oldest evicted past it); <= 0 = unlimited.
@export var memory_capacity: int = 64
## Memory cleanup: fallback lifetime (s) for remembered events given no explicit ttl; <= 0 = no age
## expiry (events then persist until evicted by capacity).
@export var memory_default_ttl: float = 0.0

@export_group("Vision")
## Whether sight is gated at all. Off = the NPC is omniscient (pre-vision behaviour), for debugging.
@export var vision_enabled: bool = true
## Maximum distance (px) at which the NPC can see anything.
@export var view_distance: float = 2520.0
## Full angular width (degrees) of the forward view cone, centred on the NPC's facing (its aim).
@export var fov_degrees: float = 110.0
## Radius (px) of a 360° near-awareness bubble: things this close are sensed regardless of facing.
@export var awareness_radius: float = 48.0
## Whether this NPC starts already knowing the house (its rooms + objects). Off = it must see them
## first. People are never pre-known either way — they are known only once seen.
@export var familiar_with_house: bool = true
## Lifetime (s) of a character sighting — the window the NPC keeps acting on a last-seen position
## after losing sight before it forgets that contact.
@export var contact_memory_ttl: float = 4.0

@export_group("Hostility")
## Every non-allied character seen is hostile (e.g. an invader).
@export var hostile_on_sight: bool = false
## A non-allied character seen inside the house is hostile (e.g. a defender).
@export var hostile_on_trespass: bool = false
## A non-allied character that attacks this NPC — hits it, or shoots close to it — is hostile.
@export var hostile_on_attack: bool = true
## Lifetime (s) of a hostility verdict; <= 0 = permanent (a grudge never fades).
@export var hostility_ttl: float = 0.0
## Factions treated as allies besides the NPC's own (its character's `faction`); never hostile.
@export var allied_factions: Array[StringName] = []

@export_group("")
## How close (px) counts as "arrived" when steering straight-line (no nav agent).
@export var arrive_dist: float = 10.0
## NavigationAgent2D used for pathing (a sibling under the character); set in the NPC scene.
@export var nav_agent_path: NodePath
## How long (s) the NPC stays blocked against furniture before it shoves straight through as a last
## resort (when no route around exists, or it is wedged and barely moving).
@export var push_through_delay: float = 1.0
## Movement speed (px/s) under which the NPC counts as blocked while trying to follow a path.
@export var stuck_speed: float = 20.0
## How close (px) a shut door must be, while the NPC is blocked on its path, for it to deliberately
## open the door instead of shoving through. Doorways stay walkable in the navmesh (doors are
## nav-invisible), so the NPC paths up to a closed door and opens it. 0 disables door-opening.
@export var door_open_reach: float = 40.0

## World-space room rects (`{ key, type, rect }`) from Main — the sensor's map of the house.
var rooms: Array = []
## The house entrance in world space, injected by Main for NPCs that start outside (e.g. the
## invader). When set, the patrol heads here first while the NPC is outside all rooms, giving the
## shortest direct path to the entrance instead of circling. Cleared after first use.
var entry_point: Vector2 = Vector2.ZERO

var _perception: Node             ## SENSE sub-domain: knowledge, decision context, combat geometry.
var _decision: Node               ## THINK sub-domain: the Von round-trip (decision/decision_client.gd).
var _behavior: Node               ## ACT sub-domain: derives movement/actions + holds commitment state.
var _acts := {}                   ## This tick's act options (from perception), brokered to the behaviour on decide.
var _moves := {}                  ## This tick's move options.
var _decide_timer := 0.0          ## Seconds until the next decision is allowed.
var _force := false               ## Force a decision now (task resolved or salient event).
var _salient_key := ""            ## Known-hostile set + engaged contact's inside state, for edge detection.
var _salient_init := false        ## Whether _salient_key has been seeded.
# EventBus &"hit" events are queued here, then handed to perception on the next control() tick.
var _character: Node              ## The character this controller drives, captured on first control.
var _hit_queue: Array = []        ## Hit events awaiting processing once _character is known.


## Build + configure the three AI sub-domains and wire them together. The controller is the single
## authoring surface: every tunable lives as an export here and is copied onto the sub-module it belongs
## to (perception owns the senses, decision the Von endpoint, behaviour the combat/movement + its
## locomotion).
func _ready() -> void:
	# SENSE: the perception sub-domain owns the sight sense, hostility rules and event memory internally.
	_perception = AgentPerception.new()
	_perception.contact_memory_ttl = contact_memory_ttl
	_perception.familiar_with_house = familiar_with_house
	_perception.vision_enabled = vision_enabled
	_perception.view_distance = view_distance
	_perception.fov_degrees = fov_degrees
	_perception.awareness_radius = awareness_radius
	_perception.hostile_on_sight = hostile_on_sight
	_perception.hostile_on_trespass = hostile_on_trespass
	_perception.hostile_on_attack = hostile_on_attack
	_perception.hostility_ttl = hostility_ttl
	_perception.allied_factions = allied_factions
	_perception.memory_capacity = memory_capacity
	_perception.memory_default_ttl = memory_default_ttl
	_perception.hit_awareness_radius = hit_awareness_radius
	_perception.under_fire_time = under_fire_time
	_perception.engage_dwell = engage_dwell
	_perception.setup()
	add_child(_perception)
	# THINK: the decision sub-domain, the Von round-trip. It reports its pick via `decided` / `failed`.
	_decision = DecisionClient.new()
	_decision.configure(server_url, model, 3.0)
	add_child(_decision)
	_decision.decided.connect(_on_decided)
	# ACT: the behaviour sub-domain (owns its own locomotion). It reads the world via perception and
	# falls back to a steady stance when the decision request fails.
	_behavior = Behavior.new()
	_behavior.pursue_hostiles = pursue_hostiles
	_behavior.defend_territory = defend_territory
	_behavior.interaction_dwell = interaction_dwell
	_behavior.max_commit_time = max_commit_time
	_behavior.shoot_range = shoot_range
	_behavior.punch_range = punch_range
	_behavior.combat_ring_radius = combat_ring_radius
	_behavior.combat_ring_count = combat_ring_count
	_behavior.cover_time = cover_time
	_behavior.fire_cooldown = fire_cooldown
	_behavior.reposition_interval = reposition_interval
	_behavior.flank = flank
	_behavior.flank_weight = flank_weight
	_behavior.flank_ally_radius = flank_ally_radius
	_behavior.arrive_dist = arrive_dist
	_behavior.push_through_delay = push_through_delay
	_behavior.stuck_speed = stuck_speed
	_behavior.door_open_reach = door_open_reach
	var nav_agent: NavigationAgent2D = null
	if nav_agent_path != NodePath():
		nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent2D
	_behavior.setup(_perception, nav_agent)
	add_child(_behavior)
	_decision.failed.connect(_behavior.fallback)
	EventBus.posted.connect(_on_event)


## Buffer a world hit event for processing on the next control() tick (the signal can fire before
## the controller knows which character it drives).
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic == &"hit":
		_hit_queue.append(data)


## Read-only: the act the NPC is currently carrying out (its last decision), for observers/HUD.
func current_act() -> String:
	return _behavior.current_act() if _behavior != null else "hold"


## Read-only: a compact, human-readable summary of what the NPC is doing right now — for debug
## overlays/observers (the behaviour sub-domain builds it from its live act state).
func debug_status() -> String:
	return _behavior.debug_status() if _behavior != null else "IDLE"


## Called each physics frame by the character. Runs the SENSE → THINK → ACT loop: fold any hits in,
## perceive, let the behaviour resolve what it knows + honour its commitments, ask Von for a new
## decision only when free to, then let the behaviour carry out the current act.
func control(character, delta: float) -> void:
	if character.is_dead:
		return
	if _character == null:
		_character = character
		_perception.set_faction(character.faction)
	_decide_timer -= delta
	# SENSE.
	_process_hits(character)
	_perception.observe(character, rooms)
	_behavior.rooms = rooms
	if entry_point != Vector2.ZERO:
		_behavior.entry_point = entry_point  # Hand the injected entrance to the behaviour once.
		entry_point = Vector2.ZERO
	var known: Array = _perception.contacts(character.global_position)
	if _behavior.update_known(character, known, delta):
		_force = true  # Lost the engaged contact mid-fight → reconsider.
	_check_salient()
	# An active interaction holds the tick; when it or an idle move resolves, re-decide at once.
	if _behavior.service_interaction(character, delta, _force):
		return
	if _behavior.take_resolved():
		_force = true
	# THINK.
	if _should_decide():
		_force = false
		_decide_timer = decide_interval
		_request_decision(character)
	# ACT.
	_behavior.apply(character, delta)


## Whether a new decision may be issued now: never while one is in flight; always when forced;
## otherwise the behaviour decides whether its current commitment still holds (a fight, an approach, a
## search patrol, an idle move) or the decide cadence has elapsed.
func _should_decide() -> bool:
	if _decision.is_pending():
		return false
	if _force:
		return true
	return _behavior.wants_decision(_character, _decide_timer <= 0.0)


## Classify buffered hit events against the character and remember them: a hit on the NPC itself, or
## a hit on anything within `hit_awareness_radius` (a shot landing close — being shot at and missed),
## both count as being attacked: the incoming direction is remembered, the attacker is handed to the
## hostility rules, and the combat engagement is refreshed so sustained fire keeps the NPC fighting.
## The NPC's own hits are ignored. A hit forces an immediate re-decision only when it is NOT already
## in combat (to kick off a fight); while fighting it just refreshes the engagement, so a firefight
## doesn't re-ask Von every frame.
func _process_hits(character) -> void:
	if _hit_queue.is_empty():
		return
	for data in _hit_queue:
		# Perception folds the hit into memory + hostility; a relevant attack kicks off a fight when
		# not already in one (while fighting it only refreshes the engagement, no re-ask every frame).
		if _perception.process_hit(character, data) and not _behavior.in_combat():
			_force = true
	_hit_queue.clear()


## Force a re-decision when the NPC's BELIEF about hostiles changes: one is spotted, lost or newly
## categorized hostile, or the engaged contact crosses the house boundary (per its last sighting).
## These are the events worth interrupting a commitment for. The behaviour sub-domain packs that belief
## into a salient key; seeded on the first call so the initial state isn't a "change".
func _check_salient() -> void:
	var key: String = _behavior.salient_key()
	if not _salient_init:
		_salient_key = key
		_salient_init = true
		return
	if key != _salient_key:
		_salient_key = key
		_force = true


## Sense the situation and hand the decision context to the Von client. It answers asynchronously via
## `decided` / `failed` (the latter wired to the behaviour's steady-stance fallback). The menus are
## kept so the chosen ids can be resolved back into acts/moves by the behaviour when the answer arrives.
func _request_decision(character) -> void:
	var ctx: Dictionary = _perception.sense(character, rooms, goal)
	_moves = ctx["moves"]
	_acts = ctx["acts"]
	_decision.request(ctx, _npc_name())


## Adopt Von's top pick (relayed by the decision client): hand the chosen act + move to the behaviour
## sub-domain and log the resulting intent.
func _on_decided(act_id: String, move_id: String) -> void:
	_behavior.set_act(act_id, _acts)
	_behavior.set_move(move_id, _moves)
	print("%s (Von) act=%s move=%s intent=%s" % [_npc_name(), _behavior.current_act(), move_id, _behavior.intent()])


## The driven character's name, for log lines.
func _npc_name() -> String:
	return str(_character.name) if _character != null else "NPC"

