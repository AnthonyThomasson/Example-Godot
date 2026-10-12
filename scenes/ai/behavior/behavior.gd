extends Node

## AI BEHAVIOUR sub-domain. Runs the LEAF the decision planner chose — one behaviour PRIMITIVE with its
## params — as concrete movement and actions on the character, and holds the System-Two state Von (a
## stateless single-shot ranker) lacks: the engaged contact, the peek-and-cover combat cycle, the
## interaction in progress, and the COMMITMENT that keeps a choice running until it completes or a
## re-decision is due. The primitives:
##   move     — go to `point` (or until entering `arrive_room`), aiming along the way (`aim`: travel /
##              target / threat / point), shooting a known hostile on a clear line when `fire_at_will`; a
##              `look_around` search move covers the room by sight: it turns and relocates until it has seen all of it.
##   engage   — go to `point`, then fight `target_id` from there: `peek_cover` (step out, shoot, duck)
##              or `ambush` (hold the covered spot, fire the moment a line opens).
##   melee    — close on `target_id` and punch.
##   interact — walk to `object`, run its interaction `id`, hold it for `interaction_dwell`.
##   reload   — stand and swap in a fresh magazine (`Character.reload()`), then re-decide.
##   hold     — stay and watch.
## It never chooses WHAT to do — the planner does — and applies no policy beyond the params it is
## handed (`confine_inside` keeps a territorial NPC from chasing out of the house). It owns a
## `Locomotion` child for all pathing, reads the world only through the PERCEPTION sub-domain (known
## contacts, combat geometry, engagement memory) and drives the character only through its public
## controller contract (`move_input` / `aim_point`, `select_slot`, `shoot`, `melee`, `interact_with`,
## `end_interaction`). All tunables are set by the controller before `setup()`.

const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
## Inventory slot of the fists (ItemRegistry id). The gun it shoots is whatever the character fights with
## (`Character.gun_slot()`): nothing here knows one gun from another.
const FISTS_SLOT := 2
## Facing error (radians) within which a shot is taken — aim settles a frame after it is set.
const AIM_TOLERANCE := 0.15

# --- Config fields the controller copies from its exports before setup(). ---
var interaction_dwell: float = 3.0
var max_commit_time: float = 6.0
var search_look_rate: float = 2.5 ## Gaze turn speed (rad/s) while a searcher looks around a room it is covering.
var search_coverage_spacing: float = 64.0 ## Room sample-grid spacing (px): smaller = finer coverage, more sight rays.
var search_coverage_target: float = 1.0 ## Fraction of sampled points that must be SEEN to call a room covered (1 = all).
var search_coverage_budget: float = 8.0 ## Max seconds spent covering one room before giving up and re-deciding (safety cap).
var search_coverage_approach: float = 300.0 ## Walk toward an unseen point beyond this range (or whose line is blocked); else just turn to it.
var search_coverage_margin: float = 24.0 ## Inset (px) from the room's walls where sampling starts, so points sit off the walls.
var tactic_interval: float = 3.0
var shoot_range: float = 500.0
var punch_range: float = 48.0
var combat_ring_radius: float = 80.0
var combat_ring_count: int = 12
var cover_time: float = 1.2
var fire_cooldown: float = 0.5
## Rounds an automatic gun fires per trigger pull (paced by the gun's own fire rate); a single-shot gun fires one.
var fire_burst: int = 3
## Seconds spent stepping back when the gun's barrel is against a wall or object and cannot fire.
var back_off_time: float = 0.45
var reposition_interval: float = 0.5
# Locomotion config (forwarded to the Locomotion child in setup()).
var arrive_dist: float = 10.0
# Running: whether the NPC may sprint on the way to a destination (see `_should_run`).
var run_enabled: bool = true ## May sprint at all.
var run_min_distance: float = 150.0 ## Only run when farther than this (px) from the destination.
var run_start_fraction: float = 0.5 ## Stamina needed to START a run (once running it goes on until dry).
var auto_reload: bool = true ## An empty gun with a spare magazine is reloaded on its own while holding or ducked in cover.
# Posture: whether the NPC may crouch in a fight (see `_wanted_posture`), and how long it keeps one before changing.
var posture_enabled: bool = true
var posture_dwell: float = 0.7

## World-space room rects (`{ key, type, rect }`), set each tick by the controller from Main's inject.
var rooms: Array = []

var _perception: Node             ## The perception sub-domain (contacts, combat geometry, engagement memory).
var _loco: Node                   ## The Locomotion child (pathing).
var _hostiles: Array = []         ## Known hostile contacts this tick (nearest first), from perception.
var _primitive: StringName = &"hold" ## The running primitive.
var _params := {}                 ## Its params (from the leaf).
var _path: Array = []             ## The decision path ids (e.g. ["combat", "t_12", "flank", "side_left"]).
var _labels: Array = []           ## The decision path as labels (e.g. ["COMBAT", "Intruder", "FLANK", "their left side (kitchen)"]).
var _leaf_ms := 0                 ## When the running leaf was adopted.
var _point := Vector2.ZERO        ## The leaf's destination, snapped onto the navmesh.
var _arrive_room := ""            ## A move that completes on ENTERING this room ("" = on reaching `_point`); ignored while looking around.
var _arrived := false             ## Whether the destination has been reached.
var _look_around := false         ## A search/explore move that covers the room by sight on arrival (vs resolving at once).
var _look_angle := 0.0            ## Current gaze angle (rad), eased toward the nearest unseen point so looking is smooth.
var _cover_points: Array = []     ## All room sample points this search (kept whole for the coverage fraction + debug).
var _cover_unseen: Array = []     ## The subset of `_cover_points` not yet SEEN (view cone + line of sight).
var _cover_target := Vector2.ZERO ## The unseen point currently being looked at / walked to (for the debug overlay).
var _cover_room := ""             ## Key of the room being covered, locked on arrival.
var _cover_budget := 0.0          ## Seconds left before the coverage gives up on unseeable nooks and re-decides.
var _engage_id := 0               ## Instance id of the contact being fought (0 = none).
var _engage_node: Node2D          ## That contact's body (excluded from line-of-fire rays).
var _engage_pos := Vector2.ZERO   ## That contact's last-KNOWN position (from memory).
var _engage_inside := false       ## Whether that contact was last seen inside the house.
var _running := false             ## The character was running last tick (for the status line).
var _posture: StringName = &"stand" ## The character's posture last tick (for the status line and overlays).
var _posture_hold := 0.0          ## Seconds before a crouch may be swapped for standing (no flicker).
var _reloading := false           ## The character was reloading last tick (for the status line and overlay).
var _reload_started := false      ## A `reload` leaf has seen its reload begin, so it ends when the reload does.
var _hold_ground := false         ## Combat: stay inside the house (territorial vs. an outsider).
var _combat_phase := "peek"       ## Peek-and-cover phase: "peek" (seek a shot) or "cover" (duck).
var _cover_timer := 0.0           ## Seconds left ducking behind cover before peeking again.
var _fire_timer := 0.0            ## Seconds left before the next shot/punch may be thrown.
var _burst_left := 0              ## Rounds still to fire in the automatic gun's current burst.
var _back_off_timer := 0.0        ## Seconds left stepping back from whatever the gun's barrel is against.
var _combat_dest := Vector2.ZERO  ## Committed fire/cover position the NPC is steering toward.
var _combat_dest_timer := 0.0     ## Seconds left before a new combat position may be chosen.
var _tactic_timer := 0.0          ## Seconds left before a fight re-asks which tactic to use.
var _target_obj: Node             ## The object to approach + use (interact), else null.
var _interact_id := ""            ## The interaction id to run on `_target_obj`.
var _act_armed := false           ## Delays an interaction one frame so facing settles first.
var _in_interaction := false      ## Committed to an active object interaction.
var _interaction_timer := 0.0     ## Seconds left before ending the current interaction.
var _commit_timer := 0.0          ## Seconds left on the current move/approach commitment (safety cap).
var _resolved := false            ## A task just finished (arrived / interaction ended / target lost) → re-decide.


## Build the Locomotion child and capture the perception sub-domain. The controller calls this once in
## its _ready(); it then pushes the config fields in with apply_config() (here and again each decision).
func setup(perception: Node, nav_agent: NavigationAgent2D) -> void:
	_perception = perception
	_loco = Locomotion.new()
	_loco.setup(nav_agent)
	add_child(_loco)


## Push the current config into the Locomotion child. The behaviour's own fields are read live, so only
## the forwarded locomotion tunables need pushing. Idempotent, so the controller may call it each
## decision to pick up an export retuned at runtime.
func apply_config() -> void:
	_loco.arrive_dist = arrive_dist


# --- Read-only views -------------------------------------------------------------------------

## Read-only: the decision path the NPC is carrying out, as ids ("combat/t_12/flank/side_left").
func current_act() -> String:
	return "/".join(_path) if not _path.is_empty() else "hold"


## Read-only: the broad mode of the running leaf (combat / investigate / search / idle / hold).
func intent() -> String:
	return str(_path[0]) if not _path.is_empty() else "hold"


## Read-only: whether the NPC is fighting (so a fresh hit doesn't force a re-decision).
func in_combat() -> bool:
	return intent() == "combat"


## Read-only: whether the running choice is still in progress (en route, fighting, using an object)
## rather than finished (arrived, holding) — the planner only offers "keep your current plan" for one
## still in progress.
func ongoing() -> bool:
	match _primitive:
		&"move":
			return not _arrived
		&"engage", &"melee":
			return true
		&"interact":
			return true
		&"reload":
			return _reloading
	return false


## Read-only: the engaged contact's last-seen inside/outside state packed into the salient key — the
## controller re-decides when this (or the known-hostile set) changes.
func salient_key() -> String:
	var ids: Array = _hostiles.map(func(c): return c["id"])
	ids.sort()
	return "%s|%s" % [str(ids), str(_engage_inside) if _engage_id != 0 else "-"]


## Read-only: the FULL decision path the NPC is carrying out, every level from the broad mode down to
## the concrete option ("COMBAT - Intruder - FLANK - their left side (kitchen)"), then where it is
## in carrying it out — for debug overlays and the HUD.
func debug_status() -> String:
	var line: String = " - ".join(_labels) if not _labels.is_empty() else "HOLD"
	var state := _progress()
	if state != "":
		line += "  · " + state
	if _posture != &"stand":
		line += "  · " + "crouching"
	if _perception != null and _perception.under_fire():
		line += "  ⚠ under fire"
	return line


## Read-only: what the NPC is doing, for Von's "current activity" line: the full path, its progress
## and how long it has been at it.
func activity_text() -> String:
	if _labels.is_empty():
		return ""
	var secs := int((Time.get_ticks_msec() - _leaf_ms) / 1000.0)
	return "%s (%s, for %ds)" % [" - ".join(_labels), _progress(), secs]


## Where the running primitive stands ("en route", "in position, ducking behind cover", …).
func _progress() -> String:
	match _primitive:
		&"move":
			return "reached it" if _arrived else ("running" if _running else "en route")
		&"engage":
			if not _arrived:
				return "running into position" if _running else "moving into position"
			if _params.get("style", &"peek_cover") == &"ambush":
				return "in ambush, waiting for a shot"
			return "in position, %s" % ("ducking behind cover" if _combat_phase == "cover" else "looking for a shot")
		&"melee":
			return "running in to punch" if _running else "closing in to punch"
		&"interact":
			return "using it" if _in_interaction else "walking to it"
		&"reload":
			return "reloading"
	return "waiting" if not _labels.is_empty() else ""


## Read-only: the full primitive/engagement/commitment state as structured data, for the controller's
## `debug_state()` snapshot. Built from live state (never mutates); JSON-safe.
func debug_state() -> Dictionary:
	return {
		"act": current_act(),
		"labels": " - ".join(_labels),
		"primitive": String(_primitive),
		"params": _json_safe(_params),
		"arrived": _arrived,
		"running": _running,
		"posture": String(_posture),
		"reloading": _reloading,
		"engage": str(_engage_node.name) if is_instance_valid(_engage_node) else "",
		"engage_id": _engage_id,
		"engage_inside": _engage_inside,
		"combat_phase": _combat_phase,
		"hold_ground": _hold_ground,
		"hostiles_known": _hostiles.size(),
		"in_interaction": _in_interaction,
		"timers": {
			"commit": _commit_timer,
			"tactic": _tactic_timer,
			"interaction": _interaction_timer,
			"fire": _fire_timer,
			"cover": _cover_timer,
			"combat_dest": _combat_dest_timer,
		},
		"loco": _loco.debug_state(),
	}


## Read-only: the running search-coverage state, for the search debug overlay. `active` is true only
## while a `look_around` move is actually covering a room (arrived, not yet resolved); `points` are all
## the room's sample points, `unseen` the ones still to be seen, `target` the one being looked at now.
func debug_coverage() -> Dictionary:
	return {
		"active": _primitive == &"move" and _look_around and _arrived and not _resolved,
		"points": _cover_points,
		"unseen": _cover_unseen,
		"target": _cover_target,
		"budget": _cover_budget,
	}


## Read-only: the running combat / movement / interaction state as world-space data (Vector2s, not the
## JSON-safe digest), for the combat, territory and targets debug overlays. `character` is the NPC's body,
## needed for its aim point and the fire-line query. A pure read — the line query only casts a ray.
func debug_combat(character) -> Dictionary:
	var engaged := _engage_id != 0
	var in_range := false
	var fire_clear := false
	if engaged and character != null:
		in_range = character.global_position.distance_to(_engage_pos) <= shoot_range
		fire_clear = in_range and _perception.has_line_to(character, _engage_node, _engage_pos)
	var fighting := _primitive in [&"engage", &"melee"]
	var obj_pos = null
	if _primitive == &"interact" and is_instance_valid(_target_obj) and _target_obj is Node2D:
		obj_pos = (_target_obj as Node2D).global_position
	return {
		"primitive": _primitive,
		"style": _params.get("style", &"peek_cover") if _primitive == &"engage" else &"",
		"engaged": engaged,
		"engage_pos": _engage_pos,
		"engage_inside": _engage_inside,
		"hold_ground": _hold_ground,
		"in_range": in_range,
		"fire_clear": fire_clear,
		"shoot_range": shoot_range,
		"punch_range": punch_range,
		"combat_phase": _combat_phase if fighting else "",
		"cover_timer": _cover_timer,
		"cover_time": cover_time,
		"fire_timer": _fire_timer,
		"fire_cooldown": fire_cooldown,
		"combat_dest": _combat_dest if _primitive == &"engage" and _arrived and _combat_dest != Vector2.ZERO else null,
		"aim_point": character.aim_point if character != null else Vector2.ZERO,
		"fire_at_will": bool(_params.get("fire_at_will", false)),
		"reloading": _reloading,
		"requested_point": _params["point"] if _params.has("point") else null,
		"point": _point if _params.has("point") else null,
		"arrived": _arrived,
		"arrive_room": _arrive_room,
		"object_pos": obj_pos,
		"in_interaction": _in_interaction,
		"interaction_timer": _interaction_timer,
		"interaction_dwell": interaction_dwell,
		"watch_pos": _hostiles[0]["pos"] if _primitive == &"hold" and not _hostiles.is_empty() else null,
		"reachable": _loco.debug_state().get("reachable", true),
		"timers": { "commit": _commit_timer, "commit_max": max_commit_time, "tactic": _tactic_timer, "tactic_max": tactic_interval },
	}


## Read-only: the movement-progress sample (speed, seconds stalled, recent trail) for the stuck overlay.
func debug_progress() -> Dictionary:
	return _loco.debug_progress()


## A params dict with points as [x, y] and objects as names, so an observer can serialize it.
func _json_safe(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v = d[k]
		if v is Vector2:
			out[k] = [int(v.x), int(v.y)]
		elif v is Object:
			out[k] = str(v.name) if is_instance_valid(v) and v is Node else "?"
		else:
			out[k] = v if v is bool or v is int or v is float else str(v)
	return out


# --- Adopting a decision ---------------------------------------------------------------------

## Adopt the planner's leaf `{ path, labels, primitive, params }`: capture its destination (snapped
## onto the navmesh), its target and its object, and commit to it.
func set_leaf(leaf: Dictionary) -> void:
	_primitive = leaf.get("primitive", &"hold")
	_params = leaf.get("params", {})
	_path = leaf.get("path", [])
	_labels = leaf.get("labels", [])
	_leaf_ms = Time.get_ticks_msec()
	_arrived = false
	_act_armed = false
	_commit_timer = max_commit_time
	_arrive_room = str(_params.get("arrive_room", ""))
	_look_around = bool(_params.get("look_around", false))
	_cover_points = []          # Room sample points, built on arrival once we know which room we're in.
	_cover_unseen = []
	_cover_target = Vector2.ZERO
	_cover_room = ""
	_point = _loco.reachable(_params["point"]) if _params.has("point") else Vector2.ZERO
	_target_obj = null
	_engage_id = 0
	var target_id: int = _params.get("target_id", 0)
	if target_id != 0:
		_engage(target_id)
	match _primitive:
		&"engage", &"melee":
			if _engage_id == 0:
				_primitive = &"hold"  # The target was lost while deciding; re-decide.
				_resolved = true
				return
			_combat_phase = "peek"
			_combat_dest_timer = 0.0
			_tactic_timer = tactic_interval
			_perception.note_engaged()  # Commit to the fight (refreshed by firing).
		&"interact":
			_target_obj = _params.get("object")
			_interact_id = _params.get("id", "")
		&"reload":
			_reload_started = false


## Fight known contact `id`: capture its body and last-known position (no-op when it isn't known).
func _engage(id: int) -> void:
	for c in _hostiles:
		if c["id"] == id:
			_engage_id = id
			_engage_node = c["node"]
			_engage_pos = c["pos"]
			_engage_inside = c.get("inside", false)
			return


## A steady stance for when no decision can be had (Von unreachable): stop and watch any known hostile.
func fallback() -> void:
	_primitive = &"hold"
	_params = {}
	_path = []
	_labels = []
	_target_obj = null


# --- Per-tick bookkeeping ---------------------------------------------------------------------

## Resolve what the NPC currently knows from the perception's contact list (the engaged contact's
## last-known body/position/inside state) and advance the commitment timers. If the engaged contact is
## no longer known (its sighting decayed) or no longer hostile, a fight retargets to the nearest other
## known hostile; with none left, a leaf that needs a target ends and this returns true so the
## controller re-decides. All acting reads these rather than true positions, so the NPC only ever acts
## on what it has perceived.
func update_known(known: Array, delta: float) -> bool:
	_commit_timer -= delta
	_tactic_timer -= delta
	_hostiles = known.filter(func(c): return c["hostile"])
	if _engage_id == 0:
		return false
	var engaged: Dictionary = {}
	for c in _hostiles:
		if c["id"] == _engage_id:
			engaged = c
	if engaged.is_empty():
		engaged = _hostiles[0] if not _hostiles.is_empty() else {}
		_engage_id = engaged.get("id", 0)
	if not engaged.is_empty():
		_engage_node = engaged["node"]
		_engage_pos = engaged["pos"]
		_engage_inside = engaged.get("inside", false)
		return false
	if _needs_target():
		_primitive = &"hold"
		return true
	return false


## Whether the running leaf is pointless without its target (a fight, or a move aimed at it).
func _needs_target() -> bool:
	return _primitive in [&"engage", &"melee"] or (_primitive == &"move" and _params.get("aim") == &"target")


## Advance an active interaction: hold it until its dwell runs out, the character leaves it, or the
## controller forces a rethink (`force`); then end it and flag the task resolved. Returns true while the
## NPC is STILL interacting (the controller should do nothing more this tick).
func service_interaction(character, delta: float, force: bool) -> bool:
	if not _in_interaction:
		return false
	_interaction_timer -= delta
	if force or not character.is_busy() or _interaction_timer <= 0.0:
		character.end_interaction()
		_in_interaction = false
		_resolved = true  # Pick the next step right away rather than wait out the cadence.
		return false
	return true


## Whether a committed task just finished (arrived / interaction ended / target lost while deciding).
## Clears the flag; the controller forces a re-decision when it returns true.
func take_resolved() -> bool:
	var r := _resolved
	_resolved = false
	return r


## The investigation lead the running move has reached (its `lead` param), or "" — so the controller
## can tell perception it was checked.
func reached_lead() -> String:
	return str(_params.get("lead", "")) if _primitive == &"move" and _arrived else ""


## Whether the running leaf wants a new decision now: a fight still moving into position holds until
## its safety cap; once in position it re-asks its tactic every `tactic_interval` or when the
## engagement lapses; a move or approach holds until it completes (which forces a decision) or its
## safety cap runs out; a hold follows the decide cadence.
func wants_decision(_character, decide_timer_elapsed: bool) -> bool:
	match _primitive:
		&"engage":
			if not _arrived:
				return _commit_timer <= 0.0
			return _tactic_timer <= 0.0 or not _perception.engaged_fresh()
		&"melee":
			return _tactic_timer <= 0.0 or not _perception.engaged_fresh()
		&"move":
			if _look_around and _arrived and not _resolved:
				return false  # Hold through room coverage; it ends itself (all seen, or the budget runs out).
			return _commit_timer <= 0.0
		&"interact", &"reload":
			return _commit_timer <= 0.0
	return decide_timer_elapsed


# --- Running the primitive --------------------------------------------------------------------

## Carry out the running primitive this tick.
func apply(character, delta: float) -> void:
	_fire_timer -= delta
	_loco.sample(character, delta)  # Observation only (stuck overlay); never alters the tick.
	match _primitive:
		&"move":
			_apply_move(character, delta)
		&"engage":
			_apply_engage(character, delta)
		&"melee":
			_apply_melee(character)
		&"interact":
			_apply_interact(character)
		&"reload":
			_apply_reload(character)
		_:
			_apply_hold(character)
	_continue_burst(character)
	character.run_input = _should_run(character)
	_apply_back_off(character, delta)
	_apply_posture(character, delta)
	_running = character.is_running()
	_posture = character.posture()
	_reloading = character.is_reloading()


## Take the posture `_wanted_posture` asks for. Standing back up is never delayed (a run, the end of a fight);
## a crouch is held for `posture_dwell` before it is dropped, so a peek-and-duck does not flicker. A
## change the character refuses (its own pacing, an interaction) is simply asked again next tick.
func _apply_posture(character, delta: float) -> void:
	_posture_hold = maxf(_posture_hold - delta, 0.0)
	var want := _wanted_posture(character)
	if want == character.posture() or (want != &"stand" and _posture_hold > 0.0):
		return
	if character.set_posture(want):
		_posture_hold = posture_dwell


## The posture to take this tick: a manner of carrying out the leaf, not something Von chooses, so it works with
## the server down. Only a standing body runs, so anything on the move to a destination stands, and so does
## everything outside a fight. Fighting in place (an engaged NPC in position, or one holding / reloading while a hostile is known or
## shots are landing) it crouches: a smaller target, and it hides behind cover as high as a crouch.
func _wanted_posture(character) -> StringName:
	if not posture_enabled or character.run_input:
		return &"stand"
	var under_fire: bool = _perception != null and _perception.under_fire()
	if _hostiles.is_empty() and not under_fire:
		return &"stand"
	match _primitive:
		&"engage":
			if not _arrived:
				return &"stand"
		&"hold", &"reload":
			pass
		_:
			return &"stand"
	return &"crouch"


## Whether to sprint this tick, judged after the primitive has steered: only while travelling to a
## destination (a move or engage approach that hasn't arrived, a melee closing in; never an ambush,
## peek, room search, interaction or hold), when the leaf asks for it (`params.run`) or the NPC is under
## fire, the destination is farther than `run_min_distance`, and a run can be started (stamina
## `run_start_fraction`, or already running). The Character spends the stamina and runs dry on its own.
func _should_run(character) -> bool:
	if not run_enabled or character.move_input == Vector2.ZERO:
		return false
	var dest := _point
	match _primitive:
		&"move":
			if _arrived or _look_around:
				return false
		&"engage":
			if _arrived:
				return false
		&"melee":
			dest = _engage_pos
		_:
			return false
	if not _params.get("run", false) and not (_perception != null and _perception.under_fire()):
		return false
	if character.global_position.distance_to(dest) <= run_min_distance:
		return false
	return character.is_running() or character.stamina_fraction() >= run_start_fraction


## Move: walk to the destination (or into the destination room), aiming as the leaf asks, and — when
## `fire_at_will` — shoot a known hostile the moment there is a clear line. A `look_around` move (search /
## explore) walks all the way to the interior point and, on arrival, COVERS the room by sight — turning
## and relocating until it has seen (near-)every sampled point (see `_cover_room_step`) — before flagging
## the task resolved; any other move flags resolved the moment it arrives.
func _apply_move(character, delta: float) -> void:
	if not _arrived:
		if _arrive_room != "" and not _look_around:
			_arrived = _room_key_at(character.global_position) == _arrive_room
		if not _arrived:
			_arrived = _loco.reached(character, _point)
		if _arrived:
			if _look_around:
				_begin_coverage(character)
			else:
				_resolved = true
	if not _arrived:
		_loco.move_to(character, _point)
	elif _look_around:
		_cover_room_step(character, delta)  # Look around until the room is covered by sight.
		return
	_aim_move(character)
	if _params.get("fire_at_will", false):
		_fire_at_will(character)


## Start covering the room on arrival: lock the room, sample it into points to be seen, and begin the
## time budget. `_room_key_at` may be "" (an explore point in no room); then the sample is empty and
## coverage resolves at once (a single look), which is the graceful fallback.
func _begin_coverage(character) -> void:
	_cover_room = _room_key_at(character.global_position)
	_cover_points = _sample_room(_cover_room)
	_cover_unseen = _cover_points.duplicate()
	_cover_target = character.global_position
	_cover_budget = search_coverage_budget
	_look_angle = character.facing.angle()


## One tick of room coverage: drop every sample point now in sight, then — if the room isn't covered
## yet and the budget holds — turn the gaze toward the nearest unseen point and, when it is far or its
## line is blocked (behind furniture), walk toward it so a new vantage reveals it. Resolves (forcing a
## re-decision) once `search_coverage_target` of the points are seen or the budget runs out.
func _cover_room_step(character, delta: float) -> void:
	for p in _perception.visible_points(character, _cover_unseen):
		_cover_unseen.erase(p)
	_cover_budget -= delta
	if _cover_unseen.size() <= floori(_cover_points.size() * (1.0 - search_coverage_target)) or _cover_budget <= 0.0:
		_look_around = false
		_resolved = true
		return
	var self_pos: Vector2 = character.global_position
	var target: Vector2 = _nearest(self_pos, _cover_unseen)
	_cover_target = target
	var desired := (target - self_pos).angle()
	_look_angle = rotate_toward(_look_angle, desired, search_look_rate * delta)
	character.aim_point = self_pos + Vector2.from_angle(_look_angle) * 100.0
	if self_pos.distance_to(target) > search_coverage_approach or not _perception.has_line_to(character, null, target):
		_loco.move_to(character, _loco.reachable(target))  # Relocate to see a far / occluded part of the room.
	else:
		character.move_input = Vector2.ZERO  # Close with a clear line: stand and turn, the cone will catch it.


## Where a moving NPC looks: its target, the nearest known threat, the destination, or (default) the
## direction of travel so its view cone sweeps ahead.
func _aim_move(character) -> void:
	match _params.get("aim", &"travel"):
		&"target":
			if _engage_id != 0:
				character.aim_point = _engage_pos
				return
		&"threat":
			if not _hostiles.is_empty():
				character.aim_point = _hostiles[0]["pos"]
				return
		&"point":
			character.aim_point = _point
			return
	if character.move_input != Vector2.ZERO:
		character.aim_point = character.global_position + character.move_input * 100.0


## Shoot the engaged (else nearest) known hostile when it is in range with a clear line, once the
## facing has settled on it; aims at it meanwhile. No-op without a loaded gun (or mid-reload).
func _fire_at_will(character) -> void:
	var gun: int = character.gun_slot()
	if gun < 0 or character.ammo(gun) == 0 or character.is_reloading():
		return
	var target: Dictionary = {}
	for c in _hostiles:
		if c["id"] == _engage_id or target.is_empty():
			target = c
	if target.is_empty():
		return
	var pos: Vector2 = target["pos"]
	if character.global_position.distance_to(pos) > shoot_range:
		return
	if not _perception.has_line_to(character, target["node"], pos):
		return
	character.aim_point = pos
	if _fire_timer <= 0.0 and absf(character.facing.angle_to(pos - character.global_position)) <= AIM_TOLERANCE:
		_shoot(character)


## Engage: walk to the chosen spot (shooting on the way when a line opens), then fight from it —
## peek-and-cover, or an ambush that holds the covered spot and fires the moment a line opens. A
## territorial NPC fighting a contact outside the house stays inside (`_hold_ground`).
func _apply_engage(character, delta: float) -> void:
	if _engage_id == 0:
		_apply_hold(character)
		return
	character.aim_point = _engage_pos  # Aim at where we last saw them, not their true position.
	_hold_ground = _params.get("confine_inside", false) and not _engage_inside
	if not _arrived:
		_arrived = _loco.reached(character, _point)
		if not _arrived:
			_loco.move_to(character, _point)
			_fire_at_will(character)
			return
		_tactic_timer = tactic_interval  # In position: the tactic gets its full run from here.
		_perception.note_engaged()
	if _params.get("style", &"peek_cover") == &"ambush":
		character.move_input = Vector2.ZERO
		if character.global_position.distance_to(_engage_pos) <= shoot_range \
				and _perception.has_line_to(character, _engage_node, _engage_pos) and _fire_timer <= 0.0:
			_shoot(character)
		return
	_apply_peek_cover(character, delta)


## Peek-and-cover shooting: in the PEEK phase, move to a spot with a clear shot and fire, then duck;
## in the COVER phase, hold behind a shielding object for `cover_time` before peeking again. The
## fire/cover destination is committed for `reposition_interval` rather than re-picked every frame,
## so the NPC steers smoothly instead of vibrating between near-equal candidates.
func _apply_peek_cover(character, delta: float) -> void:
	var dist: float = character.global_position.distance_to(_engage_pos)
	_combat_dest_timer -= delta
	if _combat_phase == "cover":
		_cover_timer -= delta
		if _combat_dest_timer <= 0.0:
			_combat_dest = _choose_combat_dest(character, "cover")
			_combat_dest_timer = reposition_interval
		_loco.move_to(character, _combat_dest)
		_reload_if_dry(character)
		if _cover_timer <= 0.0:
			_combat_phase = "peek"
			_combat_dest_timer = 0.0  # Re-pick a firing spot immediately on peeking out.
		return
	# PEEK: take the shot if a clear line to the known position is in range, else reposition to get one.
	if dist <= shoot_range and _perception.has_line_to(character, _engage_node, _engage_pos):
		character.move_input = Vector2.ZERO
		if _fire_timer <= 0.0:
			_shoot(character)
			# A gun whose barrel is against something (stepping back to clear it) has not shot yet: keep
			# peeking until it does, rather than ducking without having fired.
			if _back_off_timer <= 0.0:
				_combat_phase = "cover"
				_cover_timer = cover_time
				_combat_dest_timer = 0.0  # Pick a cover spot immediately after shooting.
		return
	if _combat_dest_timer <= 0.0:
		_combat_dest = _choose_combat_dest(character, "peek")
		_combat_dest_timer = reposition_interval
	_loco.move_to(character, _combat_dest)


## The committed destination for the current phase: the nearest spot with a clear shot (peek) or the
## nearest shielded spot (cover); falls back to closing on the contact (peek) or holding (cover) when
## no suitable spot exists this sample. While holding ground, spots are restricted to inside the house
## and the peek fallback holds position instead of advancing out.
func _choose_combat_dest(character, phase: String) -> Vector2:
	var spots: Dictionary = _perception.combat_spots(character, _engage_node, _engage_pos, combat_ring_radius, combat_ring_count)
	var fire: Array = spots["fire"]
	var cover: Array = spots["cover"]
	if _hold_ground:
		fire = fire.filter(func(p): return _inside_house(p))
		cover = cover.filter(func(p): return _inside_house(p))
	if phase == "cover":
		return cover[0] if not cover.is_empty() else character.global_position
	if not fire.is_empty():
		return fire[0]
	return character.global_position if _hold_ground else _engage_pos


## Melee: close to punch range and swing on the fire cooldown (no cover cycle for fists). While
## holding ground it won't chase a contact out of the house — it only swings if one is already in reach.
func _apply_melee(character) -> void:
	if _engage_id == 0:
		_apply_hold(character)
		return
	character.aim_point = _engage_pos
	_hold_ground = _params.get("confine_inside", false) and not _engage_inside
	if character.global_position.distance_to(_engage_pos) > punch_range:
		if not _hold_ground:
			_loco.move_to(character, _engage_pos)
		else:
			character.move_input = Vector2.ZERO
		return
	character.move_input = Vector2.ZERO
	if _fire_timer <= 0.0:
		_punch(character)


## Equip the character's gun and fire it, refreshing the combat engagement so an active fight stays
## committed; true when a round left the barrel. Nothing here is specific to a gun:
##   - at a run or mid-reload it holds fire and keeps the cooldown for when that stops;
##   - dry, a click is not a shot, so it neither commits the fight nor needs a hand free to reload — it
##     re-decides (the empty gun is in the snapshot now), at most once per cooldown;
##   - with the barrel against a wall or object (`weapon_blocked()`) it cannot fire, so it steps back until
##     it can, keeping the cooldown;
##   - an automatic gun's pull is a burst (`fire_burst` rounds, `_continue_burst`), the rest at the gun's own rate.
func _shoot(character) -> bool:
	if character.is_running() or character.is_reloading():
		return false
	var gun: int = character.gun_slot()
	if gun < 0:
		return false
	if character.ammo(gun) == 0:
		_fire_timer = fire_cooldown
		_resolved = true
		return false
	character.select_slot(gun)
	if character.weapon_blocked():
		_back_off_timer = back_off_time
		return false
	if not character.shoot():
		return false
	_perception.note_engaged()
	_fire_timer = fire_cooldown
	_burst_left = maxi(fire_burst - 1, 0) if character.is_automatic() else 0
	return true


## Equip the fists and throw a punch, refreshing the combat engagement.
func _punch(character) -> void:
	_perception.note_engaged()
	_fire_timer = fire_cooldown
	character.select_slot(FISTS_SLOT)
	character.melee()


## Keep the trigger down for the rest of an automatic gun's burst: one more round each time the gun's own fire
## rate allows, until the burst is spent or something stops it (a run, a reload, a swap, a wall, running dry).
func _continue_burst(character) -> void:
	if _burst_left <= 0:
		return
	if not character.is_automatic() or character.is_running() or character.is_reloading() \
			or character.weapon_blocked() or character.ammo() <= 0:
		_burst_left = 0
		return
	if character.shoot():
		_burst_left -= 1


## Step back from whatever the gun's barrel is against (`_shoot` set the timer): away from where it points,
## walking, until the barrel is clear or the time is up. Applied after the primitive has steered, so it wins.
func _apply_back_off(character, delta: float) -> void:
	if _back_off_timer <= 0.0:
		return
	_back_off_timer -= delta
	character.move_input = -character.facing
	character.run_input = false


## Interact: walk to the chosen object facing it (or a known hostile, to keep eyes on them); once its
## action is in reach, face it, run it and hold the interaction. Ends (and re-decides) if the object is
## gone or the action can't start.
func _apply_interact(character) -> void:
	if _target_obj == null or not is_instance_valid(_target_obj):
		_primitive = &"hold"
		_resolved = true
		character.move_input = Vector2.ZERO
		return
	if not _interaction_in_reach(character):
		character.aim_point = _hostiles[0]["pos"] if not _hostiles.is_empty() else _target_obj.global_position
		_loco.move_to(character, _target_obj.global_position)
		return
	character.move_input = Vector2.ZERO
	character.aim_point = _target_obj.global_position  # face the object to perform the interaction
	if not _act_armed:
		_act_armed = true  # Let facing settle before acting.
		return
	if character.interact_with(_target_obj, _interact_id):
		_in_interaction = true
		_interaction_timer = interaction_dwell
	else:
		_primitive = &"hold"
		_resolved = true


## Hold: stand still and watch the nearest known hostile, if any. An empty gun is reloaded meanwhile,
## so a steady NPC (no decision to be had) isn't left unarmed.
func _apply_hold(character) -> void:
	character.move_input = Vector2.ZERO
	if not _hostiles.is_empty():
		character.aim_point = _hostiles[0]["pos"]
	_reload_if_dry(character)


## Reload: stand and swap magazines, watching the nearest known hostile; when the reload ends (or can't
## start) the task is resolved and the NPC re-decides. A reload refused while the previous leaf's run is
## still winding down is retried the next tick.
func _apply_reload(character) -> void:
	character.move_input = Vector2.ZERO
	if not _hostiles.is_empty():
		character.aim_point = _hostiles[0]["pos"]
	if character.is_reloading():
		_reload_started = true
		return
	if not _reload_started:
		var gun: int = character.gun_slot()
		if gun >= 0:
			character.select_slot(gun)
		character.reload()
		if character.is_reloading():
			_reload_started = true
			return
		if character.is_running():
			return
	_primitive = &"hold"
	_resolved = true


## Reflex: swap in a fresh magazine when the gun is empty and one is carried (`auto_reload`). It
## equips the gun first, since a reload works on the held item.
func _reload_if_dry(character) -> void:
	var gun: int = character.gun_slot()
	if not auto_reload or gun < 0 or character.is_reloading() or character.ammo(gun) != 0 or not character.can_reload(gun):
		return
	character.select_slot(gun)
	character.reload()


# --- Helpers ---------------------------------------------------------------------------------

## Whether a world point lies within any of the house's rooms (the "inside the house" test).
func _inside_house(p: Vector2) -> bool:
	return _room_key_at(p) != ""


## The key of the room containing world point `p`, or "" when `p` is in no room.
func _room_key_at(p: Vector2) -> String:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return str(room["key"])
	return ""


## Grid-sample room `room_key` into the points a searcher must SEE to have covered it: the rect inset
## by `search_coverage_margin` (to keep points off the walls), stepped by `search_coverage_spacing`,
## dropping any point not on the navmesh — i.e. inside a carved furniture footprint — so search points
## sit on open floor, not on furniture (which also keeps unseeable points out of the coverage set).
## Deterministic (no RNG). Empty when the room is unknown (coverage then resolves at once).
func _sample_room(room_key: String) -> Array:
	var points: Array = []
	for room in rooms:
		if str(room["key"]) != room_key:
			continue
		var r: Rect2 = (room["rect"] as Rect2).grow(-search_coverage_margin)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			r = room["rect"]  # Too small to inset; use the whole rect.
		var step: float = maxf(search_coverage_spacing, 8.0)
		var x: float = r.position.x + step * 0.5
		while x < r.end.x:
			var y: float = r.position.y + step * 0.5
			while y < r.end.y:
				var p := Vector2(x, y)
				if _loco.on_navmesh(p):  # Skip furniture holes / off-walkable so points land on open floor.
					points.append(p)
				y += step
			x += step
		break
	return points


## The point in `points` nearest `from` (world space); `from` when the list is empty.
func _nearest(from: Vector2, points: Array) -> Vector2:
	var best: Vector2 = from
	var best_d := INF
	for p in points:
		var d: float = from.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


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
