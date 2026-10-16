extends Node

## AI domain: perception/sensor for a goal-driven NPC. It has two halves. `observe()` is the SEE
## pass — run every tick, it tests what is currently visible (via the vision sense, agent_vision.gd),
## deposits sightings into the agent's memory (agent_memory.gd) — every other character
## (`saw_character`, with a smoothed movement track, its facing and raw hit-damage) and, for an NPC
## that must learn its surroundings, rooms and objects (`saw_room` / `saw_object`) — notes the rooms it
## has searched, and runs each character sighting through the hostility rules (agent_hostility.gd).
## `contacts()` is the resulting view: every character the agent knows of, hostile or not. `sense()`
## is the BUILD pass — run at the start of each decision, it gathers what the agent knows (contacts,
## callouts, learned house knowledge) and hands it to the SNAPSHOT AUTHOR (agent_snapshot.gd), which
## turns it into the SNAPSHOT the decision planner walks (facts / sections / option groups). The NPC
## knows only what it has perceived — sight, nearby hits, gunfire and footsteps within earshot, and its allies' radio
## callouts — and that knowledge decays as the memory does.
##
## This is the PERCEPTION sub-domain's public face: it OWNS the sight sense (agent_vision.gd), the
## hostility rules (agent_hostility.gd), the event memory (agent_memory.gd), the combat geometry
## (agent_tactics.gd), the doorway geometry (agent_entry.gd), the grenade geometry (agent_throw.gd), the live
## grenades known (agent_grenades.gd) and the snapshot author (agent_snapshot.gd) as internal modules, and surfaces
## knowledge only through its own methods. It holds NO policy: it never decides, gates by goal or
## picks — and the measured wording Von reads lives in the snapshot author, not here. The controller
## configures it (all tunables live on the GoalController, the single authoring surface) then calls
## `setup()` once.

## The internal modules this sub-domain owns (built in setup() from the config fields).
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentHostility := preload("res://scenes/ai/perception/agent_hostility.gd")
const AgentMemory := preload("res://scenes/ai/perception/agent_memory.gd")
const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")
const AgentSuspicion := preload("res://scenes/ai/perception/agent_suspicion.gd")
## The BUILD half: turns what the NPC knows + the combat geometry into the decision snapshot Von walks.
const AgentSnapshot := preload("res://scenes/ai/perception/agent_snapshot.gd")
const SnapshotVocab := preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")

## Physics frames between an unfamiliar NPC's looks for rooms and furniture it does not know yet. Learning is permanent and
## a decision looks again first, so a glimpse shorter than this still counts when it is the moment of a decision.
const LEARN_EVERY_FRAMES := 6

## The share of a stun's longest blindness (`max_blind`) a hostile caught at its burst is taken to be blinded for, at point-blank (less with distance): the NPC cannot
## see which way their eyes were turned.
const FLASH_SHARE := 0.8

## Physics frames between two sight tests of a character that stays inside an NPC's view cone. The range and cone test runs
## every frame, so one that enters the cone is tested at once and one that leaves it is dropped at once; only the line of
## sight and the sighting written from it are renewed this often, offset per NPC and target so a squad does not test on the
## same frame. What the NPC holds of a character it sees is at most this many frames old.
const SIGHT_EVERY_FRAMES := 3
## The longest (game ms, `GameClock`) a decision waits for the avoid map its routes are measured on (`routes_ready`).
const WARM_CAP_MS := 3000

## Lifetime (s) of a live contact: the window the NPC keeps acting on a last-seen position.
var contact_memory_ttl: float = 4.0
## Whether this NPC starts knowing the house (rooms + objects), else learns them by sight.
var familiar_with_house: bool = true
## The house entrance in world space (injected by Main for some NPCs), offered while outside.
var entry_point: Vector2 = Vector2.ZERO
## The house's doorways (`WorldGen.get_openings`, injected by Main), for tactical entry.
var openings: Array = []

# --- Config fields the controller copies from its exports before calling setup(). ---
# Vision (the sight sense).
var vision_enabled: bool = true        ## GoalController.vision_enabled
var view_distance: float = 2520.0      ## GoalController.view_distance
var fov_degrees: float = 110.0         ## GoalController.fov_degrees
var awareness_radius: float = 48.0     ## GoalController.awareness_radius
var see_over_coverage: float = 60.0    ## GoalController.see_over_coverage
# Hostility (the categorization rules).
var hostile_on_sight: bool = false     ## GoalController.hostile_on_sight
var hostile_on_trespass: bool = false  ## GoalController.hostile_on_trespass
var hostile_on_attack: bool = true     ## GoalController.hostile_on_attack
var hostility_ttl: float = 0.0         ## GoalController.hostility_ttl
# Memory (the event log) and how long each kind of knowledge lasts.
var memory_capacity: int = 128         ## GoalController.memory_capacity
var lead_memory_ttl: float = 20.0      ## GoalController.lead_memory_ttl
var search_memory_ttl: float = 60.0    ## GoalController.search_memory_ttl
# Combat awareness (how hits and gunfire are remembered — see process_hit()).
var hit_awareness_radius: float = 160.0 ## GoalController.hit_awareness_radius
var hearing_radius: float = 900.0      ## GoalController.hearing_radius
var hear_walk: float = 250.0           ## How far (px) a walking step is heard, through walls (docs/hearing.md H1).
var hear_run: float = 450.0            ## How far (px) a running step is heard.
var hear_crouch: float = 100.0         ## How far (px) a crouched step is heard.
var under_fire_time: float = 3.0       ## GoalController.under_fire_time
var engage_dwell: float = 3.0          ## GoalController.engage_dwell
# Context: how knowledge is worded and bounded for Von.
var shoot_range: float = 500.0         ## GoalController.shoot_range
var punch_range: float = 48.0          ## GoalController.punch_range
var recency_bands: Vector2 = Vector2(2.0, 8.0) ## GoalController.recency_bands
var route_buckets: Vector2 = Vector2(400.0, 900.0) ## GoalController.route_buckets
var aim_cone: float = 20.0             ## GoalController.aim_cone
var still_speed: float = 20.0          ## GoalController.still_speed
var track_smoothing: float = 0.3       ## GoalController.track_smoothing
var extrapolate_cap: float = 3.0       ## GoalController.extrapolate_cap
var investigate_distance: float = 300.0 ## GoalController.investigate_distance
var max_options_per_level: int = 4     ## GoalController.max_options_per_level
var hurt_threshold: float = 15.0       ## Accumulated damage at/above which a character reads as hurt.
var critical_threshold: float = 35.0   ## Accumulated damage at/above which a character reads as badly wounded.
var low_ammo_fraction: float = 0.34    ## A gun at/below this fraction of its magazine reads as nearly empty.
var max_contacts_in_state: int = 4     ## Most contacts described in the decision state (hostiles first).
# Tactics (the combat geometry).
var cover_min: float = 40.0            ## Surface coverage at/above which a blocking object counts as cover.
var flank_distance: float = 220.0      ## GoalController.flank_distance
var flank_arc: float = 60.0            ## GoalController.flank_arc
var flank_ally_radius: float = 500.0   ## GoalController.flank_ally_radius
var combat_ring_radius: float = 80.0   ## GoalController.combat_ring_radius
var combat_ring_count: int = 12        ## GoalController.combat_ring_count
var route_clearance: float = 120.0     ## GoalController.route_clearance
var watch_arc: float = 90.0            ## GoalController.watch_arc
var fire_spot_distances: Array[float] = [200.0, 350.0] ## GoalController.fire_spot_distances
# Callouts (allies' radio).
var callout_range: float = 1500.0      ## GoalController.callout_range
var callout_ttl: float = 6.0           ## GoalController.callout_ttl
# Tactical entry (the doorway geometry; see agent_entry.gd).
var entry_enabled: bool = false        ## Whether doorways into rooms left to clear are offered (ENTER).
var entry_stack_spacing: float = 44.0  ## GoalController.entry_stack_spacing
var entry_wall_standoff: float = 28.0  ## GoalController.entry_wall_standoff
var entry_pie_radius: float = 100.0    ## GoalController.entry_pie_radius
var entry_pie_steps: int = 5           ## GoalController.entry_pie_steps
var entry_corner_inset: float = 40.0   ## GoalController.entry_corner_inset
var entry_short_room: float = 150.0   ## A room with a side under this (px) is too small for the team (agent_entry.gd `short_room`).
var entry_guard: bool = true           ## Whether walks keep out of doorway views and secure the ones they cross (the controller's `entry_guard`).
var door_view_depth: float = 450.0     ## How far (px) out of a doorway its view reaches (agent_entry.gd `door_view_depth`).
var door_avoid_ratio: float = 2.0      ## A walk round the doorway views is taken when no longer than this many times the plain route...
var door_avoid_slack: float = 300.0    ## ... plus this many px.
var entry_pass_clear_time: float = 60.0 ## Seconds a cleared room counts as safe to walk past.
## Whether the NPC is walking an ordered stack's way to its door (`docs/leadership.md` LD9), set each tick by the behaviour: that walk keeps
## out of the doorway views whatever `entry_enabled` says (D4), and for an NPC that does not clear rooms by entry (`entry_enabled` off) a
## room it has stood in lately and seen no hostile in counts as clear for passing (`seen_empty`, D11).
var ordered_walk := false:
	set(value):
		if value != ordered_walk:
			ordered_walk = value
			_sync_walks()
# Grenades (live ones known by sight, hearing and callouts, and the danger zone; see agent_grenades.gd).
var grenades_enabled: bool = true      ## Whether the NPC reacts to live grenades at all.
var hear_grenade: float = 300.0        ## How far (px) a grenade coming down is heard.
var evade_margin: float = 120.0        ## How far past a frag's blast radius its danger zone reaches (px).
var throw_spot_walk: float = 250.0     ## Longest walk (px of route) to a throw spot (agent_tactics.gd `throw_spot`).

var _character: Node             ## The NPC's body, handed in once by bind().
var _vision: RefCounted          ## The sight sense (FOV/range/LoS); see agent_vision.gd.
var _hostility: RefCounted       ## The hostility rules; see agent_hostility.gd.
var _memory: RefCounted          ## The event memory; see agent_memory.gd.
var _tactics: RefCounted         ## The combat geometry; see agent_tactics.gd.
var _entry: RefCounted           ## The doorway geometry and the team's claims; see agent_entry.gd.
var _warming_since := -1         ## When (`GameClock.msec()`) the decision began waiting for the avoid map; -1: not waiting.
var _throw: RefCounted           ## The grenade geometry (danger zone, escape spot, lob); see agent_throw.gd.
var _grenades: RefCounted        ## The live grenades known and the plan to get clear of them; see agent_grenades.gd.
var _snapshot: RefCounted        ## The BUILD half: writes the decision snapshot; see agent_snapshot.gd.
var _suspicion: RefCounted       ## Why a room is suspect (G18); see agent_suspicion.gd.
var _rooms: Array = []           ## The house's rooms, as handed to the latest observe().
var _post := Vector2.ZERO        ## The NPC's spawn position, captured on the first observe() call.
var _post_set := false           ## Whether _post has been captured yet.
var _interactables: Array = []   ## Cached world objects that advertise interactions (static furniture).
var _scanned := false            ## Whether the one-time interactable scan has run.
var _seeded := false             ## Whether the familiar-NPC house-knowledge seed has run.
var _learn_next := 0             ## First physics frame the next look for unknown rooms and furniture may run.
var _learned_frame := -1         ## Physics frame of the latest such look (-1 = none yet).
var _visible_now := {}           ## Instance ids of characters visible on the latest observe() tick.
var _visible_before := {}        ## The same one tick earlier (what a character not due for a sight test keeps).
var _looked := {}                ## Instance ids of characters in the view cone that have had a sight test since they entered it.
var _tracks := {}                ## Per-character movement track: id → { pos, vel, t, f } (last seen, game msec and game frame).
var _blind := false              ## The NPC was flash-blinded on the latest observe() tick: it sees nothing new.
## The latest grenade burst (`{ kind, position, frame, team }`: the game-clock frame (`GameClock.frame()`) it was taken note of in, and whether the NPC or an ally
## threw it), or {}: a bang entry waits for its stun's, and an entry goes in on its own team's burst in the room (E17).
var last_burst := {}
var _ended_order := {}           ## The order that ended done or refused, until the controller radios it (`take_ended_order`).


## Build the owned sensing modules. The controller calls this once in its _ready(); it then pushes the
## config fields into the modules with apply_config() (here, and again each decision so a runtime
## retune takes effect). Building and configuring are separate so apply_config() never rebuilds a
## module — that would wipe the event memory and the sight state.
func setup() -> void:
	_vision = AgentVision.new()
	_hostility = AgentHostility.new()
	_memory = AgentMemory.new()
	_tactics = AgentTactics.new()
	_tactics.vision = _vision
	_entry = AgentEntry.new()
	_entry.vision = _vision
	_throw = AgentThrow.new()
	_throw.vision = _vision
	_grenades = AgentGrenades.new()
	_grenades.setup(_throw)
	_suspicion = AgentSuspicion.new()
	_suspicion.memory = _memory
	_suspicion.entry = _entry
	_snapshot = AgentSnapshot.new()
	_snapshot.setup(_memory, _tactics, _entry, _throw, _suspicion)


## Push the current config fields into the owned modules. Idempotent and state-free (it only sets
## tunables, never the memory log or hostility faction), so the controller may call it every decision
## to keep the modules in step with exports retuned at runtime (e.g. by the dev command server).
func apply_config() -> void:
	_vision.enabled = vision_enabled
	_vision.view_distance = view_distance
	_vision.fov_degrees = fov_degrees
	_vision.awareness_radius = awareness_radius
	_vision.see_over_coverage = see_over_coverage
	_hostility.on_sight = hostile_on_sight
	_hostility.trespass = hostile_on_trespass
	_hostility.retaliate = hostile_on_attack
	_hostility.ttl = hostility_ttl
	_memory.capacity = memory_capacity
	_tactics.cover_min = cover_min
	_tactics.flank_distance = flank_distance
	_tactics.flank_arc = flank_arc
	_tactics.flank_ally_radius = flank_ally_radius
	_tactics.shoot_range = shoot_range
	_tactics.combat_ring_radius = combat_ring_radius
	_tactics.combat_ring_count = combat_ring_count
	_tactics.still_speed = still_speed
	_tactics.route_clearance = route_clearance
	_tactics.watch_arc = watch_arc
	_tactics.fire_spot_distances = fire_spot_distances
	_tactics.throw_spot_walk = throw_spot_walk
	_entry.stack_spacing = entry_stack_spacing
	_entry.wall_standoff = entry_wall_standoff
	_entry.pie_radius = entry_pie_radius
	_entry.pie_steps = entry_pie_steps
	_entry.corner_inset = entry_corner_inset
	_entry.short_room = entry_short_room
	_entry.door_view_depth = door_view_depth
	_entry.door_avoid_ratio = door_avoid_ratio
	_entry.door_avoid_slack = door_avoid_slack
	_sync_walks()
	_throw.evade_margin = evade_margin
	_grenades.enabled = grenades_enabled
	_grenades.hear_grenade = hear_grenade
	_suspicion.still_speed = still_speed
	_suspicion.extrapolate_cap = extrapolate_cap
	_snapshot.vocab.shoot_range = shoot_range
	_snapshot.vocab.punch_range = punch_range
	_snapshot.vocab.recency_bands = recency_bands
	_snapshot.vocab.route_buckets = route_buckets
	_snapshot.vocab.aim_cone = aim_cone
	_snapshot.vocab.still_speed = still_speed
	_snapshot.vocab.flank_ally_radius = flank_ally_radius
	_snapshot.vocab.investigate_distance = investigate_distance
	_snapshot.vocab.extrapolate_cap = extrapolate_cap
	_snapshot.vocab.max_options_per_level = max_options_per_level
	_snapshot.vocab.hurt_threshold = hurt_threshold
	_snapshot.vocab.critical_threshold = critical_threshold
	_snapshot.vocab.low_ammo_fraction = low_ammo_fraction
	_snapshot.vocab.max_contacts_in_state = max_contacts_in_state
	_snapshot.vocab.search_memory_ttl = search_memory_ttl


## Push the walk rules into the entry geometry: walks keep out of the doorway views where the entry guard runs (`entry_guard`, with
## `entry_enabled` or on an ordered stack's walk, D4), and a room counts as clear for passing when it was cleared lately (`is_pass_clear`)
## or, on an ordered walk of an NPC that does not clear rooms by entry, when it has seen it empty (`seen_empty`, D11).
func _sync_walks() -> void:
	if _entry == null:
		return
	_entry.avoid_views = entry_guard and (entry_enabled or ordered_walk)
	_entry.pass_clear = _passable if ordered_walk and not entry_enabled else is_pass_clear


## Hand the perception the NPC's body, which every sense and query reads from then on, and tell the hostility rules its
## faction (so allies are never hostile). The controller calls this once it knows which character it drives.
func bind(character: Node) -> void:
	_character = character
	_hostility.faction = character.faction
	_throw.bind(character)
	_grenades.bind(character)
	_snapshot.bind(character)


# --- Event intake ----------------------------------------------------------------------------

## Classify one world `&"hit"` event (interface 10) against this NPC and fold it into memory. A hit ON
## the NPC, or any hit within `hit_awareness_radius` of it, counts as being attacked: the incoming
## direction (and whether it actually hit) is remembered (`under_fire`), the engagement is refreshed
## (`engaged`), and the attacker is handed to the hostility rules. A hit farther off but within
## `hearing_radius` is gunfire heard (`heard_gunfire`) — an investigation lead — but ONLY from a shooter
## the NPC doesn't already know is hostile: gunfire from a character it is fighting (or any other known
## hostile) is no mystery, already covered by COMBAT or that contact's last-seen lead, so it is not a lead
## to chase. The NPC's own hits are ignored, and so is an ally's round striking near it (a teammate's fire is not
## fire at it; one that hits it still is). Returns true when it was a relevant attack, so the controller
## can kick off a fight.
func process_hit(data: Dictionary) -> bool:
	var attacker = data.get("attacker")
	if attacker == _character:
		return false  # Our own shot or punch.
	var self_pos: Vector2 = _character.global_position
	var pos: Vector2 = data.get("position", self_pos)
	var from: Vector2 = -(data.get("direction", Vector2.RIGHT) as Vector2)
	var hit_me: bool = data.get("victim") == _character
	var by_ally: bool = attacker is Node and is_instance_valid(attacker) and _hostility.is_ally(attacker.get("faction") if attacker.get("faction") != null else &"")
	if not hit_me and by_ally and self_pos.distance_to(pos) <= hit_awareness_radius:
		return false  # A teammate's round striking close by: it knows who fired.
	if not hit_me and self_pos.distance_to(pos) > hit_awareness_radius:
		var known_shooter: bool = attacker is Node and is_instance_valid(attacker) \
			and _hostility.is_hostile(attacker.get_instance_id(), _memory)
		if self_pos.distance_to(pos) <= hearing_radius and not known_shooter:
			var cell := "%d,%d" % [floori(pos.x / 200.0), floori(pos.y / 200.0)]
			_memory.remember(&"heard_gunfire", { "pos": pos }, lead_memory_ttl, cell)
		return false
	_memory.remember(&"under_fire", { "from": from, "hit": hit_me }, under_fire_time, "latest")
	_memory.remember(&"engaged", {}, engage_dwell, "latest")
	if not by_ally:
		_note_shot_from(pos, from)
	if attacker is Node and is_instance_valid(attacker):
		_hostility.on_attacked(attacker, _memory)
	return true


## Remember where a shot at the NPC came from (`shot_from`, docs/grenades.md G18): the line back from where it landed (`at`), along
## `from`, to the first wall it meets (`hearing_radius` at most). A shot that came in through a doorway runs back into the room behind
## it, so that room is where the shooter is. Kept `lead_memory_ttl`, long after being under fire is over (`under_fire_time`), keyed by
## where the line ends so shots from two places are two memories.
func _note_shot_from(at: Vector2, from: Vector2) -> void:
	var dir := from.normalized()
	if dir == Vector2.ZERO:
		return
	var far := at + dir * hearing_radius
	var hit: Dictionary = _vision.wall_hit(_character.get_world_2d().direct_space_state, at, far)
	var end: Vector2 = (hit["position"] as Vector2) - dir * 4.0 if not hit.is_empty() else far
	var cell := "%d,%d" % [floori(end.x / 200.0), floori(end.y / 200.0)]
	_memory.remember(&"shot_from", { "at": at, "pos": end, "from": from }, lead_memory_ttl, cell)


## Hear one `&"footfall"` (interface 10, `{ position, character, running, crouched }`) through walls: the step of a character not of
## the NPC's own faction (its faction is how it knows its own team's steps) within earshot for its gait, `hear_run` running,
## `hear_crouch` crouched, else `hear_walk`, is remembered as `heard_footsteps` (`{ pos }`, keyed per walker, so the latest step
## stands for it; `lead_memory_ttl`): an investigation lead and a reason to suspect the room it came from (docs/hearing.md H1). A
## character it sees right now is no news. The controller drops every footfall while the NPC is deaf (G15).
func process_footfall(data: Dictionary) -> void:
	var walker = data.get("character")
	if walker == _character or not walker is Node or not is_instance_valid(walker):
		return
	var pos: Vector2 = data.get("position", Vector2.INF)
	var reach := hear_walk
	if data.get("crouched", false):
		reach = hear_crouch
	elif data.get("running", false):
		reach = hear_run
	if _character.global_position.distance_to(pos) > reach:
		return
	var f = walker.get("faction")
	if _hostility.is_ally(f if f != null else &"") or _visible_now.has(walker.get_instance_id()):
		return
	_memory.remember(&"heard_footsteps", { "pos": pos }, lead_memory_ttl, str(walker.get_instance_id()))


## The farthest any footfall is heard (px), so the controller can drop the rest before queuing them.
func footfall_reach() -> float:
	return maxf(hear_walk, maxf(hear_run, hear_crouch))


## Where the NPC last knew hostile `target_id` to be (its last sighting), else, with nobody known, where the shots at it came from
## (`shot_from`); `Vector2.INF` when it knows neither. What a combat callout radios as `target_pos` (interface 10).
func target_pos(target_id: int) -> Vector2:
	if target_id != 0:
		for seen in _memory.recall_all(&"saw_character"):
			if seen["id"] == target_id:
				return seen["pos"]
	var shot: Dictionary = _memory.recall(&"shot_from")
	return shot.get("pos", Vector2.INF)


## Fold one ally radio `&"callout"` (interface 10) into memory: what an ally says it is doing — its
## tactic, target and destination, or its step through a doorway. Ignores its own, non-allies, dead speakers,
## and anything beyond `callout_range` (<= 0 = unlimited). Each speaker's latest callout supersedes its earlier
## one. An ally that radios a room clear (`cleared_room`) teaches this NPC the room and marks it searched, so the
## team does not clear it twice.
func process_callout(data: Dictionary) -> void:
	var speaker = data.get("speaker")
	if speaker == _character or not speaker is Node or not is_instance_valid(speaker) or speaker.get("is_dead") == true:
		return
	if not _hostility.is_ally(data.get("faction", &"")):
		return
	var at: Vector2 = data.get("position", _character.global_position)
	if callout_range > 0.0 and _character.global_position.distance_to(at) > callout_range:
		return
	if AgentGrenades.is_call(data.get("status")):
		_grenades.called(data)  # "Grenade!": a live grenade, not what the ally is doing, so not a callout to weigh.
		return
	if String(data.get("order_step", "")) != "" and String(data.get("entry_step", "")) == "":
		return  # How an ally's order goes (LD7) is its squad's to hear: it leaves what the ally last said it is doing standing.
	_memory.remember(&"heard_callout", data, callout_ttl, str(speaker.get_instance_id()))
	var cleared := str(data.get("cleared_room", ""))
	if cleared != "":
		_learn_room({ "key": cleared })
		_memory.remember(&"visited_room", { "key": cleared }, search_memory_ttl, cleared)
		mark_cleared(cleared)


## Take one `&"order"` (interface 10, `docs/leadership.md` LD5: `{ id, leader, faction, to, kind, ... }`) when it names this NPC in `to`
## and comes from its own side: kept as the live order (memory topic `order`, permanent, one per NPC), replacing the one it held; a
## `cancel` ends the one it holds. An order never lapses on a timer: it ends only when it is done, cancelled or replaced (`end_order`).
## True when the NPC's order changed (the controller then decides at once).
func process_order(data: Dictionary) -> bool:
	if not (data.get("to", []) as Array).has(_character) or not _hostility.is_ally(data.get("faction", &"")):
		return false
	if String(data.get("kind", "")) == "cancel":
		var held := order()
		if held.is_empty():
			return false
		end_order(held["id"], "cancelled")
		return true
	_memory.remember(&"order", data.duplicate(), 0.0, "live")
	return true


## The live order (`process_order`), or {} when the NPC holds none.
func order() -> Dictionary:
	var held: Dictionary = _memory.recall(&"order")
	return {} if held.is_empty() or held.has("ended") else held


## End the live order when it is order `id`, for `why` (`done`, `refused`, `cancelled`): kept as ended, so it is no longer the NPC's.
## One done or refused is the leader's to hear (`take_ended_order`).
func end_order(id: Variant, why: String) -> void:
	var held := order()
	if held.is_empty() or str(held.get("id", "")) != str(id):
		return
	var ended := held.duplicate()
	ended["ended"] = why
	_memory.remember(&"order", ended, 0.0, "live")
	if why != "cancelled":
		_ended_order = { "id": held["id"], "why": why }


## The order that ended done or refused since the last call (`{ id, why }`), or {}: the controller radios it (LD7).
func take_ended_order() -> Dictionary:
	var out := _ended_order
	_ended_order = {}
	return out


## A grenade came down (`&"grenade"`, `{ position, kind, stage }`): heard if within earshot and the NPC is not `deaf`,
## so known (G16).
func process_grenade(data: Dictionary, deaf: bool) -> void:
	_grenades.hear(data, deaf)


## A grenade went off (`&"explosion"`, `{ position, kind, attacker, ... }`): it is forgotten, and so is the plan to get clear of it. A
## stun the NPC or an ally threw also blinds the hostiles it knew in its flash (`flashed`).
func process_explosion(data: Dictionary) -> void:
	_grenades.burst(data.get("position", Vector2.INF), data.get("kind", &""))
	var by = data.get("attacker")
	var team: bool = by == _character or (by is Node and is_instance_valid(by) and _hostility.is_ally(by.get("faction") if by.get("faction") != null else &""))
	last_burst = { "kind": data.get("kind", &""), "position": data.get("position", Vector2.INF), "frame": GameClock.frame(), "team": team }
	if data.get("kind") == &"stun":
		_note_flash(data)


## A stun thrown by the NPC or an ally went off at `data.position`: every hostile it knew of within the flash radius with a clear line
## from the burst is blinded for a few seconds (`FLASH_SHARE` of the stun's longest blindness at the burst, less with distance), which it holds as `flashed` (the contact's
## `blind`). It cannot see their eyes, but it knows what it threw the flash at.
func _note_flash(data: Dictionary) -> void:
	var by = data.get("attacker")
	if by != _character and not (is_instance_valid(by) and _hostility.is_ally(by.get("faction") if by.get("faction") != null else &"")):
		return
	var burst: Vector2 = data["position"]
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var rids := _character_rids()
	var flash := float(data.get("radius", 0.0))  # (The flash radius the burst reports.)
	var reach: float = _throw.cover_reach(&"stun")
	for c in _sightings(null, lead_memory_ttl, -1.0, true):
		var d: float = burst.distance_to(c["pos"])
		if d <= flash and not _throw.shielded(space, burst, c["pos"], _throw.stand_height(), rids, reach):
			_memory.remember(&"flashed", { "id": c["id"] }, maxf(_throw.max_blind_of(&"stun") * FLASH_SHARE * (1.0 - d / flash), 1.0), str(c["id"]))


## Refresh the combat engagement (called by the behaviour when it fires or adopts a fight), so an
## active firefight stays committed between decisions.
func note_engaged() -> void:
	_memory.remember(&"engaged", {}, engage_dwell, "latest")


## Whether the NPC is still committed to a fight (an `engaged` event is fresh).
func engaged_fresh() -> bool:
	return _memory.engaged()


## Whether the NPC is currently under fire (a recent incoming/nearby hit).
func under_fire() -> bool:
	return _memory.under_fire()


## The cheap facts the controller needs between decisions (e.g. to see whether a new situation should
## interrupt the decision in flight), without building the whole snapshot.
func quick_facts() -> Dictionary:
	var hostile_known := contacts(_character.global_position).any(func(c): return c["hostile"])
	return {
		"under_fire": under_fire(),
		"engaged": engaged_fresh(),
		"hostile_known": hostile_known,
		"threat_known": hostile_known or under_fire(),
		"ordered": not order().is_empty(),
	}


## The NPC reached investigation lead `lead_id` (its option carried the id in `params.lead`): remember
## it as checked, so it isn't offered again until something newer happens there.
func check_lead(lead_id: String) -> void:
	_memory.remember(&"checked_lead", { "id": lead_id }, lead_memory_ttl, lead_id)


## Number of events in memory, for the debug snapshot.
func memory_size() -> int:
	return _memory.size()


## Whether room `key` is one the shots at the NPC came from: the line back from a shot at it (`shot_from`, kept `lead_memory_ttl`) runs
## through it. The behaviour's entry guard reads it (`docs/tactical-entry.md` E9: under fire, a walk into the room the shots came from
## still goes by entry).
func shots_from_room(key: String) -> bool:
	for shot in _memory.recall_all(&"shot_from"):
		if AgentSuspicion.shot_rooms(_rooms, shot).has(key):
			return true
	return false


## Why the NPC suspects a hostile is waiting in room `key` (`docs/grenades.md` G18): its reasons, `AgentSuspicion.ORDER`'s ids (gunfire or
## footsteps heard there, shot at from it, an ally's fight in it, a hostile lost in it, by its doorway or heading in), empty when none.
## What a quiet entry reads to turn into a bang when a new one comes up (`docs/tactical-entry.md` E17).
func room_suspicion(key: String) -> Array:
	return _suspicion.rooms_suspected(_rooms, lost_hostiles(), _callouts()).get(key, [])


## Debug read: what the NPC has heard and been told, for the hearing/contacts overlays — gunfire heard
## (`pos`, `age`), footsteps heard (`footsteps`: `pos`, `age`), where shots at it came from (`shot_from`: `pos` the end of the
## line back, `at` where the shot landed, `age`), the live under-fire event (`from` direction, `hit`, seconds `left`), ally callouts
## heard (`pos`, `point`, `label`, `name`, `age`), checked leads, the
## hostiles it has lost track of, and the hearing/awareness radii. A pure read of memory; never writes it.
func debug_memory() -> Dictionary:
	var now := GameClock.msec()
	var gunfire: Array = []
	for rec in _memory.recall_aged(&"heard_gunfire"):
		gunfire.append({ "pos": rec["data"].get("pos", Vector2.ZERO), "age": rec["age"] })
	var footsteps: Array = []
	for rec in _memory.recall_aged(&"heard_footsteps"):
		footsteps.append({ "pos": rec["data"].get("pos", Vector2.ZERO), "age": rec["age"] })
	var shot_from: Array = []
	for rec in _memory.recall_aged(&"shot_from"):
		shot_from.append({ "pos": rec["data"].get("pos", Vector2.ZERO), "at": rec["data"].get("at", Vector2.ZERO), "age": rec["age"] })
	var under := {}
	var checked: Array = []
	for e in _memory.fresh():
		var left: float = maxf((e["ttl"] - (now - e["at"]) / 1000.0), 0.0) if e["ttl"] > 0.0 else 0.0
		match e["topic"]:
			&"under_fire":
				if under.is_empty():
					under = { "from": e["data"].get("from", Vector2.ZERO), "hit": e["data"].get("hit", false), "left": left }
			&"checked_lead":
				checked.append(str(e["data"].get("id", "")))
	var callouts: Array = []
	for c in _callouts():
		callouts.append({
			"name": c["name"], "age": c["age"], "label": c.get("label", ""),
			"pos": c.get("position", Vector2.ZERO), "point": c.get("point", Vector2.ZERO),
		})
	var lost: Array = []
	for c in lost_hostiles():
		lost.append({ "pos": c["pos"], "vel": c.get("vel", Vector2.ZERO), "age": c["age"], "name": c["name"] })
	return {
		"gunfire": gunfire,
		"footsteps": footsteps,
		"shot_from": shot_from,
		"under_fire": under,
		"callouts": callouts,
		"checked_leads": checked,
		"lost": lost,
		"hearing_radius": hearing_radius,
		"hit_awareness_radius": hit_awareness_radius,
		"callout_range": callout_range,
		"contact_memory_ttl": contact_memory_ttl,
		"lead_memory_ttl": lead_memory_ttl,
		"extrapolate_cap": extrapolate_cap,
	}


## Debug read: every room tagged by how this NPC regards it right now — the one it stands in
## (`current`), a room it has seen and searched recently (`searched`) or seen but not searched
## (`unsearched`), or one it has not yet seen at all (`unknown`). This is the room reasoning the
## search/room/flank options are placed against, exposed for the tactics debug overlay to draw as
## zones. A pure read of knowledge + the visited-room memory; never perturbs it.
func room_status(rooms: Array, self_pos: Vector2) -> Array:
	var known := _known_room_keys()
	var here := SnapshotVocab.room_at(self_pos, rooms)
	var out: Array = []
	for room in rooms:
		var status: StringName
		if not here.is_empty() and room["key"] == here["key"]:
			status = &"current"
		elif not known.has(room["key"]):
			status = &"unknown"
		elif _memory.age_of(&"visited_room", "key", room["key"]) > search_memory_ttl:
			status = &"unsearched"
		else:
			status = &"searched"
		out.append({ "rect": room["rect"], "type": str(room["type"]).replace("_", " "), "status": status })
	return out


# --- SEE -------------------------------------------------------------------------------------

## SEE pass — run every tick. Test what is visible via `vision` and remember it, so the agent's
## knowledge stays fresh while it can see and decays once it can't; each character sighting is also
## categorized by `hostility`. A familiar NPC's house knowledge is seeded on the first call. People
## are never seeded — they are known only once seen.
func observe(rooms: Array) -> void:
	if not _post_set:
		_post = _character.global_position
		_post_set = true
	_ensure_interactables()
	_throw.learn_carried()
	_throw.learn_body()
	_seed_house(rooms)
	_entry.set_house(openings, rooms)
	_rooms = rooms

	var self_pos: Vector2 = _character.global_position
	var facing: Vector2 = _character.facing
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	var now := GameClock.msec()

	# Every other character (the player included): one sighting per character, superseded while it
	# stays visible. Dead characters are skipped — corpses add no tactical information. A flash-blinded NPC
	# (G15) sees nothing: no new sighting, and nothing is visible, so what it holds stays where it was last seen.
	var frame := Engine.get_physics_frames()
	var swap := _visible_before
	_visible_before = _visible_now
	_visible_now = swap
	_visible_now.clear()
	_blind = _character.is_blind()
	if _blind:
		_looked.clear()
	for other in (_other_characters() if not _blind else []):
		var id: int = other.get_instance_id()
		if other.get("is_dead") == true:
			_looked.erase(id)
			continue
		if not _vision.in_view(self_pos, facing, other.global_position):
			_looked.erase(id)  # Out of the cone: not seen, and its next look is at once.
			continue
		if _looked.has(id) and (frame + get_instance_id() + id) % SIGHT_EVERY_FRAMES != 0:
			if _visible_before.has(id):
				_visible_now[id] = true  # Not due: still what the last look saw.
			continue
		_looked[id] = true
		if not _vision.can_see_node(other, self_pos, facing, space, exclude):
			continue
		var pos: Vector2 = other.global_position
		var room := SnapshotVocab.room_at(pos, rooms)
		var item = other.current_item()
		var f = other.get("faction")
		var sighting := {
			"id": id,
			"node": other,
			"name": str(other.name),
			"faction": f if f != null else &"",
			"ally": _hostility.is_ally(f if f != null else &""),
			"pos": pos,
			"vel": _track(id, pos, now),
			"facing": other.get("facing") if other.get("facing") is Vector2 else Vector2.ZERO,
			"wound_dmg": other.damage_taken(),
			"inside": not room.is_empty(),
			"room_type": room.get("type", "") if not room.is_empty() else "",
			"item": item.display_name if item != null else "nothing",
			"reloading": other.is_reloading(),
			"posture": other.posture(),
		}
		_visible_now[id] = true
		_memory.remember(&"saw_character", sighting, maxf(contact_memory_ttl, lead_memory_ttl), str(id))
		_hostility.classify(sighting, _memory)

	# The room the NPC stands in counts as searched (superseded while it stays there).
	var here := SnapshotVocab.room_at(self_pos, rooms)
	if not here.is_empty():
		_memory.remember(&"visited_room", { "key": here["key"] }, search_memory_ttl, str(here["key"]))

	_grenades.observe(_vision, space, exclude, _blind)
	if not familiar_with_house and not _blind and Engine.get_physics_frames() >= _learn_next:
		_learn_by_sight(rooms)


## An unfamiliar NPC learns the rooms and objects it can see (permanent once learned). Runs every `LEARN_EVERY_FRAMES`
## frames from `observe()`, offset per NPC so a squad does not look on the same frame, and at the start of every decision,
## so what it knows when it decides is what it sees at that moment.
func _learn_by_sight(rooms: Array) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _learned_frame:
		return
	_learn_next = frame + (LEARN_EVERY_FRAMES if _learned_frame >= 0 else 1 + get_instance_id() % LEARN_EVERY_FRAMES)
	_learned_frame = frame
	var self_pos: Vector2 = _character.global_position
	var facing: Vector2 = _character.facing
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	var known_rooms := _known_room_keys()  # Read once: what is learned here is permanent and only grows.
	for room in rooms:
		if known_rooms.has(room["key"]):
			continue  # Already learned: looking again would change nothing.
		var rect: Rect2 = room["rect"]
		if rect.has_point(self_pos) or _vision.can_see(self_pos, facing, rect.position + rect.size * 0.5, space, exclude):
			known_rooms[room["key"]] = true
			_learn_room(room)
	var known_objects := _known_object_ids()
	for obj in _interactables:
		if not is_instance_valid(obj) or known_objects.has(obj.get_instance_id()):
			continue
		if _vision.can_see_node(obj, self_pos, facing, space, exclude):
			known_objects[obj.get_instance_id()] = true
			_learn_object(obj)


## Update character `id`'s movement track with a sighting at `pos` (game msec `now`) and return its smoothed velocity, both
## measured on the game clock (`GameClock`). A sighting after a long gap restarts the track (no velocity across the gap).
## `track_smoothing` is the share of a new velocity taken per game frame, so a sighting that comes several frames after the
## last takes the share they add up to.
func _track(id: int, pos: Vector2, now: int) -> Vector2:
	var frame := GameClock.frame()
	var vel := Vector2.ZERO
	var track = _tracks.get(id)
	if track != null:
		var dt: float = (now - track["t"]) / 1000.0
		if dt > 0.0 and dt < 0.5:
			var steps: int = maxi(frame - int(track["f"]), 1)
			var share := track_smoothing if steps == 1 else 1.0 - pow(1.0 - track_smoothing, steps)
			vel = (track["vel"] as Vector2).lerp((pos - track["pos"]) / dt, share)
		elif dt == 0.0:
			vel = track["vel"]
	_tracks[id] = { "pos": pos, "vel": vel, "t": now, "f": frame }
	return vel


## Every character the agent currently knows of (seen within `contact_memory_ttl`) — the latest
## sighting per character, with `hostile` / `reason`, `visible` (seen on the latest tick) and `age`.
## Hostiles first, then nearest to `self_pos`. Dead or freed characters are dropped.
func contacts(self_pos: Vector2) -> Array:
	return _sightings(self_pos, _contact_ttl())


## Every character in memory regardless of contact_memory_ttl — all non-expired sightings (up to
## lead_memory_ttl, typically 20 s). Same dict shape as contacts() but covers stale sightings too,
## so external observers (e.g. the spectator inspector) can see the NPC's full knowledge window.
func all_seen_characters(self_pos: Vector2) -> Array:
	return _sightings(self_pos)


## Hostiles the NPC has lost track of — last seen longer ago than `contact_memory_ttl` but within
## `lead_memory_ttl` — newest first: where to investigate.
func lost_hostiles() -> Array:
	return _sightings(null, INF, _contact_ttl(), true)


## How long (s) a sighting counts as a live contact. A blinded NPC cannot tell that a contact has gone, so it keeps
## acting on every sighting its memory holds (G15); it is back to `contact_memory_ttl` the moment it can see.
func _contact_ttl() -> float:
	return maxf(contact_memory_ttl, lead_memory_ttl) if _blind else contact_memory_ttl


## The live character sightings in memory as contact dicts — the one source behind contacts(),
## all_seen_characters() and lost_hostiles(). Keeps sightings with age in (`min_age`, `max_age`];
## `hostile_only` drops non-hostiles; dead or freed characters are always dropped. Given a
## `self_pos` (a Vector2) the result is sorted hostiles-first then nearest to it, else it keeps the
## memory's newest-first order.
func _sightings(self_pos, max_age := INF, min_age := -1.0, hostile_only := false) -> Array:
	var out: Array = []
	for rec in _memory.recall_aged(&"saw_character"):
		if rec["age"] > max_age or rec["age"] <= min_age:
			continue
		var c := _live_sighting(rec)
		if c.is_empty() or (hostile_only and not c["hostile"]):
			continue
		out.append(c)
	if self_pos is Vector2:
		out.sort_custom(func(a, b):
			if a["hostile"] != b["hostile"]:
				return a["hostile"]
			return (a["pos"] as Vector2).distance_squared_to(self_pos) < (b["pos"] as Vector2).distance_squared_to(self_pos))
	return out


## A remembered sighting (`{ data, age }`) as a contact dict, or empty when its character is gone.
func _live_sighting(rec: Dictionary) -> Dictionary:
	var data: Dictionary = rec["data"]
	var n = data.get("node")
	if not is_instance_valid(n) or (n as Node).get("is_dead") == true:
		return {}
	var c := data.duplicate()
	c["age"] = rec["age"]
	c["reason"] = _hostility.reason(c["id"], _memory)
	c["hostile"] = c["reason"] != ""
	c["visible"] = _visible_now.has(c["id"])
	c["blind"] = _memory.age_of(&"flashed", "id", c["id"]) < INF
	return c


## Live ally callouts heard (latest per speaker), with `age`, `name` and the speaker's `id`.
func _callouts() -> Array:
	var out: Array = []
	for rec in _memory.recall_aged(&"heard_callout"):
		var speaker = rec["data"].get("speaker")
		if not is_instance_valid(speaker) or (speaker as Node).get("is_dead") == true:
			continue
		var c: Dictionary = rec["data"].duplicate()
		c["age"] = rec["age"]
		c["id"] = speaker.get_instance_id()
		c["name"] = str(speaker.name)
		out.append(c)
	return out


# --- BUILD (delegated to the snapshot author) ------------------------------------------------

## BUILD pass — run at the start of each decision. Gather what the NPC currently knows (contacts,
## allies' callouts, learned house knowledge, lost hostiles) and hand it, with the goal and the
## behaviour's current-activity line, to the snapshot author (agent_snapshot.gd), which turns it into
## the decision snapshot the planner walks: { facts, sections, sections_per_target, options }. The
## author reads this knowledge and the combat geometry only — it writes no memory and holds no policy.
func sense(rooms: Array, goal: String, activity: String) -> Dictionary:
	if not familiar_with_house and not _character.is_blind():
		_learn_by_sight(rooms)
	var self_pos: Vector2 = _character.global_position
	var carried := AgentThrow.carried(_character)
	var knowledge := {
		"known_rooms": _known_rooms(rooms),
		"known_room_keys": _known_room_keys(),
		"known_object_ids": _known_object_ids(),
		"interactables": _interactables,
		"post": _post,
		"entry_point": entry_point,
		"entry_enabled": entry_enabled,
		"lost": lost_hostiles(),
		"carried_grenades": carried,  # The kinds of grenade it holds, and the bodies a throw's line goes through.
		"character_rids": _character_rids() if not carried.is_empty() else [],
		"order": order(),
	}
	return _snapshot.build(rooms, goal, activity, contacts(self_pos), _callouts(), knowledge)


## The goal text as Von reads it: `{gun}` filled with what the NPC calls its gun.
func fill_goal(goal: String) -> String:
	return _snapshot.fill_goal(goal)


# --- House knowledge -------------------------------------------------------------------------

## Seed a familiar NPC's house knowledge once: remember every room and interactable as already-known
## (permanent ttl). An unfamiliar NPC skips this and learns by sight in observe(). Needs the rooms
## list, so it runs on the first observe() (not _ready).
func _seed_house(rooms: Array) -> void:
	if _seeded or not familiar_with_house:
		return
	_seeded = true
	for room in rooms:
		_learn_room(room)
	for obj in _interactables:
		if is_instance_valid(obj):
			_learn_object(obj)


## Remember a room as known (permanent).
func _learn_room(room: Dictionary) -> void:
	if not _known_room_keys().has(room["key"]):
		_memory.remember(&"saw_room", { "key": room["key"] }, 0.0, str(room["key"]))


## Remember an interactable object as known (permanent), keyed by instance id.
func _learn_object(obj: Object) -> void:
	if not _known_object_ids().has(obj.get_instance_id()):
		_memory.remember(&"saw_object", { "id": obj.get_instance_id() }, 0.0, str(obj.get_instance_id()))


## The rooms the NPC knows (all of `rooms` whose key it has learned), in `rooms` order.
func _known_rooms(rooms: Array) -> Array:
	var known := _known_room_keys()
	return rooms.filter(func(r): return known.has(r["key"]))


## The set of room keys the NPC currently knows (from `saw_room` memory), as a lookup dict.
func _known_room_keys() -> Dictionary:
	var out := {}
	for data in _memory.recall_all(&"saw_room"):
		out[data.get("key")] = true
	return out


## The set of interactable instance ids the NPC currently knows (from `saw_object` memory).
func _known_object_ids() -> Dictionary:
	var out := {}
	for data in _memory.recall_all(&"saw_object"):
		out[data.get("id")] = true
	return out


## Scan the world once for objects that advertise interactions (static furniture), caching the refs.
## Positions are read live each tick; the set itself doesn't change during a run.
func _ensure_interactables() -> void:
	if _scanned:
		return
	_scanned = true
	_interactables.clear()
	var root: Node = _character.world_root()
	if root != null:
		_collect(root)


## Recursively gather descendants whose get_interactions() is non-empty into `_interactables`.
func _collect(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("get_interactions") and not (child.get_interactions() as Array).is_empty():
			_interactables.append(child)
		_collect(child)


## Every other character in the world (the group `characters`, interface 7) under the shared world root, excluding
## the NPC itself, in tree order. Used by observe() to test each for visibility.
func _other_characters() -> Array:
	var root: Node = _character.world_root()
	if root == null:
		return []
	var out: Array = []
	for c: Node in _character.get_tree().get_nodes_in_group(&"characters"):
		if c != _character and root.is_ancestor_of(c):
			out.append(c)
	return out


# --- Combat geometry for the behaviour -------------------------------------------------------

## Whether the NPC has a clear line (no wall or solid furniture between) to a world `point` — the
## engaged contact's last-known position. The behaviour gates FIRING on this: once a contact is known,
## the NPC shoots when it has a clear line to where it knows they are, independent of its view cone.
## Both the NPC and `target` (the contact's body) are excluded, so the target doesn't block itself.
func has_line_to(target: Node2D, point: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	return not _tactics.blocked(space, _character.global_position, point, exclude)


## Of world `points`, the subset the NPC can SEE right now from where it stands — view cone + clear
## line of sight over low cover, the same sight rule used to spot characters (agent_vision.gd). The
## behaviour uses it to track which parts of a room a searcher has covered. Builds the sight query
## from the NPC's body; the NPC excludes itself.
func visible_points(points: Array) -> Array:
	if points.is_empty():
		return []
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var exclude := [_character.get_rid()]
	var self_pos: Vector2 = _character.global_position
	var facing: Vector2 = _character.facing
	var seen: Array = []
	for p in points:
		if _vision.can_see(self_pos, facing, p, space, exclude):
			seen.append(p)
	return seen


## Where the NPC's sight from where it stands toward world point `to` is first blocked — over low cover, the same
## rule that spots characters (agent_vision.gd) — or `to` itself when the line reaches it. The NPC excludes itself.
## What the vision overlay draws its visible area from; a pure read.
func sight_end(to: Vector2) -> Vector2:
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var hit: Dictionary = _vision.sight_hit(space, _character.global_position, to, [_character.get_rid()])
	return hit["position"] if not hit.is_empty() else to


## The geometry of going through doorway `opening_id` into room `into` (see agent_entry.gd `geometry`): the door's
## frame, the stack slots and pie arc on either side, and the room's corners tagged hard or soft. {} when unknown.
func entry_geometry(opening_id: String, into: String) -> Dictionary:
	return _entry.geometry(opening_id, into, _character.get_world_2d().navigation_map, _character.get_world_2d().direct_space_state)


## Mark room `key` cleared: its entry was carried through to the end (or searched by sight to the end), by this NPC or
## by an ally who radioed it. Not the same as having stood in it (`visited_room`): a room walked through unprepared is
## visited, not cleared. It lapses after `search_memory_ttl`, like a searched room. A stack order into it is done.
func mark_cleared(key: String) -> void:
	_memory.remember(&"cleared_room", { "key": key }, search_memory_ttl, key)
	var held := order()
	if String(held.get("kind", "")) == "stack" and String(held.get("into", "")) == key:
		end_order(held["id"], "done")  # A stack order ends at its room cleared (LD9), by this NPC or by an ally who radioed it.


## Whether room `key` is cleared (see `mark_cleared`).
func is_cleared(key: String) -> bool:
	return _memory.age_of(&"cleared_room", "key", key) <= search_memory_ttl


## The first doorway on the walk `path` (from waypoint `from_idx`, `max_dist` px of it at most) that leads into a room that
## is not cleared (nor, on an ordered walk of an NPC that does not clear rooms by entry, seen empty: D11), as `{ opening, into, dist }`,
## or {} (see agent_entry.gd `threshold_ahead`).
func threshold_ahead(path: PackedVector2Array, from_idx: int, max_dist: float) -> Dictionary:
	var clear := is_cleared
	if ordered_walk and not entry_enabled:
		clear = func(key: String) -> bool: return is_cleared(key) or seen_empty(key)  # D11: a room seen empty is passed through.
	return _entry.threshold_ahead(path, from_idx, _character.global_position, clear, max_dist)


## The first doorway view the walk `path` goes into without entering the room behind it, as `{ opening, into, dist }`, or {} (see
## agent_entry.gd `passing_ahead`): a doorway to be secured before the NPC crosses its view (E15, E18).
func passing_ahead(path: PackedVector2Array, from_idx: int, max_dist: float) -> Dictionary:
	var world: World2D = _character.get_world_2d()
	return _entry.passing_ahead(path, from_idx, _character.global_position, max_dist, world.navigation_map, world.direct_space_state)


## Whether room `key` counts as safe to walk past: cleared within `entry_pass_clear_time` (a room cleared longer ago is cleared for
## the entry, `is_cleared`, but a doorway into it is not safe to walk past again).
func is_pass_clear(key: String) -> bool:
	return _memory.age_of(&"cleared_room", "key", key) <= entry_pass_clear_time


## Whether the NPC has stood in room `key` within `entry_pass_clear_time` and has seen no hostile in it since (the latest sighting of
## each hostile it knows of, within that time, lies elsewhere): a room seen empty (`docs/leadership.md` D11). A room only glimpsed through
## its doorway was not stood in, so it is not.
func seen_empty(key: String) -> bool:
	if _memory.age_of(&"visited_room", "key", key) > entry_pass_clear_time:
		return false
	for c in _sightings(null, entry_pass_clear_time, -1.0, true):
		if str(SnapshotVocab.room_at(c["pos"], _rooms).get("key", "")) == key:
			return false
	return true


## Whether room `key` counts as clear for passing on an ordered walk of an NPC that does not clear rooms by entry (D11): cleared lately,
## or seen empty.
func _passable(key: String) -> bool:
	return is_pass_clear(key) or seen_empty(key)


## Whether the routes a snapshot measures can be the ones the NPC will walk (see agent_entry.gd `warm`): the avoid map for the doorway
## views from the room it stands in is baked. Asking starts the bake. After `WARM_CAP_MS` of waiting it is true anyway, so a decision
## never waits for good.
func routes_ready() -> bool:
	var world: World2D = _character.get_world_2d()
	if _entry.warm(_character.global_position, world.navigation_map, world.direct_space_state):
		_warming_since = -1
		return true
	var now := GameClock.msec()
	if _warming_since < 0:
		_warming_since = now
	return now - _warming_since > WARM_CAP_MS


## The doorway views the NPC's walks keep out of from where it stands, each `{ id, into, poly }` (see agent_entry.gd `avoided`): what the
## entry plan overlay draws.
func avoided_views() -> Array:
	var world: World2D = _character.get_world_2d()
	return _entry.views_from(_character.global_position, world.navigation_map, world.direct_space_state) if _entry.avoid_views else []


## The route the NPC walks from where it stands to `to` (see agent_entry.gd `walk_route`): the plain one, or the one that keeps out of
## the views of the doorways into rooms not clear for passing when there is one within the cap.
func walk_route(to: Vector2, exempt := "") -> Dictionary:
	var world: World2D = _character.get_world_2d()
	return _entry.walk_route(_character.global_position, to, world.navigation_map, world.direct_space_state, exempt)


## The doorways out of the cleared room `into` that lead on into a room that is not cleared, other than `opening_id` (the
## one the NPC came in by): what the team covers once the room is clear, as `{ id, into, pos, width }` (see
## agent_entry.gd `watch_doors`).
func entry_watch_doors(into: String, opening_id: String) -> Array:
	return _entry.watch_doors(into, opening_id, is_cleared)


## Every doorway of room `room_key`, outer doors included, as `{ id, pos, width }` (see agent_entry.gd `room_doorways`): the
## places a resting NPC watches.
func room_doorways(room_key: String) -> Array:
	return _entry.room_doorways(room_key)


## The allies' live claims on doorway `opening_id`, off the radio: `{ id, name, slot, side, step, covering, pos, age }`,
## lowest slot first (see agent_entry.gd `claims`).
func entry_team(opening_id: String) -> Array:
	return AgentEntry.claims(opening_id, _callouts())


## The lowest stack slot (1 = the point) no ally in `team` has claimed, for the NPC with instance id `self_id` that
## holds `current` (see agent_entry.gd `free_slot`).
func entry_free_slot(team: Array, self_id: int, current := 0) -> int:
	return AgentEntry.free_slot(team, self_id, current)


## The side of a doorway (`geometry` from `entry_geometry`) the team stacks on (see agent_entry.gd `stack_side`).
func entry_team_side(geometry: Dictionary, team: Array, self_pos: Vector2) -> int:
	return AgentEntry.stack_side(geometry, team, self_pos)


## The side of a doorway the NPC stacks on from where it stands: the team's, unless its way there crosses the doorway's view, then its
## own (a split stack, see agent_entry.gd `stack_side_from`).
func entry_stack_side(geometry: Dictionary, team: Array) -> int:
	var world: World2D = _character.get_world_2d()
	return _entry.stack_side_from(geometry, team, _character.global_position, world.navigation_map, world.direct_space_state)


## The members of a stack (claims with `id`, `slot`, `side`, the NPC's own among them) in the order they cross (see agent_entry.gd
## `crossing_order`).
func entry_crossing_order(members: Array) -> Array:
	return AgentEntry.crossing_order(members)


## The place in its side's file of the member holding slot `slot` on side `side` (see agent_entry.gd `place`).
func entry_place(team: Array, side: int, slot: int) -> int:
	return AgentEntry.place(team, side, slot)


## Where the `nth` place in the file on side `side` of a doorway stands (see agent_entry.gd `slot_point`).
func entry_slot_point(geometry: Dictionary, side: int, nth: int) -> Vector2:
	return AgentEntry.slot_point(geometry, side, nth)


## Candidate standing points on a ring around the NPC, classified for peek-and-cover against the
## engaged contact's KNOWN position `tgt_pos`: `fire` points have a clear line to it; `cover` points
## are shielded from it by a high-coverage solid. Both nearest-first (see agent_tactics.gd).
func combat_spots(target: Node2D, tgt_pos: Vector2, radius: float, count: int) -> Dictionary:
	var exclude := [_character.get_rid()]
	if target != null and is_instance_valid(target):
		exclude.append(target.get_rid())
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	return _tactics.combat_spots(space, _character.global_position, tgt_pos, exclude, radius, count)


# --- Grenades --------------------------------------------------------------------------------

## The live grenades the NPC knows of (seen, heard, called or its own), soonest to go off first, as
## `{ point, kind, fuse_left, fuse, radius, source }` (`source`: `&"seen"` / `&"heard"` / `&"called"` / `&"own"`).
func known_grenades() -> Array:
	return _grenades.known()


## The plan to get clear of the live grenade that goes off first among those the NPC is in the danger zone of (or is
## already running from): `{ id, point, kind, radius, spot, crouch, fuse_left }` (see agent_grenades.gd `plan`), or {}. Made
## from where the NPC stands and kept while the grenade lives. A pure read of what it knows plus the physics space and the navmesh.
func evade_plan() -> Dictionary:
	if not _grenades.has_known():
		return {}
	return _grenades.plan(_character.get_world_2d().direct_space_state, _character.get_world_2d().navigation_map,
		_character_rids())


## The grenades to radio now, `{ point, kind }`, each once, when they have come down (see agent_grenades.gd `announcements`).
func grenade_announcements() -> Array:
	return _grenades.announcements()


## Whether a thrower standing at `at` can lob a grenade of `kind` onto `to`: within its throw range, and the lob from its hand is clear
## of everything between, low furniture included (agent_throw.gd `can_lob`). `walked`: the thrower walks to `at` first, so the lob must be
## clear wherever that walk may end (`throw_clear_on_arrival`).
func can_lob(at: Vector2, to: Vector2, kind: StringName, walked := false) -> bool:
	var space: PhysicsDirectSpaceState2D = _character.get_world_2d().direct_space_state
	var rids: Array = _character_rids()
	if not walked:
		return _throw.can_lob(space, at, to, _throw.range_of(kind), rids)
	return at.distance_to(to) <= _throw.range_of(kind) and _throw.throw_clear_on_arrival(space, at, to, rids)


## Whether the lob a thrower standing at `at` throws onto `to` flies clear, from its hand (any distance: the range is `grenade_range`'s).
func throw_clear(at: Vector2, to: Vector2) -> bool:
	return _throw.throw_clear(_character.get_world_2d().direct_space_state, at, to, _character_rids())


## How far (px) a grenade of `kind` first comes down (what the NPC learned of it off the grenades it carries).
func grenade_range(kind: StringName) -> float:
	return _throw.range_of(kind)


## How far (px) from its spot a thrower stands to let a grenade of `kind` go: its range less a few px, so one that drifted a step past it
## closes in first (agent_throw.gd `reach_of`).
func grenade_reach(kind: StringName) -> float:
	return _throw.reach_of(kind)


## Seconds from release to the burst of a grenade of `kind` (what the NPC learned of it off the grenades it carries).
func grenade_fuse(kind: StringName) -> float:
	return _throw.fuse_of(kind)


## The rids of every character in the world, this NPC included: the bodies a blast or a lob goes through.
func _character_rids() -> Array:
	var rids := [_character.get_rid()]
	for other in _other_characters():
		if other is CollisionObject2D:
			rids.append(other.get_rid())
	return rids
