extends RefCounted

## AI PERCEPTION sub-domain — GRENADES: the live grenades an NPC knows of, and the plan to get clear of the ones that
## threaten it (docs/grenades.md G15, G16). A grenade is known by **sight** (in the view cone with a clear line), by
## **hearing** it land (a `&"grenade"` bounce or rest within `hear_grenade`), by an ally's **callout** (`&"grenade"`,
## `&"frag_out"`, `&"bang_out"`) or because the NPC threw it (**own**). Each is `{ point, kind, fuse_left, fuse, radius, source }`
## (`known()`); it is forgotten when it goes off (`&"explosion"`) or is gone. Blind, the NPC sees no grenade it did not
## already know; deaf, the controller drops the events it would have heard (G15).
##
## The **evade plan** (`plan()`) is made for a known grenade the NPC is inside the danger zone of (`agent_throw.gd`): the
## nearest safe spot it can reach before the fuse runs out, replanned as the grenade moves (in flight, a bounce). It
## stands while the grenade lives, so the NPC holds its spot until the burst. `announcements()` hands the controller the
## grenade to radio once it has come down (a call names where it LANDED, which the plan of an ally that hears it needs).
## Holds no policy: the behaviour sub-domain carries the plan out.

const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")

## The group every live grenade is in (Items: `ThrownGrenade`: `kind`, `fuse_left()`, `danger_radius()`, `throw_stats()`, `thrower`).
const GROUP := &"live_grenades"
## How far (px) from a known grenade a bounce or rest event may be, to be that grenade coming down.
const LANDED_NEAR := 80.0
## How far (px) from a heard bounce the grenade it came from is looked for, and from an ally's call (a grenade rolls on a little).
const HEARD_NEAR := 40.0
const CALLED_NEAR := 150.0
## A plan is made again when its grenade has moved this far (px), and not more often than every `REPLAN_EVERY` s of game time (counted in
## physics frames, as the game's clock: the wall clock runs ahead of it in a fast headless run).
const REPLAN_DIST := 48.0
const REPLAN_EVERY := 0.15
## A grenade that came to rest this far (px) from where it was first called is called again, so the allies plan from the real spot.
const RECALL_DIST := 30.0
## The callout statuses that name a live grenade, and the kind each means (`&""`: the callout names it).
const CALL_KINDS := { &"grenade": &"", &"frag_out": &"frag", &"bang_out": &"stun" }

var enabled: bool = true               ## Whether the NPC reacts to grenades at all (`grenades_enabled`).
var hear_grenade: float = 300.0        ## How far (px) a grenade coming down is heard.
var throw: AgentThrow                  ## The danger-zone and escape geometry.

var _known := {}   ## Grenade node instance id -> { node, kind, radius, point, source, landed }.
var _plans := {}   ## Grenade node instance id -> { id, point, kind, radius, spot, crouch, at (the physics frame it was made in) }.
var _told := {}    ## Grenade node instance id -> { point, rested }: where it was last radioed, and whether that was after it came to rest.


## Capture the grenade geometry (the perception's `AgentThrow`) that judges every zone and line. Called once by `AgentPerception`.
func setup(geometry: AgentThrow) -> void:
	throw = geometry


# --- Knowing grenades ----------------------------------------------------------------------------------------

## The SEE pass, every tick: the NPC's own grenades (always known) and the live ones in its view cone with a clear line
## (`vision` is the sight sense), their points following them; `blind` sees none that it did not know. Gone ones are forgotten.
func observe(character, vision: RefCounted, space, exclude: Array, blind: bool) -> void:
	_forget_gone()
	if not enabled:
		return
	var tree: SceneTree = character.get_tree()
	if tree.get_node_count_in_group(GROUP) == 0:
		return
	var self_pos: Vector2 = character.global_position
	var facing: Vector2 = character.facing
	for node: Node2D in tree.get_nodes_in_group(GROUP):
		if node.get("thrower") == character:
			_note_own(character, node)
		elif not blind and vision.can_see_node(node, self_pos, facing, space, exclude):
			_note(node, node.global_position, &"seen", false)


## The NPC's own grenade, always known: it knows where it threw it. Until it has come down (a bounce marks it `landed`) its spot is
## where it was aimed (no further than a throw reaches), not the hand it just left, so the zone it is in is the one the burst will have;
## after that, wherever it lies.
func _note_own(character, node: Node2D) -> void:
	var rec: Dictionary = _known.get(node.get_instance_id(), {})
	if rec.is_empty():
		var from := node.global_position
		throw.learn(node.call("throw_stats"))
		_note(node, from + (character.aim_target() - from).limit_length(throw.range_of(node.get("kind"))), &"own", false)
	else:
		_note(node, node.global_position if rec["landed"] else rec["point"], &"own", false)


## A grenade came down (`&"grenade"` bounce or rest, `data` `{ position, kind, stage }`): the ones known already are marked down at
## that spot (seen coming down, deaf or not), and one within `hear_grenade` of a NPC that is not `deaf` is heard (so known) even if
## it was never seen.
func hear(character, data: Dictionary, deaf: bool) -> void:
	if not enabled or not data.get("stage") in [&"bounce", &"rest"]:
		return
	var at: Vector2 = data.get("position", Vector2.INF)
	for rec: Dictionary in _known.values():
		if is_instance_valid(rec["node"]) and rec["kind"] == data.get("kind") \
				and (rec["node"].global_position as Vector2).distance_to(at) <= LANDED_NEAR:
			rec["landed"] = true
			rec["rested"] = data.get("stage") == &"rest"
			rec["point"] = at
	if deaf or character.global_position.distance_to(at) > hear_grenade:
		return
	var node := _find(character.get_tree(), data.get("kind", &""), at, HEARD_NEAR)
	if node != null:
		_note(node, at, &"heard", true)


## An ally's radio call about a live grenade (`data` the callout: `status`, `point`, `kind`): known by the call, at the
## spot it names (a better source for a grenade it knows already wins: it keeps what it saw or heard itself).
func called(character, data: Dictionary) -> void:
	if not enabled:
		return
	var kind: StringName = CALL_KINDS.get(StringName(str(data.get("status", ""))), &"")
	if kind == &"":
		kind = data.get("kind", &"")
	var at: Vector2 = data.get("point", Vector2.INF)
	var node := _find(character.get_tree(), kind, at, CALLED_NEAR)
	if node != null:
		_note(node, at, &"called", true)


## Whether a callout `status` names a live grenade.
static func is_call(status: Variant) -> bool:
	return CALL_KINDS.has(StringName(str(status)))


## A grenade of `kind` went off at `at` (`&"explosion"`): forgotten, with the plan to get clear of it.
func burst(at: Vector2, kind: StringName) -> void:
	for id in _known.keys():
		var rec: Dictionary = _known[id]
		if rec["kind"] == kind and (not is_instance_valid(rec["node"]) or (rec["node"].global_position as Vector2).distance_to(at) <= LANDED_NEAR):
			_drop(id)


## Note grenade `node` as known at `point` by `source`: the first source stays (how the NPC came to know of it); sightings and later
## calls keep its spot true.
func _note(node: Node2D, point: Vector2, source: StringName, landed: bool) -> void:
	var id := node.get_instance_id()
	var rec: Dictionary = _known.get(id, {})
	if rec.is_empty():
		throw.learn(node.call("throw_stats"))  # (What a live grenade tells of its kind: its flash's cover reach, for one.)
		rec = { "node": node, "kind": node.get("kind"), "radius": float(node.call("danger_radius")), "point": point,
			"source": source, "landed": landed, "rested": false }
		_known[id] = rec
		return
	if source == rec["source"] or source == &"seen" or source == &"own":
		rec["point"] = point  # (Its source stays how the NPC first came to know of it; what it sees of it later keeps its spot true.)
	rec["landed"] = rec["landed"] or landed


## The live grenade of `kind` nearest to `at` within `reach` px, or null.
func _find(tree: SceneTree, kind: StringName, at: Vector2, reach: float) -> Node2D:
	var found: Node2D = null
	var best := reach
	for node: Node2D in tree.get_nodes_in_group(GROUP):
		if node.get("kind") != kind:
			continue
		var d := node.global_position.distance_to(at)
		if d <= best:
			best = d
			found = node
	return found


## Forget the grenades that are gone (gone off, or freed).
func _forget_gone() -> void:
	for id in _known.keys():
		var node = _known[id]["node"]
		if not is_instance_valid(node) or not (node as Node).is_in_group(GROUP):
			_drop(id)


## Forget grenade `id`: its record, its plan and what was radioed of it.
func _drop(id: int) -> void:
	_known.erase(id)
	_plans.erase(id)
	_told.erase(id)


## Whether the NPC knows of any live grenade.
func has_known() -> bool:
	return not _known.is_empty()


## The grenades the NPC knows of, soonest to go off first, as `{ point, kind, fuse_left, fuse (the whole fuse), radius, source }`.
func known() -> Array:
	var out: Array = []
	for id in _known:
		var rec: Dictionary = _known[id]
		if is_instance_valid(rec["node"]):
			out.append({ "point": rec["point"], "kind": rec["kind"], "fuse_left": float(rec["node"].call("fuse_left")),
				"fuse": throw.fuse_of(rec["kind"]), "radius": rec["radius"], "source": rec["source"] })
	out.sort_custom(func(a, b): return a["fuse_left"] < b["fuse_left"])
	return out


# --- Getting clear -------------------------------------------------------------------------------------------

## The plan for the grenade that goes off first among those the NPC is inside the danger zone of (or is already running
## from): `{ id, point, kind, radius, spot, crouch, fuse_left }`, where `spot` is the safe spot to run to (`Vector2.INF`: none
## in time) and `crouch` whether it is behind cover that shields a crouched body only. {} with nothing to run from. A plan is
## made when the NPC is first inside a grenade's zone, made again as the grenade moves, and kept while it lives, so the NPC
## holds its spot until the burst. `exclude` is every character's rid (a body shields nothing); `map` the navigation map.
func plan(character, space, map: RID, exclude: Array) -> Dictionary:
	if _known.is_empty():
		return {}
	var self_pos: Vector2 = character.global_position
	var height := float(character.get_surface().get("coverage", throw.stand_height()))
	var now := Engine.get_physics_frames()
	var best := {}
	var best_fuse := INF
	for id in _known:
		var rec: Dictionary = _known[id]
		var fuse := float(rec["node"].call("fuse_left"))
		var plan_: Dictionary = _plans.get(id, {})
		var point: Vector2 = rec["point"]
		if plan_.is_empty():
			if not throw.in_zone(space, rec["kind"], rec["radius"], point, self_pos, height, exclude):
				continue
			plan_ = _make(character, space, map, exclude, id, rec, fuse)
		elif (plan_["point"] as Vector2).distance_to(point) >= REPLAN_DIST and now - int(plan_["at"]) >= ceili(REPLAN_EVERY * Engine.physics_ticks_per_second):
			plan_ = _make(character, space, map, exclude, id, rec, fuse)
		_plans[id] = plan_
		if fuse < best_fuse:
			best_fuse = fuse
			best = plan_
	if best.is_empty():
		return {}
	var out: Dictionary = best.duplicate()
	out["fuse_left"] = best_fuse
	return out


## A fresh plan for grenade `id` (record `rec`) from where the NPC stands.
func _make(character, space, map: RID, exclude: Array, id: int, rec: Dictionary, fuse: float) -> Dictionary:
	var found: Dictionary = throw.escape(space, map, rec["kind"], rec["radius"], rec["point"], character.global_position, fuse,
		throw.run_speed(character), exclude)
	return { "id": id, "point": rec["point"], "kind": rec["kind"], "radius": rec["radius"], "spot": found["spot"],
		"crouch": found["crouch"], "at": Engine.get_physics_frames() }


## The grenades to radio now, `{ point, kind }`: ones the NPC has seen or heard come down and is running from, each once when it
## first came down and again if it then comes to rest somewhere else (a call names where it LANDED, which an ally's plan needs). A
## call from an ally, and a grenade the NPC threw (the thrower has its own call), are not repeated.
func announcements() -> Array:
	var out: Array = []
	for id in _plans:
		var rec: Dictionary = _known.get(id, {})
		if rec.is_empty() or not rec["landed"] or not rec["source"] in [&"seen", &"heard"]:
			continue
		var told: Dictionary = _told.get(id, {})
		var due: bool = told.is_empty() or (rec["rested"] and not told["rested"] and (told["point"] as Vector2).distance_to(rec["point"]) >= RECALL_DIST)
		if due:
			_told[id] = { "point": rec["point"], "rested": rec["rested"] }
			out.append({ "point": rec["point"], "kind": rec["kind"] })
		elif rec["rested"] and not told["rested"]:
			told["rested"] = true
	return out
