extends Node

## AI domain ORCHESTRATOR: a generic, goal-driven controller for a non-player character. It is the AI's
## own composition root (the `main.gd` of the AI domain): it wires the three AI sub-domains and runs the
## SENSE → THINK → ACT loop, but holds almost no behaviour itself. It satisfies the character's
## controller contract (`control(character, delta)`) and writes only the intent the player controller
## writes (`move_input`/`aim_point`) plus the same public actions — all of that done by the behaviour
## sub-domain. It is the single authoring surface: every tunable below is an export here (so a defender
## or invader preset is all data on this one node), pushed into the sub-modules it builds — and
## re-pushed each decision, so a tunable retuned at runtime (a behaviour test, the dev command server)
## takes effect without a rebuild.
##
## The three sub-domains (see their `domain-ai-<name>` skills):
##   • PERCEPTION (perception/) — SENSE. What the NPC knows: sight, hostility, event memory, the
##     known-contacts view, combat geometry, and the decision SNAPSHOT (state sections, facts and
##     option groups). The NPC is NOT omniscient — it acts on last-KNOWN positions and forgets what decays.
##   • DECISION (decision/) — THINK. The decision TREE and its planner: Von picks top-down, one `choice`
##     request per level — a broad mode (combat / investigate / search / idle), the hostile, a tactic
##     (engage / flank / push / retreat …), then a concrete option — ending in one behaviour primitive.
##   • BEHAVIOUR (behavior/) — ACT. Runs the chosen primitive (move / engage / melee / interact / hold) as
##     movement + actions, and holds the System-Two state Von lacks: the engaged contact,
##     peek-and-cover, the interaction in progress, and the commitment that keeps a choice running.
##
## This file keeps only the ORCHESTRATION: the control loop, the decide cadence, forcing a re-decision
## on a salient event or a finished task (interrupting a walk in flight when the situation now calls for
## a different starting point — e.g. under fire → straight to combat), the EventBus intake (hits and
## allies' radio callouts) and posting this NPC's own callouts. The behaviour is pure DATA — `goal` plus
## the generic primitives and decision config exported below; a house defender and a house invader are
## the same code with different data.

const AgentPerception := preload("res://scenes/ai/perception/agent_perception.gd")
const DecisionClient := preload("res://scenes/ai/decision/decision_client.gd")
const DecisionPlanner := preload("res://scenes/ai/decision/decision_planner.gd")
const Behavior := preload("res://scenes/ai/behavior/behavior.gd")

## The behaviour to pursue, in plain language — what Von ranks every level of the decision against.
@export_multiline var goal: String = ("Deal with hostile characters: shoot them with your pistol. " +
	"Otherwise go about your business.")
## Pursuit primitive: when true this NPC actively hunts hostiles instead of doing chores. Once a hostile
## is known every decision starts at COMBAT, and IDLE (chores) is never offered — a passive interaction
## freezes the NPC's facing and blinds it. Turn off for an NPC whose goal is unrelated to fighting.
@export var pursue_hostiles: bool = true
## Territory primitive: when true the NPC fights from inside the house — combat options outside it are
## never offered, and it won't chase a contact out of the house.
@export var defend_territory: bool = false
## The `/v1/systemone` endpoint to ask.
@export var server_url: String = "http://127.0.0.1:8000/v1/systemone"
## Model name sent with each request.
@export var model: String = "von-1.2.0"
## Minimum seconds between decisions while holding (the re-decide cadence once free to change).
@export var decide_interval: float = 1.0
## Seconds to stay in a chosen interaction before ending it and re-deciding (covers Von's
## statelessness so multi-step goals advance).
@export var interaction_dwell: float = 3.0
## Safety cap (s) on committing to a move or to reaching an object, so a blocked path still re-decides.
@export var max_commit_time: float = 6.0
## Seconds the NPC pauses to look around a room on reaching it while searching/exploring, before deciding
## where to go next. Stops it re-deciding the instant it crosses a room's edge (and bouncing on the boundary).
@export var search_dwell: float = 2.5
## Range (px) of the pistol: shots are taken within it, and distances are banded against it for Von.
@export var shoot_range: float = 500.0
## Range (px) within which a punch lands.
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
## re-decides at once).
@export var under_fire_time: float = 3.0
## Seconds the NPC stays committed to a fight after the last shot it fired or took, before it
## re-asks Von. Stops it dropping out of combat between decisions.
@export var engage_dwell: float = 3.0

@export_group("Decision")
## Decision-tree nodes never offered to this NPC (see scenes/ai/decision/decision_tree.gd), e.g.
## [&"advance"] for one that never closes in. `pursue_hostiles` adds &"idle".
@export var disabled_nodes: Array[StringName] = []
## Per-node overrides merged over the tree's defaults: { node_id: { field: value } } — e.g. a different
## `question` for &"flank".
@export var node_overrides: Dictionary = {}
## Ordered fact → node: a decision starts at the first rule's node whose fact holds, skipping the
## broader levels above it (e.g. under fire → straight to COMBAT). `pursue_hostiles` adds
## hostile_known → combat. Facts: see the perception snapshot.
@export var entry_rules: Dictionary = { &"under_fire": &"combat", &"engaged": &"combat" }
## Take a level's only option without asking Von (saves a round-trip per auto-picked level).
@export var skip_single_option: bool = true
## Most options offered at one level (positions, rooms, leads); interactions are not capped.
@export var max_options_per_level: int = 4
## Seconds a fight runs before Von re-chooses its tactic (it re-chooses sooner if the fight lapses).
@export var tactic_interval: float = 3.0

@export_group("Context")
## Ages (s) up to which something counts as "just now" (x) and "recently" (y); older is "a while ago".
@export var recency_bands: Vector2 = Vector2(2.0, 8.0)
## Route lengths (px) up to which a route is "short" (x) and "medium" (y); longer is "long".
@export var route_buckets: Vector2 = Vector2(400.0, 900.0)
## Half-angle (degrees) within which a seen character's facing counts as aiming at someone.
@export var aim_cone: float = 20.0
## Speed (px/s) under which a seen character counts as standing still.
@export var still_speed: float = 20.0
## Smoothing (0–1) of a seen character's tracked velocity; higher follows changes faster.
@export var track_smoothing: float = 0.3
## Radius (px) within which a hit elsewhere is heard as gunfire (an investigation lead).
@export var hearing_radius: float = 900.0
## Most seconds a lost hostile's last-seen velocity is projected forward ("where they were heading").
@export var extrapolate_cap: float = 3.0
## Distance (px) toward unseen gunfire the "where the shots came from" lead points.
@export var investigate_distance: float = 300.0
## Accumulated damage (see Character.damage_taken) at or above which a character reads as "hurt".
@export var hurt_threshold: float = 15.0
## Accumulated damage at or above which a character reads as "badly wounded".
@export var critical_threshold: float = 35.0
## Most contacts described in the decision state (hostiles first, then nearest).
@export var max_contacts_in_state: int = 4

@export_group("Tactics")
## Surface coverage (0–100) at or above which a blocking object counts as usable cover.
@export var cover_min: float = 40.0
## Distance (px) from a target at which a flanking spot is sought.
@export var flank_distance: float = 220.0
## Angular spread (degrees) sampled around each flank side's bearing.
@export var flank_arc: float = 60.0
## An ally within this distance (px) of a target holds the side it stands on, so this NPC is told that
## side is taken.
@export var flank_ally_radius: float = 500.0
## A route that comes within this distance (px) of a known hostile, nearer than the NPC already is,
## passes them: such a flank side is never offered, nor is such a firing spot.
@export var route_clearance: float = 120.0
## Full width (degrees) of the cone around a hostile's front in which it counts as looking. A firing
## spot in the open inside that cone, with a clear line from the hostile, is never offered.
@export var watch_arc: float = 90.0
## Distances (px) from a target at which firing spots around it are sampled (besides those a step or
## two from the NPC).
@export var fire_spot_distances: Array[float] = [200.0, 350.0]

@export_group("Memory")
## Hard cap on remembered events (oldest expirable evicted past it); <= 0 = unlimited.
@export var memory_capacity: int = 128
## Fallback lifetime (s) for remembered events given no explicit ttl; <= 0 = no age expiry.
@export var memory_default_ttl: float = 0.0
## Seconds a lost hostile's last sighting stays an investigation lead.
@export var lead_memory_ttl: float = 20.0
## Seconds a visited room counts as recently searched.
@export var search_memory_ttl: float = 60.0

@export_group("Callouts")
## Broadcast this NPC's combat and investigation decisions to allies over the EventBus.
@export var send_callouts: bool = true
## Listen to allies' callouts (their tactic, target and destination).
@export var hear_callouts: bool = true
## How far (px) a callout carries; <= 0 = unlimited.
@export var callout_range: float = 1500.0
## Seconds a heard callout stays current.
@export var callout_ttl: float = 6.0

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
## after losing sight before the contact becomes a mere investigation lead.
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

## World-space room rects (`{ key, type, rect }`) from Main — the sensor's map of the house.
var rooms: Array = []
## The house entrance in world space, injected by Main for NPCs that start outside. Handed to the
## perception once (it offers "the front entrance" as a search option while outside).
var entry_point: Vector2 = Vector2.ZERO

var _perception: Node ## SENSE sub-domain: knowledge, the decision snapshot, combat geometry.
var _client: Node ## THINK transport: the Von round-trip (decision/decision_client.gd).
var _planner: Node ## THINK policy: the decision-tree walk (decision/decision_planner.gd).
var _behavior: Node ## ACT sub-domain: runs the chosen primitive + holds commitment state.
var _last_facts := {} ## The facts of the last decision snapshot, retained for `debug_state()`.
var _last_options := {} ## The option groups of the last snapshot, retained for `debug_zones()`.
var _decide_timer := 0.0 ## Seconds until the next decision is allowed.
var _force := false ## Force a decision now (task resolved or salient event).
var _salient_key := "" ## Known-hostile set + engaged contact's inside state, for edge detection.
var _salient_init := false ## Whether _salient_key has been seeded.
# EventBus events are queued here, then handed to perception on the next control() tick.
var _character: Node ## The character this controller drives, captured on first control.
var _event_queue: Array = [] ## [topic, data] pairs awaiting processing once _character is known.


## Build the AI sub-domains and wire them together, then push every export into them with
## _apply_config(). The sub-domains each own internal modules (perception's sight/hostility/memory/
## tactics, the behaviour's locomotion), so building and configuring are separate: _ready() builds
## once, _apply_config() configures (here and again each decision, so a tunable retuned at runtime
## still takes effect without a rebuild that would wipe memory or in-flight state).
func _ready() -> void:
	# SENSE: the perception sub-domain owns sight, hostility, memory and the combat geometry internally.
	_perception = AgentPerception.new()
	add_child(_perception)
	_perception.setup()
	# THINK: the Von transport, and the planner that walks the decision tree through it. node_overrides
	# is baked into the tree at setup() (construction-time only); the rest of the planner's config is
	# applied by _apply_config(), which turns the policy primitives into tree config (pursuit starts at
	# COMBAT once a hostile is known and never idles; territory keeps combat options inside the house).
	_client = DecisionClient.new()
	_client.configure(server_url, model, 3.0)
	add_child(_client)
	_planner = DecisionPlanner.new()
	_planner.node_overrides = node_overrides
	add_child(_planner)
	# ACT: the behaviour sub-domain (owns its own locomotion). It reads the world via perception and
	# falls back to a steady stance when no decision can be had.
	_behavior = Behavior.new()
	var nav_agent: NavigationAgent2D = null
	if nav_agent_path != NodePath():
		nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent2D
	add_child(_behavior)
	_behavior.setup(_perception, nav_agent)
	_apply_config()
	_planner.setup(_client)
	_planner.decided.connect(_on_decided)
	_planner.failed.connect(_behavior.fallback)
	EventBus.posted.connect(_on_event)


## Push every export into the sub-domains it configures. The controller is the single authoring surface
## — every tunable lives as an export here — and this is where they reach the sub-modules. It only SETS
## config on already-built sub-domains (never rebuilds), so it is safe to call each decision: a tunable
## retuned at runtime (e.g. by the dev command server for a behaviour test) takes effect on the next one.
func _apply_config() -> void:
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
	_perception.lead_memory_ttl = lead_memory_ttl
	_perception.search_memory_ttl = search_memory_ttl
	_perception.hit_awareness_radius = hit_awareness_radius
	_perception.hearing_radius = hearing_radius
	_perception.under_fire_time = under_fire_time
	_perception.engage_dwell = engage_dwell
	_perception.shoot_range = shoot_range
	_perception.punch_range = punch_range
	_perception.recency_bands = recency_bands
	_perception.route_buckets = route_buckets
	_perception.aim_cone = aim_cone
	_perception.still_speed = still_speed
	_perception.track_smoothing = track_smoothing
	_perception.extrapolate_cap = extrapolate_cap
	_perception.investigate_distance = investigate_distance
	_perception.hurt_threshold = hurt_threshold
	_perception.critical_threshold = critical_threshold
	_perception.max_contacts_in_state = max_contacts_in_state
	_perception.cover_min = cover_min
	_perception.max_options_per_level = max_options_per_level
	_perception.flank_distance = flank_distance
	_perception.flank_arc = flank_arc
	_perception.flank_ally_radius = flank_ally_radius
	_perception.combat_ring_radius = combat_ring_radius
	_perception.combat_ring_count = combat_ring_count
	_perception.route_clearance = route_clearance
	_perception.watch_arc = watch_arc
	_perception.fire_spot_distances = fire_spot_distances
	_perception.callout_range = callout_range
	_perception.callout_ttl = callout_ttl
	_perception.apply_config()
	# The pursuit/territory primitives become planner config: pursuit disables IDLE and starts a walk at
	# COMBAT once a hostile is known; territory confines combat options inside the house.
	var disabled: Array[StringName] = []
	disabled.assign(disabled_nodes)
	var rules := entry_rules.duplicate()
	if pursue_hostiles:
		if not disabled.has(&"idle"):
			disabled.append(&"idle")
		if not rules.has(&"hostile_known") and not rules.has("hostile_known"):
			rules[&"hostile_known"] = &"combat"
	_planner.disabled_nodes = disabled
	_planner.entry_rules = rules
	_planner.skip_single_option = skip_single_option
	_planner.inside_only = defend_territory
	_behavior.interaction_dwell = interaction_dwell
	_behavior.max_commit_time = max_commit_time
	_behavior.search_dwell = search_dwell
	_behavior.tactic_interval = tactic_interval
	_behavior.shoot_range = shoot_range
	_behavior.punch_range = punch_range
	_behavior.combat_ring_radius = combat_ring_radius
	_behavior.combat_ring_count = combat_ring_count
	_behavior.cover_time = cover_time
	_behavior.fire_cooldown = fire_cooldown
	_behavior.reposition_interval = reposition_interval
	_behavior.arrive_dist = arrive_dist
	_behavior.apply_config()


## Buffer a world event for processing on the next control() tick (the signal can fire before the
## controller knows which character it drives): hits (combat awareness, gunfire heard) and allies'
## radio callouts.
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic == &"hit" or topic == &"callout":
		_event_queue.append([topic, data])


## Read-only: the decision path the NPC is carrying out, as ids ("combat/t_12/flank/side_left").
func current_act() -> String:
	return _behavior.current_act() if _behavior != null else "hold"


## Read-only: the full decision path the NPC is carrying out, every level ("COMBAT - Intruder - FLANK -
## their left side (kitchen)"), plus its progress — for debug overlays/observers.
func debug_status() -> String:
	return _behavior.debug_status() if _behavior != null else "HOLD"


## Read-only: the WHOLE AI state as structured data — the deep counterpart to `debug_status()`'s
## one-line label, for an observer (the dev command server) to inspect on demand. It answers what a log
## line can't: the facts the last decision gated on, every level of the last walk (the exact state and
## question Von saw, the options, its probabilities and pick, auto-picks and timings), what the NPC
## knows (`contacts`), the running primitive and pathing. Pure reads — never perturbs the loop.
func debug_state() -> Dictionary:
	var out := {
		"npc": _npc_name(),
		"goal": goal,
		"decide_in": _decide_timer,
		"forced": _force,
		"facts": _last_facts,
	}
	if _planner != null:
		out["decision"] = _planner.debug_state()
	if _perception != null:
		out["under_fire"] = _perception.under_fire()
		out["engaged_fresh"] = _perception.engaged_fresh()
		out["memory_size"] = _perception.memory_size()
		out["contacts"] = _contact_digest()
	if _behavior != null:
		out.merge(_behavior.debug_state())
	return out


## Read-only: the tactical navigation ZONES the NPC's perception laid out for its last decision —
## every candidate position it weighed, flattened to world points (each with its `label` + `desc`)
## tagged by the kind of zone each is
## (`fire` / `flank` / `advance` / `retreat` / `lead` / `search` / `room` / `interaction`, plus
## `waypoint` for the non-room go-to points — your starting post, the front entrance, approaching the
## house — which the room/search groups carry but which aren't rooms and often sit outside one), for
## the tactics debug overlay to draw. A pure read of the last snapshot's option groups; empty until the
## first decision. Options with no world location (a point-blank punch, the hostile picks) are skipped.
func debug_zones() -> Array:
	var out: Array = []
	if _last_options.is_empty():
		return out
	for groups in _last_options.get("per_target", {}).values():
		_collect_zones(out, groups.get("fire_positions", {}), &"fire")
		_collect_zones(out, groups.get("flank_sides", {}), &"flank")
		_collect_zones(out, groups.get("advance_positions", {}), &"advance")
	_collect_zones(out, _last_options.get("retreat_positions", {}), &"retreat")
	_collect_zones(out, _last_options.get("leads", {}), &"lead")
	_collect_zones(out, _last_options.get("shooter", {}), &"lead")
	_collect_zones(out, _last_options.get("search_rooms", {}), &"search")
	_collect_zones(out, _last_options.get("explore", {}), &"search")
	_collect_zones(out, _last_options.get("rooms", {}), &"room")
	_collect_zones(out, _last_options.get("interactions", {}), &"interaction")
	return out


## Read-only: the tactical ROOM zones — every room of the house tagged by how this NPC regards it now
## (`current` / `searched` / `unsearched` / `unknown`), each as a world-space `rect` with its `type`,
## for the tactics debug overlay to draw. It is the room reasoning the search / room / flank options are
## placed against. Empty until the controller knows its character. A pure read of the perception.
func debug_room_zones() -> Array:
	if _character == null or _perception == null:
		return []
	return _perception.room_status(rooms, _character.global_position)


## Non-room go-to options the room/search groups carry: the NPC's starting post, the front entrance,
## and approaching the house. They aren't rooms (and an outside NPC's often sit well outside one), so
## the overlay tags them `waypoint` instead of `room`/`search` rather than letting them read as rooms.
const WAYPOINT_IDS := ["post", "entrance", "approach"]


## Append each option in `group` that has a world location to `out`, tagged `category` — except the
## non-room waypoints (WAYPOINT_IDS), re-tagged `waypoint`. Each entry also carries the option's `label`
## and `desc` (the human text Von reads, which spells out the deciding facts: cover, route, range) so an
## inspector can expose a clicked point's details. The location is the option's `point` param, or an
## interactable's current position. Options with neither (a punch, a hostile bind) are skipped.
func _collect_zones(out: Array, group: Dictionary, category: StringName) -> void:
	for opt in group.get("options", []):
		var params: Dictionary = opt.get("params", {})
		var cat: StringName = &"waypoint" if str(opt.get("id", "")) in WAYPOINT_IDS else category
		var point = null
		if params.has("point"):
			point = params["point"]
		elif params.get("object") is Node2D and is_instance_valid(params["object"]):
			point = (params["object"] as Node2D).global_position
		if point != null:
			out.append({ "point": point, "category": cat,
				"label": opt.get("label", ""), "desc": opt.get("desc", "") })


## Full contact data for display in the spectator inspector: each entry has `node`, `pos` (last-known
## world position), `name`, `hostile`, `visible` (seen this tick) and `age` (seconds since last seen).
func known_contacts_for_display() -> Array:
	if _character == null or _perception == null:
		return []
	return _perception.all_seen_characters(_character.global_position)


## The known-contacts list flattened to the fields worth reading in a snapshot (who, whether hostile
## and why, whether seen this tick, and how far off). Empty until the controller knows its character.
func _contact_digest() -> Array:
	if _character == null:
		return []
	var self_pos: Vector2 = _character.global_position
	var out: Array = []
	for c in _perception.contacts(self_pos):
		out.append({
			"name": c["name"],
			"hostile": c["hostile"],
			"reason": c["reason"],
			"visible": c["visible"],
			"inside": c.get("inside", false),
			"dist": int((c["pos"] as Vector2).distance_to(self_pos)),
		})
	return out


## Called each physics frame by the character. Runs the SENSE → THINK → ACT loop: fold queued events
## in, perceive, let the behaviour resolve what it knows + honour its commitments, start a decision
## walk only when free to (or restart one a new situation has overtaken), then let the behaviour carry
## out the running primitive.
func control(character, delta: float) -> void:
	if character.is_dead:
		return
	if _character == null:
		_character = character
		_perception.set_faction(character.faction)
		_client.set_npc_name(_npc_name())
	_decide_timer -= delta
	# SENSE.
	_process_events(character)
	_perception.observe(character, rooms)
	_behavior.rooms = rooms
	if entry_point != Vector2.ZERO:
		_perception.entry_point = entry_point # Hand the injected entrance to the perception once.
		entry_point = Vector2.ZERO
	var known: Array = _perception.contacts(character.global_position)
	if _behavior.update_known(known, delta):
		_force = true # Lost the engaged contact mid-fight → reconsider.
	_check_salient()
	# An active interaction holds the tick; when it or a move resolves, re-decide at once.
	if _behavior.service_interaction(character, delta, _force):
		return
	if _behavior.take_resolved():
		_force = true
		var lead: String = _behavior.reached_lead()
		if lead != "":
			_perception.check_lead(lead) # Reached it and found nothing: don't send it back there.
	# THINK.
	if _planner.is_pending():
		if _force:
			_maybe_interrupt(character)
	elif _should_decide():
		_start_decision(character)
	# ACT.
	_behavior.apply(character, delta)


## Whether a new decision may start now: always when forced; otherwise the behaviour decides whether
## its current commitment still holds (a fight, a move, an approach) or the decide cadence has elapsed.
func _should_decide() -> bool:
	if _force:
		return true
	return _behavior.wants_decision(_character, _decide_timer <= 0.0)


## A salient event arrived while a walk is in flight: restart the walk only when the situation now
## calls for a different starting node (e.g. it came under fire mid-way through choosing a room to
## search → straight to COMBAT). Otherwise the walk in flight already fits; let it finish.
func _maybe_interrupt(character) -> void:
	if _planner.entry_for(_perception.quick_facts(character)) != _planner.current_entry():
		_start_decision(character)
	else:
		_force = false


## Sense the situation and start a decision walk over it. The planner answers asynchronously via
## `decided` / `failed` (the latter wired to the behaviour's steady-stance fallback).
func _start_decision(character) -> void:
	_force = false
	_decide_timer = decide_interval
	_apply_config()  # Pick up any export retuned at runtime before sensing + deciding.
	var snapshot: Dictionary = _perception.sense(character, rooms, goal, _behavior.activity_text())
	_last_facts = snapshot["facts"]
	_last_options = snapshot["options"]
	_planner.begin(snapshot, _behavior.ongoing())


## Hand buffered EventBus events to the perception. A hit that is a relevant attack forces an
## immediate re-decision only when the NPC is NOT already fighting (to kick off a fight); while
## fighting it just refreshes the engagement, so a firefight doesn't re-ask Von every frame. Allies'
## callouts are folded in when this NPC listens to them.
func _process_events(character) -> void:
	if _event_queue.is_empty():
		return
	for ev in _event_queue:
		if ev[0] == &"hit":
			if _perception.process_hit(character, ev[1]) and not _behavior.in_combat():
				_force = true
		elif hear_callouts:
			_perception.process_callout(character, ev[1])
	_event_queue.clear()


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


## Adopt the planner's leaf: hand it to the behaviour, log the full decision path, and tell allies
## (a combat or investigation decision) over the radio.
func _on_decided(leaf: Dictionary) -> void:
	_behavior.set_leaf(leaf)
	print("%s (Von) %s  [%s]" % [_npc_name(), " - ".join(leaf["labels"]), _planner.walk_digest()])
	if send_callouts and _character != null and not leaf["path"].is_empty() \
			and str(leaf["path"][0]) in ["combat", "investigate"]:
		_post_callout(leaf)


## Broadcast this NPC's decision as an `&"callout"` EventBus event (interface 10): who is speaking and
## where, its state, the decision path, its target and destination. Allies within range hear it.
func _post_callout(leaf: Dictionary) -> void:
	var params: Dictionary = leaf["params"]
	var status: Array = []
	if _perception.under_fire():
		status.append("under fire")
	var dmg: float = _character.damage_taken()
	if dmg >= _perception.critical_threshold:
		status.append("badly wounded")
	elif dmg >= _perception.hurt_threshold:
		status.append("hurt")
	EventBus.post(&"callout", {
		"speaker": _character,
		"faction": _character.faction,
		"position": _character.global_position,
		"status": ", ".join(status),
		"path": "/".join(leaf["path"]),
		"label": " - ".join(leaf["labels"]),
		"target_id": params.get("target_id", 0),
		"point": params.get("point", _character.global_position),
	})


## The driven character's name, for log lines.
func _npc_name() -> String:
	return str(_character.name) if _character != null else "NPC"
