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
##     (engage / flank / advance / retreat / reload …), then a concrete option — ending in one behaviour primitive.
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
const Budget := preload("res://scenes/ai/decision/decision_budget.gd")  ## The frame's snapshot count (DecisionBudget).
const Behavior := preload("res://scenes/ai/behavior/behavior.gd")
const ZoneList := preload("res://scenes/ai/debug/zone_list.gd")

## The behaviour to pursue, in plain language — what Von ranks every level of the decision against. `{gun}` stands
## for whatever gun the NPC carries ("shoot them with your {gun}"); read it filled in through `goal_text()`.
@export_multiline var goal: String = ("Deal with hostile characters: shoot them with your {gun}. " +
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
## When searching a room the NPC looks around until it has SEEN (near-)every part of it (view cone +
## line of sight). These tune that coverage. Gaze turn speed (rad/s) as it looks from point to point.
@export var search_look_rate: float = 2.5
## Room sample-grid spacing (px): smaller = finer coverage but more sight rays per tick.
@export var search_coverage_spacing: float = 64.0
## Fraction (0..1) of sampled points that must be seen to call a room covered (1 = all; < 1 tolerates
## nooks it can never see into).
@export var search_coverage_target: float = 1.0
## Max seconds spent covering one room before giving up on unseeable spots and re-deciding (safety cap).
@export var search_coverage_budget: float = 8.0
## If the nearest unseen point is farther than this (px) or its line is blocked, the NPC walks toward
## it to get a view; otherwise it just turns to look.
@export var search_coverage_approach: float = 300.0
## Inset (px) from a room's walls where coverage sampling starts, so search points sit off the walls.
@export var search_coverage_margin: float = 24.0
## Range (px) of the gun: shots are taken within it, and distances are banded against it for Von.
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
## Rounds an automatic gun fires per trigger pull (at the gun's own fire rate); a single-shot gun fires one.
@export var fire_burst: int = 3
## Seconds spent stepping back when the gun's barrel is against a wall or object and cannot fire.
@export var back_off_time: float = 0.45
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
## A gun holding this fraction of its magazine or less reads as "nearly empty" (and offers a reload).
@export var low_ammo_fraction: float = 0.34
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

@export_group("Entry")
## Tactical entry (`docs/tactical-entry.md`): offer doorways into rooms left to search as an ENTER tactic, carried
## out as a team or alone — stack beside the door, slice the pie, cross without stopping, take the corners, clear.
@export var entry_enabled: bool = false
## Seconds the point waits at the door, once in its slot, for the rest of the stack before going in without them.
@export var entry_ready_timeout: float = 6.0
## Seconds a follower leaves after the member ahead of it is through, so the stack crosses one at a time.
@export var entry_follow_gap: float = 0.3
## Distance (px) between neighbouring stack slots along the wall: clear of a neighbour's footprint (the 34 px hole a body at
## rest cuts in the steering map, plus room to spare), so a slot never lies in the hole of the member beside it.
@export var entry_stack_spacing: float = 44.0
## Distance (px) of a stack slot off the wall's centreline.
@export var entry_wall_standoff: float = 28.0
## Distance (px) from the threshold of the arc the point slices the pie from.
@export var entry_pie_radius: float = 100.0
## Angle steps on that arc.
@export var entry_pie_steps: int = 5
## Seconds the point looks through the door from each step of the arc.
@export var entry_pie_dwell: float = 0.35
## Inset (px) of a corner point from the room's walls: where an entrant stops in a corner.
@export var entry_corner_inset: float = 40.0
## A room with a side under this (px) is too small for the team (about three bodies): two go in, the rest hold the stack side.
@export var entry_short_room: float = 150.0
## Seconds an entrant holds its corner, looking across the room, before it clears the rest by sight.
@export var entry_corner_dwell: float = 0.6
## Most seconds the last of a team holds the doorway it came in by, facing back out, once the room is clear (it leaves
## sooner when a teammate holding the room moves on).
@export var rear_security_time: float = 10.0
## Most seconds a member covers a doorway on out of a room the team has cleared, gun through it, when no teammate moves
## on first.
@export var entry_cover_time: float = 8.0
## Seconds a lone entrant looks through each doorway on out of a room it has cleared, once its gaze has settled.
@export var entry_watch_dwell: float = 0.8
## Safety cap (s) on reaching the stack: an entrant that cannot get to its slot in this time gives up its claim.
@export var entry_approach_time: float = 20.0
## The entry guard (E9): any walk that would cross into a room that is not cleared goes in by tactical entry first, whatever
## order it came from. Needs `entry_enabled`. A retreat and an NPC under fire are exempt.
@export var entry_guard: bool = true
## Distance (px of walking) from such a doorway at which the guard starts the entry.
@export var entry_guard_range: float = 300.0
## Seconds a doorway whose entry was given up (a fight, a failed start) is left alone before the guard may try it again.
@export var entry_guard_rearm: float = 6.0
## Seconds a doorway the NPC secured as it passed (E15: a doorway on its walk in a corridor, not crossed) is left alone before
## the guard may secure it again.
@export var entry_secure_time: float = 30.0

@export_group("Grenades")
## React to live grenades (`docs/grenades.md` G16): an NPC that sees one, hears it land or is told of it, and is in its danger zone, radios
## it and runs for the nearest safe spot (out of its line, behind cover that shields it, or outside the zone), holding it to the burst.
## Off = it stands and takes it.
@export var grenades_enabled: bool = true
## How far (px) a grenade coming down is heard (its bounce and rest), seen or not.
@export var hear_grenade: float = 300.0
## How far (px) past a frag's blast radius its danger zone reaches: the NPC runs to be clear of that, not only of the blast.
@export var evade_margin: float = 120.0

@export_group("Watch")
## How far (px) down its path a walking NPC looks: through the doorway it is lining up, not at the wall beside it.
@export var watch_look_ahead: float = 150.0
## Seconds a resting NPC looks at one doorway of its room before turning to the next.
@export var watch_door_dwell: float = 2.5
## Seconds a hostile that is no longer in sight still holds the NPC's eyes, while it has a clear line to where it was.
@export var watch_lost_gaze: float = 2.0

@export_group("Vision")
## Whether sight is gated at all. Off = the NPC is omniscient (pre-vision behaviour), for debugging.
@export var vision_enabled: bool = true
## Maximum distance (px) at which the NPC can see anything.
@export var view_distance: float = 2520.0
## Full angular width (degrees) of the forward view cone, centred on the NPC's facing (its aim).
@export var fov_degrees: float = 110.0
## Radius (px) of a 360° near-awareness bubble: things this close are sensed regardless of facing.
@export var awareness_radius: float = 48.0
## Coverage rating (0–100 height proxy) at or below which furniture is low enough to see OVER —
## tables, beds, islands, counters. Taller pieces (cabinets, wardrobes, fridges) and walls still
## block sight. Sight-only: line-of-fire and cover still treat every solid piece as an obstacle.
@export var see_over_coverage: float = 60.0
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

@export_group("")
## How close (px) counts as "arrived" when steering straight-line (no nav agent).
@export var arrive_dist: float = 10.0
## Running: may the NPC sprint (spending stamina) on the way to a destination when its decision-tree
## node asks for it (`run`) or it is under fire.
@export var run_enabled: bool = true
## Reload an empty gun on its own (holding steady, or ducked in cover) when a spare magazine is carried,
## whatever the decision tree chose: the NPC is never left unarmed for lack of a decision.
@export var auto_reload: bool = true
## Crouch while fighting in place (kneel behind cover, keep low when pinned), standing to run and
## move. Off = the NPC always stands.
@export var posture_enabled: bool = true
## Seconds a crouch is held before the NPC stands again, so a peek-and-duck does not flicker.
@export var posture_dwell: float = 0.7
## Only run when the destination is farther than this (px), so short hops don't burn stamina.
@export var run_min_distance: float = 150.0
## Stamina fraction (0..1) needed to start a run; once running it goes on until the Character runs dry.
@export var run_start_fraction: float = 0.5
## NavigationAgent2D used for pathing (a sibling under the character); set in the NPC scene.
@export var nav_agent_path: NodePath

## World-space room rects (`{ key, type, rect }`) from Main — the sensor's map of the house.
var rooms: Array = []
## The house entrance in world space, injected by Main for NPCs that start outside. Handed to the
## perception once (it offers "the front entrance" as a search option while outside).
var entry_point: Vector2 = Vector2.ZERO
## The house's doorways (`{ pos, width, front, exit, rooms }`) from Main, for tactical entry.
var openings: Array = []

var _perception: Node ## SENSE sub-domain: knowledge, the decision snapshot, combat geometry.
var _client: Node ## THINK transport: the Von round-trip (decision/decision_client.gd).
var _planner: Node ## THINK policy: the decision-tree walk (decision/decision_planner.gd).
var _behavior: Node ## ACT sub-domain: runs the chosen primitive + holds commitment state.
var _last_facts := {} ## The facts of the last decision snapshot, retained for `debug_state()`.
var _last_options := {} ## The option groups of the last snapshot, retained for `debug_zones()`.
var _decide_timer := 0.0 ## Seconds until the next decision is allowed.
var _force := false ## Force a decision now (task resolved or salient event).
var _force_reason := "" ## Why `_force` was last raised, kept (with `_force_ms`) for the brain overlay.
var _decisions := 0 ## Decision walks started so far (`debug_state()["decisions"]`).
var _decision_reason := "" ## Why the latest walk was started: the force reason, or "cadence" (`debug_state()["decision_reason"]`).
var _force_ms := 0 ## When `_force_reason` was raised (msec).
var _last_callout := {} ## The last callout this NPC radioed (`position`, `point`, `label`, `at`), for the hearing overlay.
var _salient_key := "" ## Known-hostile set + engaged contact's inside state, for edge detection.
var _salient_init := false ## Whether _salient_key has been seeded.
# EventBus events are queued here, then handed to perception on the next control() tick.
var _character: Node ## The character this controller drives, captured on first control.
var _event_queue: Array = [] ## [topic, data] pairs awaiting processing once _character is known.
var _was_blind := false ## The character was flash-blinded last tick, to re-decide the moment its sight returns.


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
	_perception.see_over_coverage = see_over_coverage
	_perception.hostile_on_sight = hostile_on_sight
	_perception.hostile_on_trespass = hostile_on_trespass
	_perception.hostile_on_attack = hostile_on_attack
	_perception.hostility_ttl = hostility_ttl
	_perception.memory_capacity = memory_capacity
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
	_perception.low_ammo_fraction = low_ammo_fraction
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
	_perception.entry_enabled = entry_enabled
	_perception.entry_stack_spacing = entry_stack_spacing
	_perception.entry_wall_standoff = entry_wall_standoff
	_perception.entry_pie_radius = entry_pie_radius
	_perception.entry_pie_steps = entry_pie_steps
	_perception.entry_corner_inset = entry_corner_inset
	_perception.entry_short_room = entry_short_room
	_perception.grenades_enabled = grenades_enabled
	_perception.hear_grenade = hear_grenade
	_perception.evade_margin = evade_margin
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
	_behavior.search_look_rate = search_look_rate
	_behavior.search_coverage_spacing = search_coverage_spacing
	_behavior.search_coverage_target = search_coverage_target
	_behavior.search_coverage_budget = search_coverage_budget
	_behavior.search_coverage_approach = search_coverage_approach
	_behavior.search_coverage_margin = search_coverage_margin
	_behavior.tactic_interval = tactic_interval
	_behavior.shoot_range = shoot_range
	_behavior.punch_range = punch_range
	_behavior.combat_ring_radius = combat_ring_radius
	_behavior.combat_ring_count = combat_ring_count
	_behavior.cover_time = cover_time
	_behavior.fire_cooldown = fire_cooldown
	_behavior.fire_burst = fire_burst
	_behavior.back_off_time = back_off_time
	_behavior.reposition_interval = reposition_interval
	_behavior.arrive_dist = arrive_dist
	_behavior.run_enabled = run_enabled
	_behavior.auto_reload = auto_reload
	_behavior.posture_enabled = posture_enabled
	_behavior.posture_dwell = posture_dwell
	_behavior.run_min_distance = run_min_distance
	_behavior.run_start_fraction = run_start_fraction
	_behavior.entry_ready_timeout = entry_ready_timeout
	_behavior.entry_follow_gap = entry_follow_gap
	_behavior.entry_pie_dwell = entry_pie_dwell
	_behavior.entry_corner_dwell = entry_corner_dwell
	_behavior.rear_security_time = rear_security_time
	_behavior.entry_cover_time = entry_cover_time
	_behavior.entry_watch_dwell = entry_watch_dwell
	_behavior.entry_approach_time = entry_approach_time
	_behavior.entry_guard = entry_guard
	_behavior.entry_guard_range = entry_guard_range
	_behavior.entry_guard_rearm = entry_guard_rearm
	_behavior.entry_secure_time = entry_secure_time
	_behavior.watch_look_ahead = watch_look_ahead
	_behavior.watch_door_dwell = watch_door_dwell
	_behavior.watch_lost_gaze = watch_lost_gaze
	_behavior.apply_config()


## Buffer a world event for processing on the next control() tick (the signal can fire before the
## controller knows which character it drives): hits (combat awareness, gunfire heard), allies'
## radio callouts, and a grenade coming down or going off.
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic == &"hit" or topic == &"callout" or topic == &"grenade" or topic == &"explosion":
		_event_queue.append([topic, data])


## Read-only: the goal as Von reads it, with `{gun}` filled in with the NPC's gun (the raw `goal` before it has acted).
func goal_text() -> String:
	if _perception == null or not is_instance_valid(_character):
		return goal.replace("{gun}", "gun")
	return _perception.fill_goal(goal, _character)


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
## knows (`contacts`), the running primitive and pathing, how many decision walks it has started and why the latest one
## started (`decisions`, `decision_reason`: the force reason, e.g. "task resolved" or "way blocked", or "cadence"). Pure
## reads — never perturbs the loop.
func debug_state() -> Dictionary:
	var out := {
		"npc": _npc_name(),
		"goal": goal_text(),
		"decide_in": _decide_timer,
		"forced": _force,
		"decisions": _decisions,
		"decision_reason": _decision_reason,
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


## Read-only: the tactical navigation ZONES the NPC's perception laid out for its last decision, flattened to world points
## tagged by kind (see `debug/zone_list.gd`), for the tactics debug overlay to draw. Empty until the first decision.
func debug_zones() -> Array:
	return ZoneList.from_options(_last_options)


## Read-only: the tactical ROOM zones — every room of the house tagged by how this NPC regards it now
## (`current` / `searched` / `unsearched` / `unknown`), each as a world-space `rect` with its `type`,
## for the tactics debug overlay to draw. It is the room reasoning the search / room / flank options are
## placed against. Empty until the controller knows its character. A pure read of the perception.
func debug_room_zones() -> Array:
	if _character == null or _perception == null:
		return []
	return _perception.room_status(rooms, _character.global_position)


## Read-only: the running tactical entry — the doorway (`opening`, `into`), the NPC's stack `slot` and `side`,
## whether it is going `solo`, its `phase`, what the pie saw (`seen_fraction`, `pie_sides`, `hidden_corners`), its
## `corner` and `stack_point`, as the behaviour reports it (typed values; `debug_state()["entry"]` is the JSON-safe
## copy). Empty when the NPC isn't entering a room.
func debug_entry() -> Dictionary:
	return _behavior.debug_entry() if _behavior != null else {}


## Read-only: the tactical entry and the entry guard as world-space data, for the entry debug overlays: `entry` (the
## doorway's slots, pie arc and corners, this NPC's role, timers, the team off the radio, the doorways it covers; {}
## when not entering) and `guard` (a running detour and the order it paused, the next uncleared doorway on the walk,
## the rooms regarded as cleared). See behavior.gd `debug_entry_view`.
func debug_entry_view() -> Dictionary:
	if _behavior == null or _character == null:
		return {}
	return _behavior.debug_entry_view(_character)


## Read-only: the behaviour's running search-coverage state (which room sample points it has seen vs.
## still needs to, and the one it is looking at now), for the search debug overlay. Empty/inactive when
## the NPC isn't currently covering a room.
func debug_search_coverage() -> Dictionary:
	return _behavior.debug_coverage() if _behavior != null else {}


## Read-only: where the NPC's sight toward world point `to` is first blocked (over low cover, the perception's own
## sight rule), or `to` when it reaches it — for the vision overlay, so it draws the area the sense really covers.
func debug_sight_end(to: Vector2) -> Vector2:
	if _perception == null or _character == null:
		return to
	return _perception.sight_end(_character, to)


## Read-only: what the NPC has heard and been told (gunfire heard, under-fire direction, ally callouts,
## lost hostiles, checked leads, radii) — for the contacts and hearing overlays. Empty before perception exists.
func debug_memory() -> Dictionary:
	return _perception.debug_memory() if _perception != null else {}


## Read-only: the behaviour's combat / movement / interaction state as world-space data — the engaged
## target, committed destination, aim and fire line, peek-and-cover phase, leash, move/interact targets —
## for the combat, territory and targets overlays. Empty until the controller knows its character.
func debug_combat() -> Dictionary:
	if _behavior == null or _character == null:
		return {}
	return _behavior.debug_combat(_character)


## Read-only: the movement-progress sample (seconds stalled, recent trail) for the stuck overlay.
func debug_progress() -> Dictionary:
	return _behavior.debug_progress() if _behavior != null else {}


## Read-only: the NPC's grenade awareness for the grenade overlay: `known` (the live grenades it knows of, soonest first, each
## `{ point, kind, fuse_left, fuse, radius, source }`, `source` being `&"seen"` / `&"heard"` / `&"called"` / `&"own"`), `escape` (the safe spot
## it is running to, `Vector2.INF` when it is not running to one) and `throw` (the throw it is about to make, `{ from, to, kind, radius }`;
## {} when it is not making one, or once the grenade has left its hand).
func debug_grenades() -> Dictionary:
	if _perception == null or _behavior == null:
		return { "known": [], "escape": Vector2.INF, "throw": {} }
	return { "known": _perception.known_grenades(), "escape": _behavior.evade_spot(),
		"throw": _behavior.throw_plan(_character) if _character != null else {} }


## Read-only: the last callout this NPC radioed (`position`, `point`, `label`, `at` msec), or empty.
func debug_sent_callout() -> Dictionary:
	return _last_callout


## Read-only: the decision machinery's live state for the brain overlay — whether Von is being asked
## (`pending`), the last walk's levels (state, offered options, probabilities, pick), whether it failed
## (the behaviour then holds steady), the decide/force timers and why the last force fired, and the facts.
func debug_brain() -> Dictionary:
	if _planner == null:
		return {}
	var d: Dictionary = _planner.debug_state()
	var timers: Dictionary = _behavior.debug_combat(_character).get("timers", {}) if _character != null else {}
	return {
		"pending": d.get("pending", false),
		"failed": d.get("last_failed", false),
		"entry": d.get("entry", ""),
		"levels": d.get("levels", []),
		"decide_in": maxf(_decide_timer, 0.0),
		"decide_interval": decide_interval,
		"forced": _force,
		"force_reason": _force_reason,
		"force_age": (Time.get_ticks_msec() - _force_ms) / 1000.0 if _force_reason != "" else INF,
		"timers": timers,
		"facts": _last_facts,
	}


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
	_perception.openings = openings
	_perception.observe(character, rooms)
	_react_to_grenades(character)
	_behavior.rooms = rooms
	if entry_point != Vector2.ZERO:
		_perception.entry_point = entry_point # Hand the injected entrance to the perception once.
		entry_point = Vector2.ZERO
	var known: Array = _perception.contacts(character.global_position)
	if _behavior.update_known(known, delta):
		_force_now("lost the engaged contact") # Lost the engaged contact mid-fight → reconsider.
	_check_salient()
	# An active interaction holds the tick; when it or a move resolves, re-decide at once.
	if _behavior.service_interaction(character, delta, _force):
		return
	var why: String = _behavior.resolve_reason()
	if _behavior.take_resolved():
		_force_now(why if why != "" else "task resolved")
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
	for step in _behavior.take_entry_calls():
		if send_callouts:
			_post_entry_call(step)
	for throw in _behavior.take_throw_calls():
		if send_callouts:
			_post_throw_call(throw)


## Raise the force-decide flag and remember why, for the brain debug overlay.
func _force_now(reason: String) -> void:
	_force = true
	_force_reason = reason
	_force_ms = Time.get_ticks_msec()


## Whether a new decision may start now: never while crossing a doorway (a forced one waits until the NPC is
## through); always when forced; otherwise the behaviour decides whether its current commitment still holds (a
## fight, a move, an approach) or the decide cadence has elapsed. One that may must also get one of the frame's
## snapshots (`DecisionBudget`); refused, it keeps its wish (`_force`, the elapsed timer) and asks again next frame.
func _should_decide() -> bool:
	if _behavior.committed() or _behavior.evading() or _character.is_blind():
		return false  # A blinded NPC starts no new decision (G15), one running from a grenade none until the burst (G16).
	if not _force and not _behavior.wants_decision(_decide_timer <= 0.0):
		return false
	return Budget.claim()


## A salient event arrived while a walk is in flight: restart the walk only when the situation now
## calls for a different starting node (e.g. it came under fire mid-way through choosing a room to
## search → straight to COMBAT). Otherwise the walk in flight already fits; let it finish.
func _maybe_interrupt(character) -> void:
	if _behavior.evading() or character.is_blind():
		return
	if _planner.entry_for(_perception.quick_facts(character)) != _planner.current_entry():
		if Budget.claim():  # Else `_force` stays and the restart is tried again next frame.
			_start_decision(character)
	else:
		_force = false


## Sense the situation and start a decision walk over it. The planner answers asynchronously via
## `decided` / `failed` (the latter wired to the behaviour's steady-stance fallback).
func _start_decision(character) -> void:
	_decisions += 1
	_decision_reason = _force_reason if _force else "cadence"
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
	var deaf: bool = character.is_deaf()  # A deafened NPC hears no gunfire, no hit elsewhere and no radio call (G15).
	for ev in _event_queue:
		match ev[0]:
			&"hit":
				if deaf and ev[1].get("victim") != character:
					continue
				if _perception.process_hit(character, ev[1]) and not _behavior.in_combat():
					_force_now("attacked")
			&"callout":
				if hear_callouts and not deaf:
					_perception.process_callout(character, ev[1])
			&"grenade":
				_perception.process_grenade(character, ev[1], deaf)
			&"explosion":
				_perception.process_explosion(character, ev[1])
	_event_queue.clear()


## The grenade reflex (G16) and the blind NPC's recovery (G15), every tick after the SEE pass: hand the behaviour the plan to get clear
## of the live grenade that threatens the NPC (or {}), radio the grenades it has seen or heard come down, and re-decide the moment
## its sight returns.
func _react_to_grenades(character) -> void:
	_behavior.poll_throw(character)
	_behavior.set_evade(_perception.evade_plan(character))
	for grenade in _perception.grenade_announcements():
		if send_callouts:
			_post_grenade_call(grenade)
	var blind: bool = character.is_blind()
	if _was_blind and not blind:
		_force_now("sight returned")
	_was_blind = blind


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
		_force_now("hostile belief changed")


## Adopt the planner's leaf: hand it to the behaviour, log the full decision path, and tell allies
## (a combat or investigation decision) over the radio.
func _on_decided(leaf: Dictionary) -> void:
	if _behavior.evading():
		return  # Overtaken by a grenade while Von was answering; the burst ends in a new decision.
	_behavior.set_leaf(leaf)
	GameLog.say("%s (Von) %s  [%s]" % [_npc_name(), " - ".join(leaf["labels"]), _planner.walk_digest()])
	if send_callouts and _character != null and not leaf["path"].is_empty() \
			and str(leaf["path"][0]) in ["combat", "investigate"]:
		_post_callout(leaf)


## Broadcast this NPC's decision as an `&"callout"` EventBus event (interface 10): who is speaking and
## where, its state, the decision path, its target and destination. Allies within range hear it.
func _post_callout(leaf: Dictionary) -> void:
	var params: Dictionary = leaf["params"]
	var status := _status(leaf["primitive"] == &"reload")
	_last_callout = { "position": _character.global_position, "point": params.get("point", _character.global_position),
		"label": " - ".join(leaf["labels"]), "at": Time.get_ticks_msec() }
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


## Radio a live grenade the NPC has seen or heard come down (`{ point, kind }`) as an `&"grenade"` callout: the spot it landed
## at and its kind, for the allies in its danger zone who neither saw nor heard it (G16). `point` is the landing.
func _post_grenade_call(grenade: Dictionary) -> void:
	var label := "a %s grenade" % grenade["kind"]
	_last_callout = { "position": _character.global_position, "point": grenade["point"], "label": label, "at": Time.get_ticks_msec() }
	EventBus.post(&"callout", {
		"speaker": _character,
		"faction": _character.faction,
		"position": _character.global_position,
		"status": "grenade",
		"path": "",
		"label": label,
		"target_id": 0,
		"point": grenade["point"],
		"kind": grenade["kind"],
	})


## Radio a grenade this NPC has just thrown (`{ kind, point }` from the behaviour) as a `frag_out` / `bang_out` `&"callout"`: where it is
## going to land and its kind, for the allies near it to get clear of (G16, G17). `point` is the landing.
func _post_throw_call(throw: Dictionary) -> void:
	var status := "frag_out" if throw["kind"] == &"frag" else "bang_out"
	var label := "%s!" % status.replace("_", " ")
	_last_callout = { "position": _character.global_position, "point": throw["point"], "label": label, "at": Time.get_ticks_msec() }
	EventBus.post(&"callout", {
		"speaker": _character,
		"faction": _character.faction,
		"position": _character.global_position,
		"status": status,
		"path": _behavior.current_act(),
		"label": label,
		"target_id": 0,
		"point": throw["point"],
		"kind": throw["kind"],
	})


## Radio one step of a tactical entry (`{ step, opening, slot, side, cleared_room? }` from the behaviour) as an
## `&"callout"`: the usual fields plus `opening`, `into` (the room it leads into), `slot`, `side` and `entry_step` (claim / ready / going_in / in /
## clear / cover / rear / done / abort), `cleared_room` with a clear and `covering` (the doorway on it watches) with a
## cover. It is how the stack claims slots, waits for the team and
## crosses in order; "going in" is also said in `status`. `point` is where the speaker stands.
func _post_entry_call(step: Dictionary) -> void:
	var status := _status(false)
	if step["step"] == "going_in":
		status.push_front("going in")
	var labels: String = _behavior.path_label()
	_last_callout = { "position": _character.global_position, "point": _character.global_position,
		"label": "%s (%s)" % [labels, String(step["step"]).replace("_", " ")], "at": Time.get_ticks_msec() }
	EventBus.post(&"callout", {
		"speaker": _character,
		"faction": _character.faction,
		"position": _character.global_position,
		"status": ", ".join(status),
		"path": _behavior.current_act(),
		"label": labels,
		"target_id": 0,
		"point": _character.global_position,
		"opening": step["opening"],
		"into": step.get("into", ""),
		"slot": step["slot"],
		"side": step["side"],
		"entry_step": step["step"],
		"bang": step.get("bang", false),
		"stuns": step.get("stuns", 0),
		"cleared_room": step.get("cleared_room", ""),
		"covering": step.get("covering", ""),
	})


## The speaker's state for a callout: under fire, wounded, reloading.
func _status(reloading: bool) -> Array:
	var status: Array = []
	if _perception.under_fire():
		status.append("under fire")
	var dmg: float = _character.damage_taken()
	if dmg >= _perception.critical_threshold:
		status.append("badly wounded")
	elif dmg >= _perception.hurt_threshold:
		status.append("hurt")
	if reloading or _character.is_reloading():
		status.append("reloading")
	return status


## The driven character's name, for log lines.
func _npc_name() -> String:
	return str(_character.name) if _character != null else "NPC"
