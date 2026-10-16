extends RefCounted

## AI PERCEPTION sub-domain — SNAPSHOT OPTIONS. Writes the option groups Von picks from: which hostile to fight, where to fire
## from, which flank side, how to close in or fall back, what to investigate, which room to search or explore and which
## furniture to use. Options are places and things, never verbs; each carries the facts that tell it from its siblings. A pure
## read of the event memory, the tactics geometry, the shared vocabulary and the knowledge handed in for the decision
## (`know`, set by `AgentSnapshot.build()`). `agent_snapshot.gd` calls it from `build()`.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const AgentEntry = preload("res://scenes/ai/perception/agent_entry.gd")
const AgentThrow = preload("res://scenes/ai/perception/agent_throw.gd")
const AgentSuspicion = preload("res://scenes/ai/perception/agent_suspicion.gd")
## Where along the stretch of the line back from a shot that lies in the room the shots came from a grenade is aimed, in order of
## preference (shares of the stretch, from where the line comes into the room): its middle first, then either side of it.
const SHOT_AIM_SHARES := [0.5, 0.35, 0.65, 0.2, 0.8]

## How a doorway's option says why its room is suspect (docs/grenades.md G18), one phrase per `AgentSuspicion` reason, measured with
## tools/von_probe.py (tools/von_scenarios/stun_entry_*.json).
const SUSPECT_PHRASES := {
	AgentSuspicion.GUNFIRE: "gunfire heard there",
	AgentSuspicion.FOOTSTEPS: "footsteps heard there",
	AgentSuspicion.SHOT_FROM: "shots at you came from there",
	AgentSuspicion.ALLY_FIGHT: "an ally radioed a fight there",
	AgentSuspicion.SEEN_IN: "a hostile seen going in",
	AgentSuspicion.LOST_BY_DOOR: "a hostile lost by its doorway",
	AgentSuspicion.HEADING_IN: "a hostile seen heading in",
}

var know := {}            ## The knowledge the perception hands in for this decision (see `AgentSnapshot.build()`).
var _throw_spots := {}    ## Throw spots worked out for this decision, by burst spot, reach and room kept out of (`_throw_option`; cleared by `begin`).
var _v: SnapshotVocab  ## The shared vocabulary and tuning; see snapshot_vocab.gd.
var _memory: RefCounted   ## The agent's event memory (read-only here); see agent_memory.gd.
var _tactics: RefCounted  ## The combat geometry; see agent_tactics.gd.
var _character: Node      ## The NPC's body, handed in once by `bind`.
var _entry: RefCounted    ## The doorway geometry; see agent_entry.gd.
var _throw: AgentThrow    ## The grenade geometry (the lob, the danger zone, the escape); see agent_throw.gd.
var _suspicion: AgentSuspicion  ## Why a room is suspect; see agent_suspicion.gd.


## Capture the collaborators the groups read. Called once by `AgentSnapshot.setup()`.
func setup(vocab: SnapshotVocab, memory: RefCounted, tactics: RefCounted, entry: RefCounted, throw: AgentThrow, suspicion: AgentSuspicion) -> void:
	_v = vocab
	_memory = memory
	_tactics = tactics
	_entry = entry
	_throw = throw
	_suspicion = suspicion


## Start a decision's option groups: forget what the last one worked out (`know` is set by the caller).
func begin() -> void:
	_throw_spots.clear()


## Hand in the NPC's body. Called once by `AgentSnapshot.bind()`.
func bind(character: Node) -> void:
	_character = character


## Which hostile to fight: one option per known hostile, with what makes it urgent or easy.
func hostile_group(ctx: Dictionary, hostiles: Array, analyses: Dictionary) -> Dictionary:
	var options: Array = []
	var self_pos: Vector2 = ctx["self_pos"]
	for t in hostiles.slice(0, _v.max_options_per_level):
		var a: Dictionary = analyses[t["id"]]
		# Only what tells the hostiles apart — common facts ("hostile") blur the match.
		var parts: Array = [
			t["name"],
			"in sight" if t["visible"] else "last seen %s" % _v.recency(t["age"]),
			"%s, %s of you" % [_v.dist_band(self_pos.distance_to(t["pos"])), _v.compass(t["pos"] - self_pos)],
		]
		if (t.get("vel", Vector2.ZERO) as Vector2).length() >= _v.still_speed:
			parts.append(_v.move_text(t, self_pos))
		var aim := _v.aim_text(t, self_pos, ctx["allies"])
		if aim != "":
			parts.append(aim)
		if t.get("item", "") != "Pistol":
			parts.append("holding a %s" % t.get("item", "nothing"))
		if t["reason"] == "attacked you":
			parts.append("they attacked you")
		var wound := _v.wound_band(t.get("wound_dmg", 0.0))
		if wound != "":
			parts.append(wound)
		if _v.blind_text(t) != "":
			parts.append(_v.blind_text(t))
		parts.append("you have a clear shot at them" if a["line"]["clear"] and a["line"]["in_range"] else "your line to them is blocked")
		var fighting := _allies_on(ctx, t)
		if fighting != "":
			parts.append("%s is already on them" % fighting)
		options.append({
			"id": "t_%d" % t["id"], "label": t["name"], "desc": " — ".join(parts),
			"bind": { "target": t["name"], "target_id": t["id"],
				"blinded": ("%s is blinded by a flash and cannot see you, or " % t["name"]) if t.get("blind", false) else "" },
		})
	return { "summary": "", "options": options }


## Reloading the gun: one option, offered only while a carried magazine would add rounds, so the
## planner takes it without asking (a lone option).
func reload_group(gun: int) -> Dictionary:
	var options: Array = []
	if gun >= 0 and _character.can_reload(gun):
		var text := "reload your %s" % _v.gun_noun(gun)
		options.append({ "id": "reload", "label": text, "desc": text })
	return { "summary": "a spare magazine is carried", "options": options }


## Where to fight hostile `t` from: this spot, firing spots around them named by place and cover, and an
## ambush in cover. Tactics has already dropped any spot the NPC would reach past a hostile or in the
## open under a hostile's eye.
func fire_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var f: Dictionary = a["fire"]
	var self_pos: Vector2 = ctx["self_pos"]
	var tpos: Vector2 = t["pos"]
	var options: Array = []
	if not f["here"].is_empty():
		options.append(_spot_option("fire_here", "where you stand", "fire from where you stand" + _v.room_suffix(self_pos), f["here"], false))
	for s in f["spots"]:
		if options.size() >= _v.max_options_per_level - (0 if f["ambush"].is_empty() else 1):
			break
		var dir := _v.compass(s["point"] - tpos)
		var place := _spot_place(s, dir)
		var lead := "fire from %s%s" % [place, (", %s of them" % dir) if s["cover"] != "" else ""]
		options.append(_spot_option("fire_" + dir.replace("-", "_"), place, lead, s, true))
	if not f["ambush"].is_empty():
		var amb: Dictionary = f["ambush"]
		var cover: String = amb["cover"] if amb["cover"] != "" else "cover"
		var desc := "wait in ambush behind the %s — you shoot when they show — %s" % [cover, _v.coming_text(t, self_pos)]
		if not amb["exposed_to"].is_empty():
			desc += " — also exposed to %s" % ", ".join(amb["exposed_to"])
		options.append({ "id": "ambush", "label": "ambush behind the %s" % cover, "desc": desc,
			"params": { "point": amb["point"], "style": &"ambush" }, "tags": { "inside": _v.is_inside(amb["point"]) } })
	var summary := ""
	if not f["here"].is_empty():
		summary = "from where you stand"
	elif not f["spots"].is_empty():
		summary = "from %s" % _spot_place(f["spots"][0], _v.compass(f["spots"][0]["point"] - tpos))
	elif not f["ambush"].is_empty():
		summary = "once they show, from an ambush behind cover"
	var wound := _v.wound_band(t.get("wound_dmg", 0.0))
	if summary != "" and wound != "":
		summary += "; they %s" % wound.replace("looks", "look")
	return { "summary": summary, "options": options }


## Which side to flank hostile `t` from: one option per reachable side other than the NPC's own.
func flank_group(t: Dictionary, a: Dictionary, rooms: Array) -> Dictionary:
	var tpos: Vector2 = t["pos"]
	var options: Array = []
	var open: Array = []
	for s in a["flanks"]:
		var room := SnapshotVocab.room_at(s["point"], rooms)
		var place: String = ("in the %s" % _v.room_name(room["type"])) if not room.is_empty() else "outside the house"
		var parts: Array = [
			"%s — %s of them, %s" % [SnapshotVocab.SIDE_WORDS[s["side"]], _v.compass(s["point"] - tpos), place],
			_v.side_status(s),
			"clear shot from there" if s["clear_shot"] else "line blocked from there",
			("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open",
			_v.route_text(s["route_len"], s["route_exposed"]) + " route",
		]
		if s["heading_toward"]:
			parts.append("they are moving toward that side")
		if not s["exposed_to"].is_empty():
			parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
		if s["ally_lane"] != "":
			parts.append("in %s's line of fire" % s["ally_lane"])
		options.append({
			"id": "side_" + s["side"],
			"label": "%s (%s)" % [SnapshotVocab.SIDE_WORDS[s["side"]], _v.room_name(room["type"]) if not room.is_empty() else "outside"],
			"desc": " — ".join(parts),
			"params": { "point": s["point"] },
			"tags": _geo_tags(s, {
				"inside": not room.is_empty(), "held": s["held_by"] != "", "crosses": s["crosses"] != "",
				"no_shot": not s["clear_shot"], "heading": s["heading_toward"], "lane": s["ally_lane"] != "" }),
		})
		if s["held_by"] == "" and s["crosses"] == "" and s["clear_shot"] and not s["heading_toward"] and s["ally_lane"] == "":
			open.append(s)
	var inside_open: Array = open.filter(func(s): return not SnapshotVocab.room_at(s["point"], rooms).is_empty())
	return {
		"summary": _flank_summary(a["flanks"], open, rooms),
		"summary_inside": _flank_summary(a["flanks"], inside_open, rooms),
		"options": options,
	}


## Throwing a grenade at hostile `t`, one option per kind carried (a frag first), offered against a hostile that is hidden from the
## NPC's line of fire (a bullet would be stopped: low furniture, a corner), or whose last-known spot is in a room the NPC is outside of
## (a defender barricaded in a room: even with a line of fire it is grenaded, not only shot at, docs/grenades.md G17), at a spot within
## throw range with a clear lob over what lies between: from where the NPC stands, else from a throw spot a short walk away
## (`_throw_option`). Each option carries the tags the tactic's `drop_tags` drop it by: `ally_in_blast` (a known ally, seen or on the radio,
## would be inside the grenade's danger zone at that spot) and `no_safe_spot` (the NPC itself would be, from where it throws, and has no way
## to get safe before the fuse is out: nowhere to crouch behind cover that shields it, no spot out of the burst's line within reach in time).
## Empty with no grenade, a clear shot at a hostile in the NPC's own room (or outside with it), no lob from anywhere near or no known spot.
func grenade_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var kinds: Array = know.get("carried_grenades", [])
	var spot: Vector2 = t["pos"]
	var held := _held_room(ctx, spot)
	var hidden: bool = not a["line"]["clear"]
	if kinds.is_empty() or (not hidden and held.is_empty()):
		return { "summary": "", "options": [] }
	var cover: String = a["line"]["blocker"]
	var room := "" if held.is_empty() else _v.room_name(held["type"])
	var options: Array = []
	for kind: StringName in kinds:
		var what := "frag" if kind == &"frag" else "stun"
		var option := _throw_option(ctx, kind, spot, t["id"], Rect2() if held.is_empty() else held["rect"], true)
		if option.is_empty():
			continue
		option["id"] = what
		option["label"] = ("%s %s behind their cover" % [what, t["name"]]) if hidden else ("%s %s in the %s" % [what, t["name"], room])
		option["desc"] = (("%s grenade onto where %s is hidden, behind the %s" % [what, t["name"], cover]) if hidden \
			else ("%s grenade into the %s, onto where %s holds it" % [what, room, t["name"]])) + _throw_from_text(ctx, option)
		options.append(option)
	if options.is_empty():
		return { "summary": "", "options": [] }
	var reach := _throw_reach_text(options)
	if hidden:
		return { "summary": "%s is hidden behind the %s, %s" % [t["name"], cover, reach], "options": options,
			"situation": "Your line to %s is blocked" % t["name"] }
	return { "summary": "%s holds the %s, a room you are outside of, %s" % [t["name"], room, reach], "options": options,
		"situation": "%s holds a room you are outside of" % t["name"], "held_room": room }


## Throwing a grenade where the shots at the NPC came from (docs/grenades.md G17): shot at by someone it cannot see from a
## room it is outside of (the line back from a shot, `shot_from`, runs into that room), one option per kind carried, onto the stretch of
## that line inside the room (`_shots_aim`: from where it stands, else from a throw spot). The same tags as `grenade_group`. Only while
## under fire with no hostile known (the unbound COMBAT level, where LOCATE is not offered toward such a room: `shooter_group`); empty otherwise.
func shots_grenade_group(ctx: Dictionary, hostiles: Array) -> Dictionary:
	var kinds: Array = know.get("carried_grenades", [])
	if kinds.is_empty() or not hostiles.is_empty() or not _memory.under_fire():
		return { "summary": "", "options": [] }
	var options: Array = []
	var room := ""
	for kind: StringName in kinds:
		var aim := _shots_aim(ctx, kind)
		if aim.is_empty():
			continue
		var option: Dictionary = aim["option"]
		var what := "frag" if kind == &"frag" else "stun"
		room = _v.room_name(aim["room"]["type"])
		option["id"] = what
		option["label"] = "%s where the shots came from" % what
		option["desc"] = "%s grenade into the %s, where the shots came from%s" % [what, room, _throw_from_text(ctx, option)]
		options.append(option)
	if options.is_empty():
		return { "summary": "", "options": [] }
	return { "summary": "the shots came from the %s, a room you are outside of, %s" % [room, _throw_reach_text(options)], "options": options,
		"situation": "The shots came from a room you are outside of", "held_room": room }


## The room hostile-held spot `spot` lies in when the NPC is outside that room (outdoors, or in another room), or {}.
func _held_room(ctx: Dictionary, spot: Vector2) -> Dictionary:
	var theirs := SnapshotVocab.room_at(spot, _v.rooms)
	if theirs.is_empty():
		return {}
	var here := SnapshotVocab.room_at(ctx["self_pos"], _v.rooms)
	return {} if not here.is_empty() and here["key"] == theirs["key"] else theirs


## Where to throw a grenade of `kind` at the shots: `{ option, room }`, the throw (`_throw_option`) onto a line back from a shot at the
## NPC (`AgentSuspicion.shot_line`: from where it leaves the room the shot landed in to the wall behind) inside the first room along it the
## NPC is outside of, at the point nearest the middle of that stretch (`SHOT_AIM_SHARES`) it can lob onto from where it stands, else from a
## throw spot; {} when there is none.
func _shots_aim(ctx: Dictionary, kind: StringName) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var here := SnapshotVocab.room_at(self_pos, _v.rooms)
	for shot: Dictionary in _memory.recall_all(&"shot_from"):
		var at: Vector2 = shot["at"]
		var line := AgentSuspicion.shot_line(_v.rooms, shot)
		var best := {}
		var nearest := INF
		for room in _v.rooms:
			if not here.is_empty() and room["key"] == here["key"]:
				continue
			var r: Rect2 = room["rect"]
			var poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
			for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, poly):
				var d := at.distance_to(piece[0])
				if d < nearest:
					nearest = d
					best = { "room": room, "from": piece[0], "to": piece[piece.size() - 1] }
		if best.is_empty():
			continue
		for walk: bool in [false, true]:
			for share: float in SHOT_AIM_SHARES:
				var spot: Vector2 = (best["from"] as Vector2).lerp(best["to"], share)
				var option := _throw_option(ctx, kind, spot, 0, best["room"]["rect"], walk)
				if not option.is_empty():
					return { "option": option, "room": best["room"] }
	return {}


## One grenade throw of `kind` onto `spot` (at hostile `target_id`, 0 for none), with its params and the tags the GRENADE tactic drops it by,
## or {} when there is no lob onto it in range from where the NPC stands nor (with `walk`) from a throw spot a short walk away (agent_tactics.gd
## `throw_spot`; never inside `keep_out`, the room the NPC is outside of that it throws into). `params.from` is where it throws
## from (where it stands, or the throw spot, with `params.walk`): the danger zone and the way out of it are judged from there. The caller
## words it (`id`, `label`, `desc`).
func _throw_option(ctx: Dictionary, kind: StringName, spot: Vector2, target_id: int, keep_out: Rect2, walk: bool) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var space = ctx["space"]
	var rids: Array = know["character_rids"]
	var from := self_pos
	var route := 0.0
	if not _throw.can_lob(space, self_pos, spot, _throw.range_of(kind), rids):
		if not walk:
			return {}
		var reach := _throw.reach_of(kind)
		var key := [spot, reach, keep_out]  # A frag and a stun of the same reach share their throw spot.
		if not _throw_spots.has(key):
			var lob := func(p: Vector2) -> bool: return _throw.throw_clear_on_arrival(space, p, spot, rids)
			var walk_to := func(p: Vector2) -> Dictionary: return _throw_walk(ctx, p)
			_throw_spots[key] = _tactics.throw_spot(ctx, spot, reach, lob, rids, keep_out, walk_to)
		var way: Dictionary = _throw_spots[key]
		if way.is_empty():
			return {}
		from = way["point"]
		route = way["route_len"]
	var radius := _throw.radius_of(kind)
	var ally := _ally_in_blast(ctx, kind, radius, spot)
	var cornered := false
	if _throw.in_zone(space, kind, radius, spot, from, _throw.stand_height(), rids):
		var out: Dictionary = _throw.escape(space, ctx["map"], kind, radius, spot, from, _throw.fuse_of(kind), _throw.run_speed(), rids)
		cornered = (out["spot"] as Vector2) == Vector2.INF
	var params := { "point": spot, "kind": kind, "radius": radius, "slot": AgentThrow.SLOTS[kind], "from": from, "walk": from != self_pos }
	if target_id != 0:
		params["target_id"] = target_id
	return { "params": params, "route_len": route,
		"tags": { "inside": _v.is_inside(spot), "ally_in_blast": ally, "no_safe_spot": cornered } }


## The walk to throw spot `p` as the NPC would walk it (agent_entry.gd `walk_route`: round the doorway views when it would take that, E18), and
## whether the entry guard would stop it on the way (`detour`): a doorway into a room not cleared that it crosses (E9), or a doorway view it
## comes into with no way round it (E15). `{ path, len, detour }`. The guard runs only where doorway views are kept out of (`AgentEntry.avoid_views`:
## tactical entry and the guard on).
func _throw_walk(ctx: Dictionary, p: Vector2) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var way: Dictionary = _entry.walk_route(self_pos, p, ctx["map"], ctx["space"])
	var detour := false
	if _entry.avoid_views:
		var cleared := func(key: String) -> bool: return _memory.age_of(&"cleared_room", "key", key) <= _v.search_memory_ttl
		detour = not _entry.threshold_ahead(way["path"], 0, self_pos, cleared, INF).is_empty() \
			or (not way["doors"] and not (way["views"] as Array).is_empty())
	return { "path": way["path"], "len": way["len"], "detour": detour }


## What a throw from a throw spot adds to its option's desc: where the spot is and the walk there (" — from the kitchen to the east, short
## route"); "" for a throw from where the NPC stands.
func _throw_from_text(ctx: Dictionary, option: Dictionary) -> String:
	var params: Dictionary = option["params"]
	if not params["walk"]:
		return ""
	var from: Vector2 = params["from"]
	return " — from %s to the %s, %s route" % [_v.place(from).trim_prefix("in "), _v.compass(from - (ctx["self_pos"] as Vector2)),
		_v.route_band(option["route_len"])]


## How a grenade group's summary says the throw is in reach: "within throwing range" when one of `options` is thrown from where the NPC
## stands, "within throwing range from a spot nearby" when each needs a walk to a throw spot.
func _throw_reach_text(options: Array) -> String:
	if options.any(func(o): return not o["params"]["walk"]):
		return "within throwing range"
	return "within throwing range from a spot nearby"


## Whether a known ally (seen, or one that radioed where it was) is inside the danger zone of a grenade of `kind` and `radius`
## that would burst at `spot`.
func _ally_in_blast(ctx: Dictionary, kind: StringName, radius: float, spot: Vector2) -> bool:
	var found := {}
	for al in ctx["allies"]:
		found[al["id"]] = al["pos"]
	for c in ctx["callouts"]:
		if not found.has(c["id"]):
			found[c["id"]] = c.get("position", Vector2.INF)
	for pos: Vector2 in found.values():
		if _throw.in_zone(ctx["space"], kind, radius, spot, pos, _throw.stand_height(), know["character_rids"]):
			return true
	return false



## Punching hostile `t`: one option, offered only while they are point-blank (`SnapshotVocab.dist_band`'s point-blank band), so
## MELEE is never chosen from across a room.
func melee_group(self_pos: Vector2, t: Dictionary) -> Dictionary:
	var dist := self_pos.distance_to(t["pos"])
	var summary := "they are %s and hold a %s" % [_v.dist_band(dist), t.get("item", "nothing")]
	var options: Array = []
	if dist <= _v.punch_range * 1.5:
		options.append({ "id": "punch", "label": "punch them", "desc": "punch them — " + summary })
	return { "summary": summary, "options": options }


## How to close in on hostile `t`: part-way along the route (with cover if any) or a straight rush.
func advance_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var options: Array = []
	for s in a["advance"]:
		var parts: Array = []
		var id := ""
		var label := ""
		if s.get("rush", false):
			id = "rush"
			label = "rush them"
			parts.append("rush straight at where they are" + _v.room_suffix(s["point"]))
			parts.append(_v.route_text(s["route_len"], s["route_exposed"]) + " route")
			parts.append("they hold a %s" % t.get("item", "nothing"))
		else:
			id = "advance_half" if s["fraction"] < 0.6 else "advance_close"
			label = "halfway to them" if id == "advance_half" else "close to them"
			parts.append(("advance halfway to them" if id == "advance_half" else "advance most of the way to them") + _v.room_suffix(s["point"]))
			parts.append(("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open")
			parts.append("clear shot from there" if s["clear_shot"] else "line blocked from there")
		if not s["exposed_to"].is_empty():
			parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
		options.append({ "id": id, "label": label, "desc": " — ".join(parts),
			"params": { "point": s["point"] }, "tags": _geo_tags(s, { "inside": _v.is_inside(s["point"]) }) })
	var summary := "they are %s, %s, holding a %s" % [
		_v.dist_band((ctx["self_pos"] as Vector2).distance_to(t["pos"])), _v.move_text(t, ctx["self_pos"]), t.get("item", "nothing")]
	var wound := _v.wound_band(t.get("wound_dmg", 0.0))
	if wound != "":
		summary += ", %s" % wound
	if _v.blind_text(t) != "":
		summary += ", %s" % _v.blind_text(t)
	return { "summary": summary, "options": options }


## Where to fall back to: out of sight of every known threat first, then farther away; with cover,
## route and the ally a spot lies toward. Threats are the known hostiles, else where fire came from.
func retreat_group(ctx: Dictionary, hostiles: Array, known_rooms: Array, dmg: float) -> Dictionary:
	var threats: Array = hostiles.map(func(h): return h["pos"])
	if threats.is_empty() and _memory.under_fire():
		threats.append(_shot_origin(ctx, false))
	if threats.is_empty():
		return { "summary": "", "options": [] }
	var spots: Array = _tactics.retreat_positions(ctx, threats, known_rooms)
	spots.sort_custom(func(x, y):
		if x["hidden"] != y["hidden"]:
			return x["hidden"]
		if (x["cover"] != "") != (y["cover"] != ""):
			return x["cover"] != ""
		return x["route_len"] < y["route_len"])
	var options: Array = []
	for s in spots:
		if options.size() >= _v.max_options_per_level:
			break
		var id := ""
		var lead := ""
		if s.get("ally", "") != "":
			id = "fall_ally_" + str(s["ally"]).to_lower()
			lead = "fall back to %s" % s["ally"]
		elif s.get("room", "") != "":
			id = "fall_" + str(s["room"]).to_lower().replace(" ", "_")
			lead = "fall back to the %s" % s["room"]
		else:
			id = "fall_cover"
			lead = "back off behind the %s close by" % (s["cover"] if s["cover"] != "" else "cover")
		if options.any(func(o): return o["id"] == id):
			continue
		var parts: Array = [lead,
			"out of every hostile's sight" if s["hidden"] else "farther from them, still in their sight",
			("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open",
			_v.route_text(s["route_len"], s["route_exposed"]) + " route"]
		options.append({ "id": id, "label": lead.trim_prefix("fall back to ").trim_prefix("back off "), "desc": " — ".join(parts),
			"params": { "point": s["point"] }, "tags": _geo_tags(s, { "inside": _v.is_inside(s["point"]), "hidden": s["hidden"] }) })
	var inside: Array = options.filter(func(o): return o["tags"]["inside"])
	return {
		"summary": _retreat_summary(options, dmg),
		"summary_inside": _retreat_summary(inside, dmg),
		"options": options,
	}


## What to investigate: lost hostiles (where last seen, and where they were heading), gunfire and footsteps heard,
## where unseen shots came from, and allies' radio calls for support — freshest first. What makes a room suspect (`AgentSuspicion`: a
## hostile last seen in it, by its doorway or heading in, gunfire or footsteps heard in it, shots from it, an ally's fight in it) is
## not a lead when the room is one a doorway of ENTER leads into (`entered`, see `entry_rooms`; the snapshot hands it over only while
## a stun can be thrown): that room is entered, and the entry says why (docs/grenades.md G18).
func lead_group(ctx: Dictionary, hostiles: Array, entered := {}) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var leads: Array = []
	for c in know["lost"].filter(func(c): return not _entered_any(entered, _suspicion.lost_rooms(_v.rooms, c).keys())):
		var moving: bool = (c["vel"] as Vector2).length() >= _v.still_speed
		leads.append({ "age": c["age"], "id": "lead_seen_%d" % c["id"], "label": "where you last saw %s" % c["name"],
			"desc": "where you last saw %s, %s — %s — %s route%s" % [c["name"], _v.where(c), _v.recency(c["age"]),
				_v.route_band(_route_len(ctx, c["pos"])), ("; they were moving %s" % _v.compass(c["vel"])) if moving else ""],
			"point": c["pos"] })
		if moving:
			var ahead: Vector2 = NavBuilder.snap(ctx["map"], c["pos"] + c["vel"] * minf(c["age"], _v.extrapolate_cap))
			leads.append({ "age": c["age"] + 0.01, "id": "lead_heading_%d" % c["id"], "label": "where %s was heading" % c["name"],
				"desc": "where %s was heading, %s — %s of where you last saw them — %s route" % [c["name"], _v.place(ahead),
					_v.compass(c["vel"]), _v.route_band(_route_len(ctx, ahead))],
				"point": ahead })
	for rec in _memory.recall_aged(&"heard_gunfire"):
		var pos: Vector2 = rec["data"]["pos"]
		if _entered_at(entered, pos):
			continue
		leads.append({ "age": rec["age"], "id": "lead_gunfire_%d_%d" % [floori(pos.x / 200.0), floori(pos.y / 200.0)],
			"label": "gunfire to the %s" % _v.compass(pos - self_pos),
			"desc": "gunfire heard to the %s, %s — %s — %s route" % [_v.compass(pos - self_pos), _v.place(pos),
				_v.recency(rec["age"]), _v.route_band(_route_len(ctx, pos))],
			"point": NavBuilder.snap(ctx["map"], pos) })
	for rec in _memory.recall_aged(&"heard_footsteps"):
		var pos: Vector2 = rec["data"]["pos"]
		if _entered_at(entered, pos):
			continue
		leads.append({ "age": rec["age"], "id": "lead_footsteps_%d_%d" % [floori(pos.x / 200.0), floori(pos.y / 200.0)],
			"label": "footsteps to the %s" % _v.compass(pos - self_pos),
			"desc": "footsteps heard to the %s, %s — %s — %s route" % [_v.compass(pos - self_pos), _v.place(pos),
				_v.recency(rec["age"]), _v.route_band(_route_len(ctx, pos))],
			"point": NavBuilder.snap(ctx["map"], pos) })
	var shot: Dictionary = _memory.recall(&"shot_from")
	if _memory.under_fire() and hostiles.is_empty() and not (not shot.is_empty() and _entered_any(entered, AgentSuspicion.shot_rooms(_v.rooms, shot))):
		var from: Vector2 = _memory.under_fire_from()
		var origin: Vector2 = _shot_origin(ctx)
		# The point toward the shots is measured from where the NPC stands, so reaching it never spends it: one the walk to which
		# ends where it stands (shots from beyond the walkable ground) is not a lead, as for LOCATE (`AgentTactics.where_it_stands`).
		if not _tactics.where_it_stands(ctx, origin):
			leads.append({ "age": 0.0, "id": "lead_shooter", "label": "where the shots came from",
				"desc": "where the shots at you came from — the %s, just now" % _v.compass(from), "point": origin })
	for c in ctx["callouts"]:
		if not str(c.get("path", "")).begins_with("combat") or _entered_at(entered, c.get("target_pos", Vector2.INF)):
			continue
		var at: Vector2 = c.get("position", self_pos)
		var status: String = c.get("status", "")
		leads.append({ "age": c["age"], "id": "lead_ally_%d" % c["id"], "label": "support %s" % c["name"],
			"desc": "support %s, %s — %s, %s of you — radio %s%s" % [c["name"], _v.place(at), c.get("label", "fighting"),
				_v.compass(at - self_pos), _v.recency(c["age"]), ("; " + status) if status != "" else ""],
			"point": NavBuilder.snap(ctx["map"], at) })
	# A lead checked more recently than the event behind it is spent (fresh news there is offered again).
	leads = leads.filter(func(l): return not _memory.age_of(&"checked_lead", "id", l["id"]) < l["age"])
	leads.sort_custom(func(x, y): return x["age"] < y["age"])
	var options: Array = []
	for l in leads.slice(0, _v.max_options_per_level):
		options.append({ "id": l["id"], "label": l["label"], "desc": l["desc"],
			"params": { "point": l["point"], "lead": l["id"] }, "tags": { "inside": _v.is_inside(l["point"]) } })
	var summary := ""
	if not options.is_empty():
		summary = "%d lead%s (freshest: %s)" % [leads.size(), "" if leads.size() == 1 else "s", options[0]["desc"].get_slice(" — ", 0)]
	return { "summary": summary, "options": options }


## Whether world point `p` lies in a room of `entered` (the rooms a doorway of ENTER leads into).
func _entered_at(entered: Dictionary, p: Vector2) -> bool:
	return not entered.is_empty() and entered.has(_room_key_at(p))


## Whether any of room keys `keys` is in `entered`.
func _entered_any(entered: Dictionary, keys: Array) -> bool:
	return not entered.is_empty() and keys.any(func(k): return entered.has(k))


## The key of the room world point `p` lies in, or "".
func _room_key_at(p: Vector2) -> String:
	return AgentSuspicion.room_key_at(_v.rooms, p)


## Under fire from someone the NPC cannot see: the one way to find them — toward where the shots came
## from. Empty unless under fire with no hostile known, and empty for shots from a room the NPC is outside of (the line back from the
## newest shot, `shot_from`, runs into a room it is not in: a barricaded shooter), which it does not walk into: GRENADE
## at the shots' origin (`shots_grenade_group`) or RETREAT instead. Empty too when the walk there ends where the NPC stands (within
## `AgentTactics.STRIDE`: the shots came from beyond the walkable ground, and the navmesh pulls the point back to it).
func shooter_group(ctx: Dictionary, hostiles: Array) -> Dictionary:
	if not _memory.under_fire() or not hostiles.is_empty() or _shots_from_a_room(ctx):
		return { "summary": "", "options": [] }
	var from: Vector2 = _memory.under_fire_from()
	var origin: Vector2 = _shot_origin(ctx)
	if _tactics.where_it_stands(ctx, origin):
		return { "summary": "", "options": [] }  # The shots came from beyond the walkable ground: the walk toward them ends where it stands.
	var dir := _v.compass(from)
	return { "summary": "the shots came from the %s" % dir, "options": [{
		"id": "toward_shots", "label": "toward the shots",
		"desc": "move toward where the shots came from — the %s%s — %s route" % [dir, _v.room_suffix(origin), _v.route_band(_route_len(ctx, origin))],
		"params": { "point": origin }, "tags": { "inside": _v.is_inside(origin) } }] }


## Whether the line back from the newest shot at the NPC (`shot_from`) runs into a room the NPC is not in.
func _shots_from_a_room(ctx: Dictionary) -> bool:
	var shot: Dictionary = _memory.recall(&"shot_from")
	if shot.is_empty():
		return false
	var here := _room_key_at(ctx["self_pos"])
	return AgentSuspicion.shot_rooms(_v.rooms, shot).any(func(key): return key != here)


## Which known room to search next: not-recently-searched first, then nearest; plus the entrance or
## the house itself while outside. With doorways to enter by (`entered`: the keys of the rooms they lead into), those
## rooms and the front entrance are left to ENTER.
func search_group(ctx: Dictionary, known_rooms: Array, rooms: Array, entered := {}) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var here := SnapshotVocab.room_at(self_pos, rooms)
	var candidates: Array = []
	var unsearched := 0
	for room in known_rooms:
		if (not here.is_empty() and room["key"] == here["key"]) or entered.has(str(room["key"])):
			continue
		var age: float = _memory.age_of(&"visited_room", "key", room["key"])
		var point: Vector2 = NavBuilder.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		var stale := age > _v.search_memory_ttl
		if stale:
			unsearched += 1
		candidates.append({ "room": room, "age": age, "stale": stale, "point": point, "len": _route_len(ctx, point) })
	candidates.sort_custom(func(x, y):
		if x["stale"] != y["stale"]:
			return x["stale"]
		return x["len"] < y["len"])
	var options: Array = []
	if here.is_empty() and entered.is_empty():  # With doorways to enter by, ENTER offers the way in.
		if know["entry_point"] != Vector2.ZERO:
			options.append({ "id": "entrance", "label": "the front entrance",
				"desc": "the front entrance — %s route" % _v.route_band(_route_len(ctx, know["entry_point"])),
				"params": { "point": know["entry_point"] }, "tags": { "inside": false } })
		elif known_rooms.is_empty() and not rooms.is_empty():
			var centre := _v.house_centre()
			options.append({ "id": "approach", "label": "the house",
				"desc": "head for the house and find a way in — %s route" % _v.route_band(_route_len(ctx, centre)),
				"params": { "point": NavBuilder.snap(ctx["map"], centre) }, "tags": { "inside": false } })
	for c in candidates:
		if options.size() >= _v.max_options_per_level:
			break
		var room: Dictionary = c["room"]
		options.append({ "id": "room_%s" % room["key"], "label": "the %s" % _v.room_name(room["type"]),
			"desc": "the %s — %s — %s route" % [_v.room_name(room["type"]),
				"unsearched" if c["stale"] else "searched %s" % _v.recency(c["age"]), _v.route_band(c["len"])],
			"params": { "point": c["point"], "look_around": true }, "tags": { "inside": true } })
	var summary := "%d of %d known rooms unsearched" % [unsearched, known_rooms.size()]
	if known_rooms.is_empty():
		summary = "find your way into the house and explore it"
	return { "summary": summary, "options": options }


## The doorways the NPC could enter a room by, for a tactical entry (ENTER): from outside the outer doors, from a room
## its doors into the next, each into a room it has not seen (named by direction only) or not searched lately. A
## doorway's place is the NPC's stack slot beside it (the lowest the radio leaves free, on the side the team stacks
## on, or its own when the way there crosses the doorway's view), out of the doorway's line of sight; the behaviour runs the entry from there. Nearest first, capped.
func entry_group(ctx: Dictionary, rooms: Array) -> Dictionary:
	if not know.get("entry_enabled", false):
		return { "summary": "", "options": [] }
	var self_pos: Vector2 = ctx["self_pos"]
	var here := SnapshotVocab.room_at(self_pos, rooms)
	var known: Dictionary = know["known_room_keys"]
	var why: Dictionary = _suspicion.rooms_suspected(rooms, know["lost"], ctx["callouts"])
	var picks: Array = []
	for e in _entry.entries_from(str(here.get("key", ""))):
		var into: String = e["into"]
		var status := "unexplored"
		if known.has(into) or known.has(StringName(into)):
			if _memory.age_of(&"cleared_room", "key", into) <= _v.search_memory_ttl:
				continue  # Cleared lately: nothing to clear.
			status = "unsearched"
		var g: Dictionary = _entry.geometry(e["id"], into, ctx["map"], ctx["space"])
		if g.is_empty():
			continue
		var team := AgentEntry.claims(e["id"], ctx["callouts"])
		var slot := AgentEntry.free_slot(team, ctx["self_id"])
		var side: int = _entry.stack_side_from(g, team, self_pos, ctx["map"], ctx["space"])
		var point := AgentEntry.slot_point(g, side, AgentEntry.place(team, side, slot))
		picks.append({ "e": e, "status": status, "point": point, "slot": slot, "len": _route_len(ctx, point),
			"suspect": why.get(into, []).map(func(w): return SUSPECT_PHRASES[w]) })
	picks.sort_custom(func(x, y):
		if x["suspect"].is_empty() != y["suspect"].is_empty():
			return not x["suspect"].is_empty()  # A room a hostile is suspected in first.
		return x["len"] < y["len"])
	var options: Array = []
	for p in picks.slice(0, _v.max_options_per_level):
		var e: Dictionary = p["e"]
		var room := SnapshotVocab.room_by_key(rooms, e["into"])
		var place := "the doorway into the %s" % _v.room_name(room["type"]) if p["status"] == "unsearched" \
			else "the doorway to the %s" % _v.compass((e["pos"] as Vector2) - self_pos)
		options.append({ "id": e["id"], "label": place,
			"desc": " — ".join([place] + (p["suspect"] if not p["suspect"].is_empty() else [p["status"]]) + ["%s route" % _v.route_band(p["len"])]),
			"params": { "opening": e["id"], "into": e["into"], "point": p["point"], "slot": p["slot"] },
			"tags": { "inside": not here.is_empty() } })
	return { "summary": options[0]["desc"] if not options.is_empty() else "", "options": options }


## The keys of the rooms the doorways of an `entry_group` lead into: those are entered by ENTER, not walked into.
static func entry_rooms(entries: Dictionary) -> Dictionary:
	var out := {}
	for opt in entries.get("options", []):
		out[str(opt["params"]["into"])] = true
	return out


## Unexplored parts of the house (rooms not yet seen), named by direction only — the NPC doesn't know
## what they are. One per compass direction, nearest first, at most two. A room a doorway of ENTER leads into
## (`entered`) is left to it.
func explore_group(ctx: Dictionary, rooms: Array, entered := {}) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var known: Dictionary = know["known_room_keys"]
	var by_dir := {}
	for room in rooms:
		if known.has(room["key"]) or entered.has(str(room["key"])):
			continue
		var point: Vector2 = NavBuilder.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		var dir := _v.compass(point - self_pos)
		var dist := self_pos.distance_to(point)
		if not by_dir.has(dir) or dist < by_dir[dir]["dist"]:
			by_dir[dir] = { "room": room, "point": point, "dist": dist }
	var picks: Array = by_dir.values()
	picks.sort_custom(func(x, y): return x["dist"] < y["dist"])
	var options: Array = []
	for p in picks.slice(0, 2):
		var dir := _v.compass(p["point"] - self_pos)
		options.append({ "id": "explore_" + dir.replace("-", "_"), "label": "unexplored %s" % dir,
			"desc": "an unexplored part of the house to the %s — %s route" % [dir, _v.route_band(_route_len(ctx, p["point"]))],
			"params": { "point": p["point"], "look_around": true }, "tags": { "inside": true } })
	return { "summary": "explore the house", "options": options }


## The object interactions the NPC knows of: one option per DISTINCT action label, pointing at the
## nearest known object offering it (item-gated). Not capped — Von ranks them against the goal.
func interaction_group(self_pos: Vector2) -> Dictionary:
	var known_objs: Dictionary = know["known_object_ids"]
	var nearest := {}  # action label -> nearest known object + its spec (+ squared distance).
	for obj in know["interactables"]:
		if not is_instance_valid(obj) or not known_objs.has(obj.get_instance_id()):
			continue
		var d: float = obj.global_position.distance_squared_to(self_pos)
		for spec in obj.get_interactions():
			var needed: int = spec.get("requires_item", 0)
			if needed != 0 and not _character.has_item(needed):
				continue
			var label: String = spec.get("label", spec.get("id", ""))
			if not nearest.has(label) or d < nearest[label]["d"]:
				nearest[label] = { "obj": obj, "id": spec.get("id", ""), "d": d }
	var options: Array = []
	for label in nearest:
		var obj = nearest[label]["obj"]
		options.append({ "id": "do_%d_%s" % [obj.get_instance_id(), nearest[label]["id"]], "label": label,
			"desc": "%s%s" % [label, _v.room_suffix(obj.global_position)],
			"params": { "object": obj, "id": nearest[label]["id"] }, "tags": { "inside": _v.is_inside(obj.global_position) } })
	var labels: Array = nearest.keys()
	var summary := "use furniture: %s%s" % [", ".join(labels.slice(0, 4)).to_lower(), ", …" if labels.size() > 4 else ""]
	return { "summary": summary if not labels.is_empty() else "", "options": options }


## Named places to go: each known room (except this one) and the NPC's starting position.
func room_group(ctx: Dictionary, known_rooms: Array, rooms: Array) -> Dictionary:
	var here := SnapshotVocab.room_at(ctx["self_pos"], rooms)
	var options: Array = []
	for room in known_rooms:
		if not here.is_empty() and room["key"] == here["key"]:
			continue
		var point: Vector2 = NavBuilder.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		options.append({ "id": "room_%s" % room["key"], "label": "the %s" % _v.room_name(room["type"]), "desc": "the %s" % _v.room_name(room["type"]),
			"params": { "point": point, "arrive_room": room["key"] }, "tags": { "inside": true } })
	options.append({ "id": "post", "label": "your starting position", "desc": "your starting position",
		"params": { "point": know["post"] }, "tags": { "inside": _v.is_inside(know["post"]) } })
	return { "summary": "", "options": options }


## The order this NPC's leader gave it (`docs/leadership.md` LD5, LD6), as the one option of the ORDER node, carrying the primitive it
## runs and that primitive's params: `defend_room` is a `defend` of the room at this member's defend spot with its gun on its doorway
## (D2, `AgentEntry.defend_spot`: the members of the order share the room's doorways out in the order `to` names them); `stack` is an
## `entry` through the ordered doorway into the ordered room (`opening`, `into`, `bang`, and the side: `stack_at` or `split`). Each
## carries the order's `order_id`. Empty with no order, or one this NPC cannot carry out (a room or doorway it does not know): refused.
func order_group(ctx: Dictionary, order: Dictionary, rooms: Array) -> Dictionary:
	if order.is_empty():
		return { "summary": "", "options": [] }
	var kind := String(order.get("kind", ""))
	var option := {}
	match kind:
		"defend_room":
			var room := SnapshotVocab.room_by_key(rooms, String(order.get("room", "")))
			if room.is_empty():
				return { "summary": "", "options": [] }
			var to: Array = (order.get("to", []) as Array).filter(func(m): return is_instance_valid(m))
			var nth := maxi(to.find(_character), 0)
			var at: Dictionary = _entry.defend_spot(String(room["key"]), nth, to.size(), ctx["map"], ctx["space"])
			if at.is_empty():
				return { "summary": "", "options": [] }
			var params := { "room": String(room["key"]), "spot": at["spot"], "door": at["door"], "order_id": order["id"] }
			if at["door_pos"] != Vector2.INF:
				params["door_pos"] = at["door_pos"]
			var label := "defend the %s" % _v.room_name(room["type"])
			option = { "id": "defend_%s" % room["key"], "label": label, "desc": label, "primitive": &"defend", "params": params,
				"tags": { "inside": true } }
		"stack":
			var into := SnapshotVocab.room_by_key(rooms, String(order.get("into", "")))
			if into.is_empty() or _entry.geometry(String(order.get("opening", "")), String(into["key"]), ctx["map"], ctx["space"]).is_empty():
				return { "summary": "", "options": [] }
			var params := { "opening": String(order["opening"]), "into": String(into["key"]), "bang": bool(order.get("bang", false)),
				"split": bool(order.get("split", false)), "order_id": order["id"] }
			if order.get("stack_at") is Vector2:
				params["stack_at"] = order["stack_at"]
			var label := "the doorway into the %s%s" % [_v.room_name(into["type"]), " with a stun" if params["bang"] else ""]
			option = { "id": "stack_%s" % order["opening"], "label": label, "desc": label, "primitive": &"entry", "params": params,
				"tags": { "inside": _v.is_inside(ctx["self_pos"]) } }
		_:
			return { "summary": "", "options": [] }
	return { "summary": option["label"], "options": [option] }


## Tag every option that names a place with the room it lies in (`tags.room`, the room key, "" outside): where its walk ends, the
## spot a throw is made `from` or else its `point`. The planner keeps a member ordered to defend a room to the options in it (LD8).
## Tags are not text: what Von reads is unchanged.
static func tag_rooms(groups: Dictionary, rooms: Array) -> void:
	for name in groups:
		var group = groups[name]
		if name == "per_target":
			for per in (group as Dictionary).values():
				tag_rooms(per, rooms)
			continue
		if not group is Dictionary:
			continue
		for o in group.get("options", []):
			var params: Dictionary = o.get("params", {})
			var at = params.get("from", params.get("point"))
			if at is Vector2 and at != Vector2.INF and o.get("tags") is Dictionary:
				o["tags"]["room"] = String(SnapshotVocab.room_at(at, rooms).get("key", ""))


## `tags` plus the spot's geometry, kept for the routes debug overlay (`clear_shot`, `route_exposed`,
## `cover`, and the flank `ally_lane` / `held_by` / `crosses` names). Planner
## filters read only the boolean tags (`inside` / `hidden`, and on a flank side `held` / `crosses` /
## `no_shot` / `heading` / `lane`), so the extra keys are inert to decisions.
func _geo_tags(s: Dictionary, tags: Dictionary) -> Dictionary:
	for key in ["clear_shot", "route_exposed", "cover", "ally_lane", "held_by"]:
		if s.has(key):
			tags[key] = s[key]
	if s.has("crosses"):
		tags["crosses_name"] = s["crosses"]
	return tags


## One fighting-spot option: its place (`lead`), clear shot, cover, the route there (`moving`: a spot to
## go to rather than where the NPC stands) and other exposure.
func _spot_option(id: String, label: String, lead: String, s: Dictionary, moving: bool) -> Dictionary:
	var parts: Array = [lead]
	parts.append("clear shot" if s["clear_shot"] else "line blocked")
	parts.append(("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open")
	if moving:
		parts.append(_v.route_text(s["route_len"], s["route_exposed"]) + " route")
	if not s["exposed_to"].is_empty():
		parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
	return { "id": id, "label": label, "desc": " — ".join(parts),
		"params": { "point": s["point"], "style": &"peek_cover" }, "tags": _geo_tags(s, { "inside": _v.is_inside(s["point"]) }) }


## A firing spot named by its place, `dir` being its bearing from the target: "behind the sofa in the
## kitchen" with cover close by, else "the kitchen, north of them" / "outside, north of them".
func _spot_place(s: Dictionary, dir: String) -> String:
	var room := SnapshotVocab.room_at(s["point"], _v.rooms)
	if s["cover"] != "":
		return "behind the %s %s" % [s["cover"], ("in the %s" % _v.room_name(room["type"])) if not room.is_empty() else "outside"]
	return "%s, %s of them" % [("the %s" % _v.room_name(room["type"])) if not room.is_empty() else "outside", dir]


## The FLANK branch summary over the `open` sides: how many, the best at a glance (Von still makes
## the pick).
func _flank_summary(flanks: Array, open: Array, rooms: Array) -> String:
	if flanks.is_empty():
		return ""
	var text := ""
	if open.is_empty():
		text = "every side is taken or out of reach"
	else:
		open.sort_custom(func(x, y): return _flank_rank(x) > _flank_rank(y))
		var best: Dictionary = open[0]
		var best_room := SnapshotVocab.room_at(best["point"], rooms)
		text = "%d free side%s; best: %s%s, %s route, %s" % [open.size(), "" if open.size() == 1 else "s",
			SnapshotVocab.SIDE_WORDS[best["side"]], (" via the %s" % _v.room_name(best_room["type"])) if not best_room.is_empty() else " outside",
			_v.route_text(best["route_len"], best["route_exposed"]), "cover" if best["cover"] != "" else "in the open"]
	return text


## How good an open flank looks at a glance (for the summary's "best" only — Von makes the pick).
func _flank_rank(s: Dictionary) -> int:
	return int(s["clear_shot"]) * 4 + int(s["cover"] != "") * 2 + int(not s["route_exposed"]) + int(s["route_len"] <= _v.route_buckets.x)


## The RETREAT branch summary over `options` (best first): whether anywhere hides the NPC, the best
## spot, and how hurt it is.
func _retreat_summary(options: Array, dmg: float) -> String:
	if options.is_empty():
		return ""
	var best: Dictionary = options[0]
	return "best: %s, %s; you are %s" % [best["label"],
		"out of their sight" if best["tags"]["hidden"] else "farther from them, still in their sight", _v.health_band(dmg)]


## The world point to investigate when under fire from an unseen shooter: `investigate_distance` px
## from the NPC toward where the shots came from, snapped onto the navmesh unless `snap_to_navmesh` is false
## (the retreat group wants the raw direction as a threat position, not a reachable spot).
func _shot_origin(ctx: Dictionary, snap_to_navmesh := true) -> Vector2:
	var from: Vector2 = _memory.under_fire_from()
	var p: Vector2 = (ctx["self_pos"] as Vector2) + from.normalized() * _v.investigate_distance
	return NavBuilder.snap(ctx["map"], p) if snap_to_navmesh else p


## The length (px) of the route the NPC will walk from where it stands to `p`: the one that keeps out of the doorway views when it would
## take it (`AgentEntry.walk_route`, E18), else the plain one.
func _route_len(ctx: Dictionary, p: Vector2) -> float:
	return float(_entry.walk_route(ctx["self_pos"], p, ctx["map"], ctx["space"])["len"])


## The ally (perceived near the target, or calling it on the radio) already fighting hostile `t`.
func _allies_on(ctx: Dictionary, t: Dictionary) -> String:
	for c in ctx["callouts"]:
		if c.get("target_id", 0) == t["id"]:
			return c["name"]
	for a in ctx["allies"]:
		if (a["pos"] as Vector2).distance_to(t["pos"]) <= _v.flank_ally_radius * 0.5:
			return a["name"]
	return ""
