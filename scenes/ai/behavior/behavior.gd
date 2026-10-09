extends Node

## AI BEHAVIOUR sub-domain. Runs the LEAF the decision planner chose — one behaviour PRIMITIVE with its
## params — as concrete movement and actions on the character, and holds the System-Two state Von (a
## stateless single-shot ranker) lacks: the engaged contact, the peek-and-cover combat cycle, the
## interaction in progress, and the COMMITMENT that keeps a choice running until it completes or a
## re-decision is due. The primitives:
##   move     — go to `point` (or until entering `arrive_room`), aiming along the way (`aim`: travel /
##              target / threat / point), shooting a known hostile on a clear line when `fire_at_will`; a
##              `look_around` search move pauses on arrival and sweeps its gaze back and forth to scan the room.
##   engage   — go to `point`, then fight `target_id` from there: `peek_cover` (step out, shoot, duck)
##              or `ambush` (hold the covered spot, fire the moment a line opens).
##   melee    — close on `target_id` and punch.
##   interact — walk to `object`, run its interaction `id`, hold it for `interaction_dwell`.
##   hold     — stay and watch.
## It never chooses WHAT to do — the planner does — and applies no policy beyond the params it is
## handed (`confine_inside` keeps a territorial NPC from chasing out of the house). It owns a
## `Locomotion` child for all pathing, reads the world only through the PERCEPTION sub-domain (known
## contacts, combat geometry, engagement memory) and drives the character only through its public
## controller contract (`move_input` / `aim_point`, `select_slot`, `shoot`, `melee`, `interact_with`,
## `end_interaction`). All tunables are set by the controller before `setup()`.

const Locomotion := preload("res://scenes/ai/behavior/locomotion.gd")
## Inventory slots of the combat items (ItemRegistry ids).
const PISTOL_SLOT := 3
const FISTS_SLOT := 2
## Facing error (radians) within which a shot is taken — aim settles a frame after it is set.
const AIM_TOLERANCE := 0.15
## How near (radians) the gaze must be to a look-around swing's goal to count as reached.
const LOOK_REACHED := 0.05

# --- Config fields the controller copies from its exports before setup(). ---
var interaction_dwell: float = 3.0
var max_commit_time: float = 6.0
var search_dwell: float = 2.5     ## Seconds to pause and look around after reaching a search/explore room.
var search_look_arc: float = 1.2  ## Base half-arc (rad) the look-around gaze swings to either side of the arrival facing.
var search_look_rate: float = 2.5 ## Base gaze turn speed (rad/s) during a look-around swing.
var search_look_pause: float = 0.5 ## Base seconds the gaze dwells at each swing's extreme before reversing.
var search_look_jitter: float = 0.15 ## Random angle (rad, ±) added to each swing's goal so it isn't perfectly symmetric.
var search_look_variance: float = 0.5 ## Fraction (0..1) the arc/rate/pause are randomized per swing (0 = uniform metronome).
var tactic_interval: float = 3.0
var shoot_range: float = 500.0
var punch_range: float = 48.0
var combat_ring_radius: float = 80.0
var combat_ring_count: int = 12
var cover_time: float = 1.2
var fire_cooldown: float = 0.5
var reposition_interval: float = 0.5
# Locomotion config (forwarded to the Locomotion child in setup()).
var arrive_dist: float = 10.0

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
var _look_around := false         ## A search/explore move that pauses to look around on arrival (vs resolving at once).
var _look_timer := 0.0            ## Seconds left in the look-around pause.
var _look_base := 0.0             ## Facing angle (rad) the look-around sweep pans around.
var _look_angle := 0.0            ## Current gaze offset (rad) from `_look_base` during the look-around.
var _look_goal := 0.0             ## The current swing's goal offset (rad) from `_look_base`.
var _look_speed := 0.0            ## This swing's gaze turn speed (rad/s), randomized per swing.
var _look_hold := 0.0             ## Seconds left dwelling at the current swing's extreme (>0 = holding, not turning).
var _engage_id := 0               ## Instance id of the contact being fought (0 = none).
var _engage_node: Node2D          ## That contact's body (excluded from line-of-fire rays).
var _engage_pos := Vector2.ZERO   ## That contact's last-KNOWN position (from memory).
var _engage_inside := false       ## Whether that contact was last seen inside the house.
var _hold_ground := false         ## Combat: stay inside the house (territorial vs. an outsider).
var _combat_phase := "peek"       ## Peek-and-cover phase: "peek" (seek a shot) or "cover" (duck).
var _cover_timer := 0.0           ## Seconds left ducking behind cover before peeking again.
var _fire_timer := 0.0            ## Seconds left before the next shot/punch may be thrown.
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
			return "reached it" if _arrived else "en route"
		&"engage":
			if not _arrived:
				return "moving into position"
			if _params.get("style", &"peek_cover") == &"ambush":
				return "in ambush, waiting for a shot"
			return "in position, %s" % ("ducking behind cover" if _combat_phase == "cover" else "looking for a shot")
		&"melee":
			return "closing in to punch"
		&"interact":
			return "using it" if _in_interaction else "walking to it"
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
	_look_timer = 0.0
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
			if _look_around and _arrived and _look_timer > 0.0:
				return false  # Hold through the look-around pause; the move itself ends it when it elapses.
			return _commit_timer <= 0.0
		&"interact":
			return _commit_timer <= 0.0
	return decide_timer_elapsed


# --- Running the primitive --------------------------------------------------------------------

## Carry out the running primitive this tick.
func apply(character, delta: float) -> void:
	_fire_timer -= delta
	match _primitive:
		&"move":
			_apply_move(character, delta)
		&"engage":
			_apply_engage(character, delta)
		&"melee":
			_apply_melee(character)
		&"interact":
			_apply_interact(character)
		_:
			_apply_hold(character)


## Move: walk to the destination (or into the destination room), aiming as the leaf asks, and — when
## `fire_at_will` — shoot a known hostile the moment there is a clear line. A `look_around` move (search /
## explore) walks all the way to the interior point and, on arrival, pauses `search_dwell` seconds sweeping
## its view before flagging the task resolved; any other move flags resolved the moment it arrives.
func _apply_move(character, delta: float) -> void:
	if not _arrived:
		if _arrive_room != "" and not _look_around:
			_arrived = _room_key_at(character.global_position) == _arrive_room
		if not _arrived:
			_arrived = _loco.reached(character, _point)
		if _arrived:
			if _look_around:
				_look_timer = search_dwell  # Pause and scan the room before deciding where to go next.
				_look_base = character.facing.angle()
				_look_angle = 0.0
				_look_hold = 0.0
				_next_look_swing(1.0)  # Kick off the first swing to one side.
			else:
				_resolved = true
	if not _arrived:
		_loco.move_to(character, _point)
	else:
		character.move_input = Vector2.ZERO
		if _look_around:
			_look_timer -= delta
			_scan_around(character, delta)
			if _look_timer <= 0.0:
				_look_around = false
				_resolved = true
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


## During a search/explore pause, sweep the aim — and so the view cone — back and forth around where
## the NPC ended up facing, so it looks around the room instead of re-deciding the instant it arrives.
## Each swing eases the gaze to one extreme, dwells there a beat, then reverses; the arc, turn speed
## and dwell are randomized per swing (by `search_look_variance`) so it reads as scanning, not a wiper.
func _scan_around(character, delta: float) -> void:
	if _look_hold > 0.0:
		_look_hold -= delta  # Dwelling at an extreme; reverse once the beat elapses.
		if _look_hold <= 0.0:
			_next_look_swing(-signf(_look_goal))
	else:
		_look_angle = move_toward(_look_angle, _look_goal, _look_speed * delta)
		if absf(_look_angle - _look_goal) <= LOOK_REACHED:
			_look_hold = search_look_pause * _look_rand_factor()  # Reached this side; pause before reversing.
	character.aim_point = character.global_position + Vector2.from_angle(_look_base + _look_angle) * 100.0


## Begin the next look-around swing toward side `dir` (+1 / −1): pick its goal offset, randomized arc
## and jitter, and a randomized turn speed. Randomness here is cosmetic gaze variation, so it uses the
## global RNG and is deliberately NOT tied to the run's seeded world-gen RNG.
func _next_look_swing(dir: float) -> void:
	var jitter: float = randf_range(-search_look_jitter, search_look_jitter)
	_look_goal = dir * search_look_arc * _look_rand_factor() + jitter
	_look_speed = search_look_rate * _look_rand_factor()


## A per-swing random multiplier `1 ± search_look_variance`, so variance 0 collapses to a uniform sweep.
func _look_rand_factor() -> float:
	return 1.0 + randf_range(-search_look_variance, search_look_variance)


## Shoot the engaged (else nearest) known hostile when it is in range with a clear line, once the
## facing has settled on it; aims at it meanwhile. No-op without the pistol.
func _fire_at_will(character) -> void:
	if not character.has_item(PISTOL_SLOT):
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
		_fire(character, PISTOL_SLOT)


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
			_fire(character, PISTOL_SLOT)
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
		if _cover_timer <= 0.0:
			_combat_phase = "peek"
			_combat_dest_timer = 0.0  # Re-pick a firing spot immediately on peeking out.
		return
	# PEEK: take the shot if a clear line to the known position is in range, else reposition to get one.
	if dist <= shoot_range and _perception.has_line_to(character, _engage_node, _engage_pos):
		character.move_input = Vector2.ZERO
		if _fire_timer <= 0.0:
			_fire(character, PISTOL_SLOT)
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
		_fire(character, FISTS_SLOT)


## Equip `slot` and throw one shot (pistol) or punch, refreshing the combat engagement so an active
## fight stays committed.
func _fire(character, slot: int) -> void:
	_perception.note_engaged()
	_fire_timer = fire_cooldown
	character.select_slot(slot)
	if slot == PISTOL_SLOT:
		character.shoot()
	else:
		character.melee()


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


## Hold: stand still and watch the nearest known hostile, if any.
func _apply_hold(character) -> void:
	character.move_input = Vector2.ZERO
	if not _hostiles.is_empty():
		character.aim_point = _hostiles[0]["pos"]


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
