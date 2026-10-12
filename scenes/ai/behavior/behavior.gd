extends Node

## AI BEHAVIOUR sub-domain. Runs the LEAF the decision planner chose — one behaviour PRIMITIVE with its
## params — as concrete movement and actions on the character, and holds the System-Two state Von (a
## stateless single-shot ranker) lacks: the engaged contact, the peek-and-cover combat cycle, the
## interaction in progress, and the COMMITMENT that keeps a choice running until it completes or a
## re-decision is due. The primitives:
##   move     — go to `point` (or until entering `arrive_room`), aiming along the way (`aim`: travel /
##              target / threat / point), shooting a known hostile on a clear line when `fire_at_will`; a
##              `look_around` search move covers the room by sight (`search_coverage.gd`): it turns and relocates
##              until it has seen all of it.
##   engage   — go to `point`, then fight `target_id` from there: `peek_cover` (step out, shoot, duck)
##              or `ambush` (hold the covered spot, fire the moment a line opens).
##   melee    — close on `target_id` and punch.
##   interact — walk to `object`, run its interaction `id`, hold it for `interaction_dwell`.
##   reload   — stand and swap in a fresh magazine (`Character.reload()`), then re-decide.
##   entry    — go through doorway `opening` into room `into` as a team member or alone: stack, slice the pie,
##              cross without stopping, take a corner, clear the room (`entry.gd`).
##   hold     — stay and watch.
## It never chooses WHAT to do — the planner does — and applies no policy beyond the params it is
## handed (`confine_inside` keeps a territorial NPC from chasing out of the house). It owns a
## `Locomotion` child for all pathing, a `Combat` module (shots, punches, bursts, the peek-and-cover cycle) and a
## `SearchCoverage` module, reads the world only through the PERCEPTION sub-domain (known
## contacts, combat geometry, engagement memory) and drives the character only through its public
## controller contract (`move_input` / `aim_point`, `select_slot`, `shoot`, `melee`, `interact_with`,
## `end_interaction`). All tunables are set by the controller before `setup()`.

const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
const Combat := preload("res://scenes/ai/behavior/combat.gd")
const SearchCoverage := preload("res://scenes/ai/behavior/search_coverage.gd")
const Entry := preload("res://scenes/ai/behavior/entry.gd")

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
# Tactical entry (see entry.gd).
var entry_ready_timeout: float = 6.0
var entry_follow_gap: float = 0.3
var entry_pie_dwell: float = 0.35
var entry_corner_dwell: float = 0.6
var rear_security_time: float = 10.0
var entry_cover_time: float = 8.0
var entry_watch_dwell: float = 0.8
var entry_approach_time: float = 20.0
# The entry guard (E9): any walk into a room that is not cleared goes in by tactical entry (see `_entry_guard`).
var entry_guard: bool = true
var entry_guard_range: float = 300.0 ## Start the entry once the doorway is this near (px of walking).
var entry_guard_rearm: float = 6.0 ## Seconds a doorway whose entry was given up is left alone before the guard may start another.

## World-space room rects (`{ key, type, rect }`), set each tick by the controller from Main's inject; handed on to the
## Locomotion child, which answers the room queries.
var rooms: Array = []:
	set(value):
		rooms = value
		if _loco != null:
			_loco.rooms = value

var _perception: Node             ## The perception sub-domain (contacts, combat geometry, engagement memory).
var _loco: Node                   ## The Locomotion child (pathing, rooms).
var _coverage: RefCounted         ## Room coverage by sight for a search move; see search_coverage.gd.
var _combat: RefCounted           ## Shots, punches, bursts and the peek-and-cover cycle; see combat.gd.
var _entry: RefCounted            ## A tactical entry through a doorway; see entry.gd.
var _entry_pending := false       ## An ENTER leaf was adopted and its entry starts on the next tick (it needs the character).
var _resume := {}                 ## The leaf an entry detour paused (see `_begin_detour`); {} when the entry is the NPC's own order.
var _guard_clock := 0.0           ## Seconds the guard has been watching (sim time), for the re-arm of a given-up doorway.
var _guard_off := {}              ## Doorway id -> `_guard_clock` before which the guard leaves it alone.
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
	_loco.rooms = rooms
	add_child(_loco)
	_coverage = SearchCoverage.new()
	_coverage.setup(_loco, perception)
	_combat = Combat.new()
	_combat.setup(_loco, perception)
	_combat.dry.connect(_on_dry)
	_entry = Entry.new()
	_entry.setup(_loco, perception, _coverage)


## Push the current config into the Locomotion child and the coverage and combat modules. The behaviour's own
## fields are read live, so only what those hold needs pushing. Idempotent, so the controller may call it each
## decision to pick up an export retuned at runtime.
func apply_config() -> void:
	_loco.arrive_dist = arrive_dist
	_coverage.spacing = search_coverage_spacing
	_coverage.target_fraction = search_coverage_target
	_coverage.budget_max = search_coverage_budget
	_coverage.approach = search_coverage_approach
	_coverage.margin = search_coverage_margin
	_coverage.look_rate = search_look_rate
	_combat.shoot_range = shoot_range
	_combat.punch_range = punch_range
	_combat.ring_radius = combat_ring_radius
	_combat.ring_count = combat_ring_count
	_combat.cover_time = cover_time
	_combat.fire_cooldown = fire_cooldown
	_combat.fire_burst = fire_burst
	_combat.back_off_time = back_off_time
	_combat.reposition_interval = reposition_interval
	_combat.auto_reload = auto_reload
	_entry.ready_timeout = entry_ready_timeout
	_entry.follow_gap = entry_follow_gap
	_entry.pie_dwell = entry_pie_dwell
	_entry.corner_dwell = entry_corner_dwell
	_entry.rear_time = rear_security_time
	_entry.cover_time = entry_cover_time
	_entry.watch_dwell = entry_watch_dwell
	_entry.approach_time = entry_approach_time
	_entry.look_rate = search_look_rate


# --- Read-only views -------------------------------------------------------------------------

## Read-only: the decision path the NPC is carrying out, as ids ("combat/t_12/flank/side_left").
func current_act() -> String:
	return "/".join(_path) if not _path.is_empty() else "hold"


## Read-only: the decision path as labels, joined ("SEARCH - ENTER - the doorway into the kitchen").
func path_label() -> String:
	return " - ".join(_labels)


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
		&"entry":
			return _entry_pending or _entry.phase not in ["", "done"]
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


## How each phase of a tactical entry reads in the status line.
const ENTRY_PROGRESS := {
	"approach": "heading for the door", "stack": "stacked at the door", "pie": "slicing the pie",
	"cross": "going in", "corner": "taking a corner", "clear": "clearing the room",
	"cover": "covering the doors on", "rear": "holding the door",
}


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
			return "in position, %s" % ("ducking behind cover" if _combat.phase == "cover" else "looking for a shot")
		&"melee":
			return "running in to punch" if _running else "closing in to punch"
		&"interact":
			return "using it" if _in_interaction else "walking to it"
		&"reload":
			return "reloading"
		&"entry":
			return ENTRY_PROGRESS.get(_entry.phase, "heading for the door")
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
		"combat_phase": _combat.phase,
		"hold_ground": _hold_ground,
		"hostiles_known": _hostiles.size(),
		"in_interaction": _in_interaction,
		"timers": {
			"commit": _commit_timer,
			"tactic": _tactic_timer,
			"interaction": _interaction_timer,
			"fire": _combat.fire_timer,
			"cover": _combat.cover_timer,
			"combat_dest": _combat.dest_timer,
		},
		"entry": _json_safe(debug_entry()),
		"loco": _loco.debug_state(),
	}


## Read-only: the running tactical entry (doorway, slot, side, phase, what the pie saw, the corner), or {} when the
## NPC isn't entering. See entry.gd `debug()`.
func debug_entry() -> Dictionary:
	return _entry.debug() if _primitive == &"entry" else {}


## How far (px of walking) the entry debug view looks ahead along the walk for the next uncleared doorway.
const GUARD_PREVIEW_RANGE := 2000.0


## Read-only, for the entry debug overlays: the running entry as world-space data (entry.gd `debug_view`, under `entry`;
## {} when none) and the entry guard's picture under `guard`: whether a detour is running and the order it paused
## (`resume_point`, `resume_label`), the doorways it is leaving alone (`rearm`: `{ opening, left }`), its `range`, the
## next uncleared doorway on the current walk (`ahead`: `{ opening, into, dist, pos }`, or {}), and the rects of the rooms
## this NPC regards as cleared (`cleared_rooms`). Computed only when asked; nothing reads it back.
func debug_entry_view(character) -> Dictionary:
	var guard := {
		"detour": _primitive == &"entry" and not _resume.is_empty(),
		"resume_point": _resume.get("point", Vector2.INF),
		"resume_label": " - ".join(_resume.get("labels", [])),
		"rearm": [],
		"range": entry_guard_range,
		"ahead": {},
		"cleared_rooms": [],
	}
	for id in _guard_off:
		var left: float = float(_guard_off[id]) - _guard_clock
		if left > 0.0:
			guard["rearm"].append({ "opening": id, "left": left })
	if _perception != null:
		for r in rooms:
			if _perception.is_cleared(str(r["key"])):
				guard["cleared_rooms"].append(r["rect"])
		var walk: Dictionary = _loco.path_ahead() if _primitive != &"entry" else {}
		if not walk.is_empty():
			var gate: Dictionary = _perception.threshold_ahead(character, walk["path"], walk["index"], GUARD_PREVIEW_RANGE)
			if not gate.is_empty():
				var geo: Dictionary = _perception.entry_geometry(character, gate["opening"], gate["into"])
				if not geo.is_empty():
					gate["pos"] = geo["pos"]
					guard["ahead"] = gate
	return { "entry": _entry.debug_view(character) if _primitive == &"entry" else {}, "guard": guard }


## Whether the NPC is committed to crossing a doorway: the controller holds every re-decision until it is through.
func committed() -> bool:
	return _primitive == &"entry" and _entry.committed()


## The entry steps to radio since the last call (`{ step, cleared_room?, covering? }`), with the doorway, slot and side they are
## about; the controller posts them as callouts.
func take_entry_calls() -> Array:
	var out: Array = []
	for c in _entry.take_calls():
		c.merge({ "opening": _entry.opening, "slot": _entry.slot, "side": _entry.side })
		out.append(c)
	return out


## Read-only: the running search-coverage state, for the search debug overlay. `active` is true only
## while a `look_around` move is actually covering a room (arrived, not yet resolved); `points` are all
## the room's sample points, `unseen` the ones still to be seen, `target` the one being looked at now.
func debug_coverage() -> Dictionary:
	var out: Dictionary = _coverage.debug()
	out["active"] = (_primitive == &"move" and _look_around and _arrived and not _resolved) \
		or (_primitive == &"entry" and _entry.phase == "clear")
	return out


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
		"combat_phase": _combat.phase if fighting else "",
		"cover_timer": _combat.cover_timer,
		"cover_time": cover_time,
		"fire_timer": _combat.fire_timer,
		"fire_cooldown": fire_cooldown,
		"combat_dest": _combat.dest if _primitive == &"engage" and _arrived and _combat.dest != Vector2.ZERO else null,
		"aim_point": character.aim_point if character != null else Vector2.ZERO,
		"fire_at_will": bool(_params.get("fire_at_will", false)),
		"reloading": _reloading,
		"requested_point": _params["point"] if _params.has("point") else null,
		"point": (_point as Variant) if _params.has("point") else null,
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
	if committed() and _resume.is_empty():
		return  # Crossing a doorway on its own ENTER: a decision that was in flight waits (the entry ends in a re-decision).
	var carry := {}
	if _primitive == &"entry" and not _resume.is_empty() and (committed() or _guards(leaf)):
		# A detour's entry carries on: the new order replaces the one paused behind it (a fight that began, the same order
		# decided again), and the entry is not torn down at its stack or in its threshold.
		carry = { "primitive": _primitive, "params": _params, "pending": _entry_pending }
	else:
		_drop_detour()
		_entry_pending = false
		_entry.abandon()  # A new choice ends any entry in progress (the stack is told).
	_adopt(leaf)
	if not carry.is_empty():
		_stash_order()
		_primitive = carry["primitive"]
		_params = carry["params"]
		_entry_pending = carry["pending"]


## Whether the entry guard applies to `leaf`: a walk (move / engage / interact) that is not a retreat, while the NPC is not
## under fire.
func _guards(leaf: Dictionary) -> bool:
	return entry_guard and leaf.get("primitive", &"hold") in [&"move", &"engage", &"interact"] \
		and bool(leaf.get("params", {}).get("entry_guard", true)) and not _perception.under_fire()


## Take `leaf` as the running order.
func _adopt(leaf: Dictionary) -> void:
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
	_coverage.reset()           # Room sample points are built on arrival, once we know which room we're in.
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
			_combat.begin_fight()
			_tactic_timer = tactic_interval
			_perception.note_engaged()  # Commit to the fight (refreshed by firing).
		&"interact":
			_target_obj = _params.get("object")
			_interact_id = _params.get("id", "")
		&"reload":
			_reload_started = false
		&"entry":
			_entry_pending = true


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
	_drop_detour()
	_entry.abandon()  # No decision to be had: an entry in progress is given up (the stack is told).
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
		&"entry":
			return false  # It ends itself: the room clear, or the entry given up.
	return decide_timer_elapsed


# --- Running the primitive --------------------------------------------------------------------

## Carry out the running primitive this tick.
func apply(character, delta: float) -> void:
	_combat.tick(delta)
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
		&"entry":
			_apply_entry(character, delta)
		_:
			_apply_hold(character)
	_guard_clock += delta
	_entry_guard(character)
	_combat.continue_burst(character)
	character.run_input = _should_run(character)
	_combat.apply_back_off(character, delta)
	_apply_posture(character, delta)
	_running = character.is_running()
	_posture = character.posture()
	_reloading = character.is_reloading()


## The gun ran dry mid-fight: the task is resolved, so the controller re-decides (the empty gun is in the snapshot now).
func _on_dry() -> void:
	_resolved = true


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
## peek, room search, interaction, hold or tactical entry — a running character cannot shoot, so an entrant
## walks with its gun up from the moment it heads for the door), when the leaf asks for it (`params.run`) or the NPC is under
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
## and relocating until it has seen (near-)every sampled point (see `search_coverage.gd`) — before flagging
## the task resolved; any other move flags resolved the moment it arrives.
func _apply_move(character, delta: float) -> void:
	if not _arrived:
		if _arrive_room != "" and not _look_around:
			_arrived = _loco.room_key_at(character.global_position) == _arrive_room
		if not _arrived:
			_arrived = _loco.reached(character, _point)
		if _arrived:
			if _look_around:
				_coverage.begin(character)
			else:
				_resolved = true
	if not _arrived:
		_loco.move_to(character, _point)
	elif _look_around:
		if _coverage.step(character, delta):  # Look around until the room is covered by sight.
			_look_around = false
			_resolved = true
			var covered: String = _loco.room_key_at(character.global_position)
			if covered != "":
				_perception.mark_cleared(covered)  # Seen all of it: cleared, as by an entry.
		return
	_aim_move(character)
	if _params.get("fire_at_will", false):
		_fire_at_will(character)


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


## Shoot the engaged (else nearest) known hostile when `Combat` finds it in range on a clear line.
func _fire_at_will(character) -> void:
	var target: Dictionary = {}
	for c in _hostiles:
		if c["id"] == _engage_id or target.is_empty():
			target = c
	_combat.fire_at_will(character, target)


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
		_combat.ambush(character, _engage_node, _engage_pos)
		return
	_combat.peek_cover(character, delta, _engage_node, _engage_pos, _hold_ground)


## Melee: close to punch range and swing on the fire cooldown (no cover cycle for fists). While
## holding ground it won't chase a contact out of the house — it only swings if one is already in reach.
func _apply_melee(character) -> void:
	if _engage_id == 0:
		_apply_hold(character)
		return
	character.aim_point = _engage_pos
	_hold_ground = _params.get("confine_inside", false) and not _engage_inside
	_combat.melee(character, _engage_pos, _hold_ground)


## Entry: start the entry on the first tick (it needs the character), then run its phases; it shoots a known
## hostile on a clear line once it is crossing or in the room. Done (the room clear, or the entry given up) → re-decide.
func _apply_entry(character, delta: float) -> void:
	if _entry_pending:
		_entry_pending = false
		if not _entry.begin(character, _params):
			_finish_entry()
			return
	if _entry.step(character, delta):
		_finish_entry()
		return
	if _entry.fires_at_will():
		_fire_at_will(character)


## The entry is over, or could not start. As the NPC's own order (ENTER) it resolves and the NPC re-decides. As a detour
## (`_begin_detour`) it hands the walk back to the order it paused, which carries on from where the entry left the NPC; a
## doorway whose room is still not cleared (the entry did not get to the end) is left alone for `entry_guard_rearm` s.
func _finish_entry() -> void:
	if _resume.is_empty():
		_primitive = &"hold"
		_resolved = true
		return
	if not _perception.is_cleared(_entry.into):
		_guard_off[_entry.opening] = _guard_clock + entry_guard_rearm
	_resume_order()


## Hand the walk back to the order a detour paused.
func _resume_order() -> void:
	var r := _resume
	_resume = {}
	_primitive = r["primitive"]
	_params = r["params"]
	_path = r["path"]
	_labels = r["labels"]
	_point = r["point"]
	_arrived = r["arrived"]
	_look_around = r["look_around"]
	_arrive_room = r["arrive_room"]
	_act_armed = r["act_armed"]
	_commit_timer = max_commit_time  # The order's cap runs from here: the entry took the time it took.


## The entry guard (E9): a walk that is about to cross into a room that is not cleared goes in by tactical entry, whatever
## order it came from (a search or explore, a lead, a closing-in, the way to an object, the front entrance). It reads the walk
## the nav agent was just given rather than the leaf's destination, so a path through an intermediate room, a reposition in
## a fight and the way to a doorway itself are all covered. Exempt: a retreat (`entry_guard: false` on its node), an NPC under
## fire, an entry already running, and anything that is not walking.
func _entry_guard(character) -> void:
	if _primitive == &"entry":
		if not _resume.is_empty() and not _entry.committed() and _perception.under_fire():
			_cancel_detour()  # Shot at before it crossed: no time to stack. (Once crossing it finishes the crossing.)
		return
	if not entry_guard or _perception == null or not _perception.entry_enabled:
		return
	match _primitive:
		&"move":
			if _arrived:
				return  # Holding at the destination, or covering the room by sight.
		&"engage", &"interact":
			pass
		_:
			return
	if (character.move_input as Vector2).length() < 0.1 or not bool(_params.get("entry_guard", true)) or _perception.under_fire():
		return
	var walk: Dictionary = _loco.path_ahead()
	if walk.is_empty():
		return
	var gate: Dictionary = _perception.threshold_ahead(character, walk["path"], walk["index"], entry_guard_range)
	if gate.is_empty() or float(_guard_off.get(gate["opening"], -1.0)) > _guard_clock:
		return
	_begin_detour(gate)


## Pause the running order and go through doorway `gate` (`{ opening, into }`) by tactical entry first. The order is kept
## whole in `_resume` and comes back when the entry ends (`_finish_entry`). A new decision replaces it and lets the entry carry
## on (`set_leaf`), unless it is one the guard does not apply to: then the detour is dropped (`_drop_detour`).
func _begin_detour(gate: Dictionary) -> void:
	_stash_order()
	_primitive = &"entry"
	_params = { "opening": gate["opening"], "into": gate["into"] }
	_entry_pending = true


## Give a detour's entry up (the stack is told) and carry on with the paused order, which walks straight through.
func _cancel_detour() -> void:
	_guard_off[str(_params.get("opening", _entry.opening))] = _guard_clock + entry_guard_rearm
	_entry_pending = false
	_entry.abandon()
	_resume_order()


## Keep the running order whole in `_resume`, to come back when the entry ends.
func _stash_order() -> void:
	_resume = {
		"primitive": _primitive, "params": _params, "path": _path, "labels": _labels, "point": _point, "arrived": _arrived,
		"look_around": _look_around, "arrive_room": _arrive_room, "act_armed": _act_armed,
	}


## A new decision (or no decision to be had) ends a detour: the paused order is gone, and the doorway it was stacking at
## is left alone for `entry_guard_rearm` s so a fight that cut the entry short does not restart it every decision.
func _drop_detour() -> void:
	if _resume.is_empty():
		return
	_guard_off[str(_params.get("opening", _entry.opening))] = _guard_clock + entry_guard_rearm
	_resume = {}


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
	_combat.reload_if_dry(character)


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


# --- Helpers ---------------------------------------------------------------------------------

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
