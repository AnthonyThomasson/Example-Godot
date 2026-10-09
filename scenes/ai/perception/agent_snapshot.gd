extends RefCounted

## AI PERCEPTION sub-domain — the SNAPSHOT AUTHOR. The BUILD half of perception: given what the NPC
## currently knows (contacts, memory, learned house knowledge) and the combat geometry, it writes the
## decision SNAPSHOT the planner walks — named boolean `facts` the tree gates on, named state `sections`
## Von reads, and named option `groups` (places and things with the attributes a choice turns on). It is
## a pure transform: it reads the event memory and the tactics module, holds no state between calls, and
## never writes memory, decides or picks. `agent_perception.gd` (the SEE half) owns it, like it owns
## vision / hostility / memory / tactics, and calls `build()` once per decision.
##
## Everything Von reads is worded for a CLASSIFIER that picks the option whose text best matches the
## state and cannot do arithmetic: distances, routes and ages are BANDS ("in pistol range", "short
## route", "recently"); each option carries the facts that distinguish it from its siblings, in a
## fixed order; there are NO negations (an encoder reads "no cover" as "cover" — say "in the open",
## "line blocked", "free", "unsearched"); and the state uses the same canonical phrases the decision
## tree's situation descriptions are written in, so a fact in the state lights up the option it argues
## for. Options are places and things, never verbs — the decision tree decides what to do at them.

## Inventory slot of the pistol (ItemRegistry id), tested for the `has_pistol` fact.
const PISTOL_SLOT := 3
## Compass names for an 8-wind direction, indexed clockwise from east (screen +y is south).
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
## How each flank side of a target is named to Von.
const SIDE_WORDS := { "left": "their left side", "right": "their right side", "rear": "behind them", "front": "their front" }

# --- Config fields the perception copies from its own config before each decision. ---
var shoot_range: float = 500.0
var punch_range: float = 48.0
var recency_bands: Vector2 = Vector2(2.0, 8.0)
var route_buckets: Vector2 = Vector2(400.0, 900.0)
var aim_cone: float = 20.0
var still_speed: float = 20.0
var flank_ally_radius: float = 500.0
var investigate_distance: float = 300.0
var extrapolate_cap: float = 3.0
var max_options_per_level: int = 4
var hurt_threshold: float = 15.0
var critical_threshold: float = 35.0
var max_contacts_in_state: int = 4
var search_memory_ttl: float = 60.0

var _memory: RefCounted   ## The agent's event memory (read-only here); see agent_memory.gd.
var _tactics: RefCounted  ## The combat geometry; see agent_tactics.gd.
var _rooms: Array = []     ## The house rooms for the decision being built (set at the top of build()).
var _know := {}            ## The knowledge the perception hands in for this decision (see build()).


## Capture the collaborators the author reads: the event memory and the combat geometry. Called once by
## the perception in its setup(), after it has built both. The config fields are set directly by the
## perception's apply_config() (like the other modules), so there is no separate configure step.
func setup(memory: RefCounted, tactics: RefCounted) -> void:
	_memory = memory
	_tactics = tactics


## BUILD pass — run at the start of each decision. Assemble the snapshot the decision planner walks,
## from what the agent currently sees and remembers (NOT from ground truth): `goal` is the behaviour
## string Von ranks against; `activity` is the behaviour's line for what the NPC is doing now. The
## perception hands in the knowledge this reads over: `known` (its `contacts()`), `callouts`, and
## `knowledge` (learned rooms/objects, interactables, the NPC's post and entry point, and lost
## hostiles — see the perception's `sense()`). Returns { facts, sections, sections_per_target, options }.
func build(character, rooms: Array, goal: String, activity: String, known: Array, callouts: Array, knowledge: Dictionary) -> Dictionary:
	_rooms = rooms
	_know = knowledge
	var self_pos: Vector2 = character.global_position
	var hostiles: Array = known.filter(func(c): return c["hostile"])
	var allies: Array = known.filter(func(c): return c["ally"] and not c["hostile"])
	var ctx := {
		"space": character.get_world_2d().direct_space_state,
		"map": character.get_world_2d().navigation_map,
		"self_pos": self_pos,
		"exclude": [character.get_rid()],
		"hostiles": hostiles,
		"allies": allies,
		"callouts": callouts,
		"fronts": {},
	}
	# Each hostile's front (its last-seen facing while recent, else toward this NPC): the frame its
	# flanks are measured in, and where it is looking when a spot is judged watched.
	for h in hostiles:
		ctx["fronts"][h["id"]] = _tactics.front_angle(h, self_pos, h["visible"] or h["age"] <= recency_bands.y)
	var known_rooms: Array = _know["known_rooms"]

	# Per known hostile: the combat geometry, the option groups and the sections that follow from it.
	var per_target := {}
	var per_sections := {}
	var analyses := {}
	for t in hostiles.slice(0, max_options_per_level):
		var a := _analyze(ctx, t)
		analyses[t["id"]] = a
		per_target[t["id"]] = {
			"fire_positions": _fire_group(ctx, t, a),
			"flank_sides": _flank_group(t, a, rooms),
			"advance_positions": _advance_group(ctx, t, a),
			"melee": _melee_group(self_pos, t),
		}
		per_sections[t["id"]] = {
			"exposure": _exposure_text(ctx, t, a),
			"flanks": _flanks_text(t, a),
			"allies": _allies_text(ctx, t, a),
		}

	var primary: Dictionary = hostiles[0] if not hostiles.is_empty() else {}
	var line: Dictionary = analyses[primary["id"]]["line"] if not primary.is_empty() else {}
	var leads := _lead_group(ctx, hostiles)
	var dmg: float = character.damage_taken()
	var facts := {
		"hostile_known": not hostiles.is_empty(),
		"hostile_visible": hostiles.any(func(c): return c["visible"]),
		"threat_known": not hostiles.is_empty() or _under_fire(),
		"has_pistol": character.has_item(PISTOL_SLOT),
		"under_fire": _under_fire(),
		"hit_recently": _hit_recently(),
		"engaged": _engaged_fresh(),
		"leads": not leads["options"].is_empty(),
		"hurt": dmg >= hurt_threshold,
		"critical": dmg >= critical_threshold,
		"inside": not _room_at(self_pos, rooms).is_empty(),
		"exposed": line.get("clear", false) or (primary.is_empty() and _under_fire()),
		"in_cover": line.get("cover", "") != "",
	}
	var sections := {
		"goal": goal,
		"situation": _situation_text(character, rooms),
		"current": ("Current activity: %s." % activity) if activity != "" else "",
		"odds": _odds_text(hostiles, allies, ctx["callouts"], not leads["options"].is_empty()),
		"contacts": _contacts_text(self_pos, known),
		"exposure": per_sections[primary["id"]]["exposure"] if not primary.is_empty() else _unseen_fire_text(),
		"allies": per_sections[primary["id"]]["allies"] if not primary.is_empty() else _allies_text(ctx, {}, {}),
		"flanks": per_sections[primary["id"]]["flanks"] if not primary.is_empty() else "",
		"awareness": _awareness_text(self_pos, not hostiles.is_empty()),
	}
	var options := {
		"per_target": per_target,
		"threat": { "summary": _threat_summary(self_pos, hostiles) },
		"hostiles": _hostile_group(ctx, hostiles, analyses),
		"retreat_positions": _retreat_group(ctx, hostiles, known_rooms, dmg),
		"leads": leads,
		"shooter": _shooter_group(ctx, hostiles),
		"search_rooms": _search_group(ctx, known_rooms, rooms),
		"explore": _explore_group(ctx, rooms),
		"interactions": _interaction_group(character, self_pos, rooms),
		"rooms": _room_group(ctx, known_rooms, rooms),
	}
	return { "facts": facts, "sections": sections, "sections_per_target": per_sections, "options": options }


## The combat geometry around hostile `t`: its frame (front bearing), the line between the NPC and it,
## and the candidate fire / flank / advance positions.
func _analyze(ctx: Dictionary, t: Dictionary) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var front: float = ctx["fronts"][t["id"]]
	var ex: Array = ctx["exclude"] + _tactics.body_rid(t)
	var obj = _tactics.blocker(ctx["space"], self_pos, t["pos"], ex)
	return {
		"front": front,
		"own_side": _tactics.side_of(t["pos"], front, self_pos),
		"line": {
			"clear": obj == null,
			"in_range": self_pos.distance_to(t["pos"]) <= shoot_range,
			"cover": _tactics.object_label(obj) if _tactics.is_cover(obj) else "",
			"blocker": _tactics.object_label(obj),
		},
		"fire": _tactics.fire_positions(ctx, t),
		"flanks": _tactics.flank_sides(ctx, t, front),
		"advance": _tactics.advance_positions(ctx, t),
	}


# --- Sections: the state text Von reads ------------------------------------------------------

## Where the NPC is, whether it is free, what it holds and how hurt it is.
func _situation_text(character, rooms: Array) -> String:
	var room := _room_at(character.global_position, rooms)
	var where := ("in the %s, inside the house" % _room_name(room["type"])) if not room.is_empty() else "outside the house"
	var busy := (" You are busy: %s." % character.interaction_label()) if character.is_busy() else ""
	return "You are %s, holding a %s.%s You are %s." % [
		where, character.current_item().display_name, busy, _health_band(character.damage_taken())]


## How many hostiles the NPC knows of against which allies it has. With none known it says whether
## it is quiet or there is trouble out of sight (`trouble`: there are leads to investigate) — "All
## quiet" must not be said while gunfire is fresh, since the SEARCH situation echoes it.
func _odds_text(hostiles: Array, allies: Array, callouts: Array, trouble: bool) -> String:
	var names: Array = allies.map(func(a): return a["name"])
	for c in callouts:
		if not names.has(c["name"]):
			names.append(c["name"])
	var ally_text := ", ".join(names) if not names.is_empty() else "none"
	if hostiles.is_empty():
		var lead := "All quiet so far."
		if _under_fire():
			lead = "Someone you cannot see is shooting at you."
		elif trouble:
			lead = "There is trouble nearby, out of your sight."
		return "%s Allies near you: %s." % [lead, ally_text]
	var in_sight := hostiles.filter(func(c): return c["visible"]).size()
	return "Known hostiles: %d (%d in sight). Allies near you: %s." % [hostiles.size(), in_sight, ally_text]


## One line per known non-ally contact (hostiles first, up to `max_contacts_in_state`).
func _contacts_text(self_pos: Vector2, known: Array) -> String:
	var others: Array = known.filter(func(c): return not c["ally"] or c["hostile"])
	if others.is_empty():
		return "Nobody else is in sight or known."
	var lines: Array = []
	for c in others.slice(0, max_contacts_in_state):
		lines.append(_contact_line(c, self_pos, known))
	return "\n".join(lines)


## A contact as Von reads it: who, hostility, sight, distance band + bearing + place, movement, aim,
## weapon and visible wounds.
func _contact_line(c: Dictionary, self_pos: Vector2, everyone: Array) -> String:
	var parts: Array = [
		"%s — %s" % [c["name"], ("HOSTILE (%s)" % c["reason"]) if c["hostile"] else "neutral"],
		"in sight" if c["visible"] else "last seen %s" % _recency(c["age"]),
		"%s, %s of you, %s" % [_dist_band(self_pos.distance_to(c["pos"])), _compass(c["pos"] - self_pos), _where(c)],
		_move_text(c, self_pos),
	]
	var aim := _aim_text(c, self_pos, everyone)
	if aim != "":
		parts.append(aim)
	parts.append("holding a %s" % c.get("item", "nothing"))
	var wound := _wound_band(c.get("wound_dmg", 0.0))
	if wound != "":
		parts.append(wound)
	return " — ".join(parts) + "."


## The line between the NPC and hostile `t`: whether each can shoot the other, what blocks it, and
## which other hostiles can see the NPC here.
func _exposure_text(ctx: Dictionary, t: Dictionary, a: Dictionary) -> String:
	var line: Dictionary = a["line"]
	var text := ""
	if line["clear"] and line["in_range"]:
		text = "You have a clear shot at %s from where you stand. You are exposed to their fire." % t["name"]
	elif line["clear"]:
		text = "%s is too far to shoot. They can see you." % t["name"]
	elif line["cover"] != "":
		text = "You are behind cover from %s (the %s): your line to them is blocked." % [t["name"], line["cover"]]
	else:
		text = "A %s is between you and %s: your line to them is blocked." % [line["blocker"], t["name"]]
	if t["visible"] and _aim_text(t, ctx["self_pos"], []) == "aiming at you":
		text += " They are aiming at you."
	var others: Array = _tactics.exposed_to(ctx["space"], ctx["self_pos"], ctx["hostiles"], t["id"], ctx["exclude"])
	if not others.is_empty():
		text += " You are also exposed to the fire of %s." % ", ".join(others)
	return text


## Exposure when under fire from someone the NPC cannot see.
func _unseen_fire_text() -> String:
	if not _under_fire():
		return ""
	return "You are being shot at by someone you cannot see, from the %s; you are exposed to their fire." % _compass(_memory.recall(&"under_fire").get("from", Vector2.ZERO))


## The NPC's allies: where each perceived ally is — and which side of hostile `t` it holds, in `t`'s
## frame — plus what each ally last said on the radio. Empty when it knows of no ally.
func _allies_text(ctx: Dictionary, t: Dictionary, a: Dictionary) -> String:
	var self_pos: Vector2 = ctx["self_pos"]
	var lines: Array = []
	for ally in ctx["allies"]:
		var parts: Array = [
			"%s (ally)" % ally["name"],
			"in sight" if ally["visible"] else "last seen %s" % _recency(ally["age"]),
			"%s of you, %s" % [_compass(ally["pos"] - self_pos), _where(ally)],
		]
		if not t.is_empty():
			var tpos: Vector2 = t["pos"]
			if (ally["pos"] as Vector2).distance_to(tpos) <= flank_ally_radius:
				parts.append("on %s's %s" % [t["name"], SIDE_WORDS[_tactics.side_of(tpos, a["front"], ally["pos"])].trim_prefix("their ")])
			else:
				parts.append("far from %s" % t["name"])
		parts.append(_move_text(ally, self_pos))
		var ally_wound := _wound_band(ally.get("wound_dmg", 0.0))
		if ally_wound != "":
			parts.append(ally_wound)
		lines.append(" — ".join(parts) + ".")
	for c in ctx["callouts"]:
		var status: String = c.get("status", "")
		lines.append("%s (radio, %s): %s%s." % [c["name"], _recency(c["age"]), c.get("label", "?"), ("; " + status) if status != "" else ""])
	return "\n".join(lines)


## A one-line digest of hostile `t`'s flanks: which side the NPC is on and, per other side, whether it
## is open, has a shot and cover, and how long and exposed the route is.
func _flanks_text(t: Dictionary, a: Dictionary) -> String:
	if a["flanks"].is_empty():
		return "Every side of %s is out of reach." % t["name"]
	var parts: Array = []
	for s in a["flanks"]:
		parts.append("%s — %s, %s, %s, %s route" % [SIDE_WORDS[s["side"]], _side_status(s),
			"clear shot" if s["clear_shot"] else "line blocked",
			"cover" if s["cover"] != "" else "in the open",
			_route_text(s["route_len"], s["route_exposed"])])
	return "Flanks on %s (you are on %s): %s." % [t["name"], SIDE_WORDS[a["own_side"]], "; ".join(parts)]


## Being shot at or hit (and from where), gunfire heard nearby (only while no hostile is known — in a
## fight it is just the fight), and any remembered event with a note.
func _awareness_text(self_pos: Vector2, fighting: bool) -> String:
	var out: Array = []
	if _under_fire():
		var uf: Dictionary = _memory.recall(&"under_fire")
		var dir := _compass(uf.get("from", Vector2.ZERO))
		out.append(("You are being hit, from the %s!" if uf.get("hit", false) else "You are under fire: shots are landing near you, from the %s!") % dir)
	for rec in _memory.recall_aged(&"heard_gunfire"):
		if not fighting and rec["age"] <= recency_bands.y:
			out.append("Gunfire heard to the %s, %s." % [_compass(rec["data"]["pos"] - self_pos), _recency(rec["age"])])
			break
	var seen := { &"under_fire": true }
	for entry in _memory.fresh():
		var topic = entry["topic"]
		if seen.has(topic):
			continue
		seen[topic] = true
		var note = entry["data"].get("note", "")
		if note != "":
			out.append(note)
	return "\n".join(out)


# --- Option groups: what Von picks from ------------------------------------------------------

## The COMBAT branch summary: the threat in one line.
func _threat_summary(self_pos: Vector2, hostiles: Array) -> String:
	if hostiles.is_empty():
		if _under_fire():
			return "shots from the %s" % _compass(_memory.recall(&"under_fire").get("from", Vector2.ZERO))
		return ""
	var t: Dictionary = hostiles[0]
	var desc := "%s, %s" % ["in sight" if t["visible"] else "last seen %s" % _recency(t["age"]), _dist_band(self_pos.distance_to(t["pos"]))]
	var aim := _aim_text(t, self_pos, [])
	if aim != "":
		desc += ", " + aim
	if hostiles.size() == 1:
		return "%s: %s, holding a %s" % [t["name"], desc, t.get("item", "nothing")]
	return "%d hostiles; nearest %s: %s" % [hostiles.size(), t["name"], desc]


## Which hostile to fight: one option per known hostile, with what makes it urgent or easy.
func _hostile_group(ctx: Dictionary, hostiles: Array, analyses: Dictionary) -> Dictionary:
	var options: Array = []
	var self_pos: Vector2 = ctx["self_pos"]
	for t in hostiles.slice(0, max_options_per_level):
		var a: Dictionary = analyses[t["id"]]
		# Only what tells the hostiles apart — common facts ("hostile", the usual pistol) blur the match.
		var parts: Array = [
			t["name"],
			"in sight" if t["visible"] else "last seen %s" % _recency(t["age"]),
			"%s, %s of you" % [_dist_band(self_pos.distance_to(t["pos"])), _compass(t["pos"] - self_pos)],
		]
		if (t.get("vel", Vector2.ZERO) as Vector2).length() >= still_speed:
			parts.append(_move_text(t, self_pos))
		var aim := _aim_text(t, self_pos, ctx["allies"])
		if aim != "":
			parts.append(aim)
		if t.get("item", "") != "Pistol":
			parts.append("holding a %s" % t.get("item", "nothing"))
		if t["reason"] == "attacked you":
			parts.append("they attacked you")
		var wound := _wound_band(t.get("wound_dmg", 0.0))
		if wound != "":
			parts.append(wound)
		parts.append("you have a clear shot at them" if a["line"]["clear"] and a["line"]["in_range"] else "your line to them is blocked")
		var fighting := _allies_on(ctx, t)
		if fighting != "":
			parts.append("%s is already on them" % fighting)
		options.append({
			"id": "t_%d" % t["id"], "label": t["name"], "desc": " — ".join(parts),
			"bind": { "target": t["name"], "target_id": t["id"] },
		})
	return { "summary": "", "options": options }


## Where to fight hostile `t` from: this spot, firing spots around them named by place and cover, and an
## ambush in cover. Tactics has already dropped any spot the NPC would reach past a hostile or in the
## open under a hostile's eye.
func _fire_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var f: Dictionary = a["fire"]
	var self_pos: Vector2 = ctx["self_pos"]
	var tpos: Vector2 = t["pos"]
	var options: Array = []
	if not f["here"].is_empty():
		options.append(_spot_option("fire_here", "where you stand", "fire from where you stand" + _room_suffix(self_pos), f["here"], false))
	for s in f["spots"]:
		if options.size() >= max_options_per_level - (0 if f["ambush"].is_empty() else 1):
			break
		var dir := _compass(s["point"] - tpos)
		var place := _spot_place(s, dir)
		var lead := "fire from %s%s" % [place, (", %s of them" % dir) if s["cover"] != "" else ""]
		options.append(_spot_option("fire_" + dir.replace("-", "_"), place, lead, s, true))
	if not f["ambush"].is_empty():
		var amb: Dictionary = f["ambush"]
		var cover: String = amb["cover"] if amb["cover"] != "" else "cover"
		var desc := "wait in ambush behind the %s — you shoot when they show — %s" % [cover, _coming_text(t, self_pos)]
		if not amb["exposed_to"].is_empty():
			desc += " — also exposed to %s" % ", ".join(amb["exposed_to"])
		options.append({ "id": "ambush", "label": "ambush behind the %s" % cover, "desc": desc,
			"params": { "point": amb["point"], "style": &"ambush" }, "tags": { "inside": _is_inside(amb["point"]) } })
	var summary := ""
	if not f["here"].is_empty():
		summary = "from where you stand"
	elif not f["spots"].is_empty():
		summary = "from %s" % _spot_place(f["spots"][0], _compass(f["spots"][0]["point"] - tpos))
	elif not f["ambush"].is_empty():
		summary = "once they show, from an ambush behind cover"
	var wound := _wound_band(t.get("wound_dmg", 0.0))
	if summary != "" and wound != "":
		summary += "; they %s" % wound.replace("looks", "look")
	return { "summary": summary, "options": options }


## One fighting-spot option: its place (`lead`), clear shot, cover, the route there (`moving`: a spot to
## go to rather than where the NPC stands) and other exposure.
func _spot_option(id: String, label: String, lead: String, s: Dictionary, moving: bool) -> Dictionary:
	var parts: Array = [lead]
	parts.append("clear shot" if s["clear_shot"] else "line blocked")
	parts.append(("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open")
	if moving:
		parts.append(_route_text(s["route_len"], s["route_exposed"]) + " route")
	if not s["exposed_to"].is_empty():
		parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
	return { "id": id, "label": label, "desc": " — ".join(parts),
		"params": { "point": s["point"], "style": &"peek_cover" }, "tags": { "inside": _is_inside(s["point"]) } }


## A firing spot named by its place, `dir` being its bearing from the target: "behind the sofa in the
## kitchen" with cover close by, else "the kitchen, north of them" / "outside, north of them".
func _spot_place(s: Dictionary, dir: String) -> String:
	var room := _room_at(s["point"], _rooms)
	if s["cover"] != "":
		return "behind the %s %s" % [s["cover"], ("in the %s" % _room_name(room["type"])) if not room.is_empty() else "outside"]
	return "%s, %s of them" % [("the %s" % _room_name(room["type"])) if not room.is_empty() else "outside", dir]


## Which side to flank hostile `t` from: one option per reachable side other than the NPC's own.
func _flank_group(t: Dictionary, a: Dictionary, rooms: Array) -> Dictionary:
	var tpos: Vector2 = t["pos"]
	var options: Array = []
	var open: Array = []
	for s in a["flanks"]:
		var room := _room_at(s["point"], rooms)
		var place: String = ("in the %s" % _room_name(room["type"])) if not room.is_empty() else "outside the house"
		var parts: Array = [
			"%s — %s of them, %s" % [SIDE_WORDS[s["side"]], _compass(s["point"] - tpos), place],
			_side_status(s),
			"clear shot from there" if s["clear_shot"] else "line blocked from there",
			("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open",
			_route_text(s["route_len"], s["route_exposed"]) + " route",
		]
		if s["heading_toward"]:
			parts.append("they are moving toward that side")
		if not s["exposed_to"].is_empty():
			parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
		if s["ally_lane"] != "":
			parts.append("in %s's line of fire" % s["ally_lane"])
		options.append({
			"id": "side_" + s["side"],
			"label": "%s (%s)" % [SIDE_WORDS[s["side"]], _room_name(room["type"]) if not room.is_empty() else "outside"],
			"desc": " — ".join(parts),
			"params": { "point": s["point"] },
			"tags": { "inside": not room.is_empty(), "held": s["held_by"] != "", "crosses": s["crosses"] != "" },
		})
		if s["held_by"] == "" and s["crosses"] == "":
			open.append(s)
	var inside_open: Array = open.filter(func(s): return not _room_at(s["point"], rooms).is_empty())
	var shot_here: bool = a["line"]["clear"] and a["line"]["in_range"]
	return {
		"summary": _flank_summary(t, a["flanks"], open, rooms, shot_here),
		"summary_inside": _flank_summary(t, a["flanks"], inside_open, rooms, shot_here),
		"options": options,
	}


## The FLANK branch summary over the `open` sides: how many, the best at a glance (Von still makes
## the pick), and whether the NPC already has a shot without moving.
func _flank_summary(t: Dictionary, flanks: Array, open: Array, rooms: Array, shot_here: bool) -> String:
	if flanks.is_empty():
		return ""
	var text := ""
	if open.is_empty():
		text = "every side is taken or out of reach"
	else:
		open.sort_custom(func(x, y): return _flank_rank(x) > _flank_rank(y))
		var best: Dictionary = open[0]
		var best_room := _room_at(best["point"], rooms)
		text = "%d free side%s; best: %s%s, %s route, %s" % [open.size(), "" if open.size() == 1 else "s",
			SIDE_WORDS[best["side"]], (" via the %s" % _room_name(best_room["type"])) if not best_room.is_empty() else " outside",
			_route_text(best["route_len"], best["route_exposed"]), "cover" if best["cover"] != "" else "in the open"]
	return text


## A flank side's status: "route passes X" when getting there walks past a known hostile, "taken by X"
## when an ally holds it, else "free".
func _side_status(s: Dictionary) -> String:
	if s["crosses"] != "":
		return "route passes %s" % s["crosses"]
	return ("taken by %s" % s["held_by"]) if s["held_by"] != "" else "free"


## How good an open flank looks at a glance (for the summary's "best" only — Von makes the pick).
func _flank_rank(s: Dictionary) -> int:
	return int(s["clear_shot"]) * 4 + int(s["cover"] != "") * 2 + int(not s["route_exposed"]) + int(s["route_len"] <= route_buckets.x)


## Punching hostile `t`: one option, offered only while they are point-blank (`_dist_band`'s band), so
## MELEE is never chosen from across a room.
func _melee_group(self_pos: Vector2, t: Dictionary) -> Dictionary:
	var dist := self_pos.distance_to(t["pos"])
	var summary := "they are %s and hold a %s" % [_dist_band(dist), t.get("item", "nothing")]
	var options: Array = []
	if dist <= punch_range * 1.5:
		options.append({ "id": "punch", "label": "punch them", "desc": "punch them — " + summary })
	return { "summary": summary, "options": options }


## How to close in on hostile `t`: part-way along the route (with cover if any) or a straight rush.
func _advance_group(ctx: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var options: Array = []
	for s in a["advance"]:
		var parts: Array = []
		var id := ""
		var label := ""
		if s.get("rush", false):
			id = "rush"
			label = "rush them"
			parts.append("rush straight at where they are" + _room_suffix(s["point"]))
			parts.append(_route_text(s["route_len"], s["route_exposed"]) + " route")
			parts.append("they hold a %s" % t.get("item", "nothing"))
		else:
			id = "advance_half" if s["fraction"] < 0.6 else "advance_close"
			label = "halfway to them" if id == "advance_half" else "close to them"
			parts.append(("advance halfway to them" if id == "advance_half" else "advance most of the way to them") + _room_suffix(s["point"]))
			parts.append(("cover close by (the %s)" % s["cover"]) if s["cover"] != "" else "in the open")
			parts.append("clear shot from there" if s["clear_shot"] else "line blocked from there")
		if not s["exposed_to"].is_empty():
			parts.append("also exposed to %s" % ", ".join(s["exposed_to"]))
		options.append({ "id": id, "label": label, "desc": " — ".join(parts),
			"params": { "point": s["point"] }, "tags": { "inside": _is_inside(s["point"]) } })
	var summary := "they are %s, %s, holding a %s" % [
		_dist_band((ctx["self_pos"] as Vector2).distance_to(t["pos"])), _move_text(t, ctx["self_pos"]), t.get("item", "nothing")]
	var wound := _wound_band(t.get("wound_dmg", 0.0))
	if wound != "":
		summary += ", %s" % wound
	return { "summary": summary, "options": options }


## Where to fall back to: out of sight of every known threat first, then farther away; with cover,
## route and the ally a spot lies toward. Threats are the known hostiles, else where fire came from.
func _retreat_group(ctx: Dictionary, hostiles: Array, known_rooms: Array, dmg: float) -> Dictionary:
	var threats: Array = hostiles.map(func(h): return h["pos"])
	if threats.is_empty() and _under_fire():
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
		if options.size() >= max_options_per_level:
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
			_route_text(s["route_len"], s["route_exposed"]) + " route"]
		options.append({ "id": id, "label": lead.trim_prefix("fall back to ").trim_prefix("back off "), "desc": " — ".join(parts),
			"params": { "point": s["point"] }, "tags": { "inside": _is_inside(s["point"]), "hidden": s["hidden"] } })
	var inside: Array = options.filter(func(o): return o["tags"]["inside"])
	return {
		"summary": _retreat_summary(options, dmg),
		"summary_inside": _retreat_summary(inside, dmg),
		"options": options,
	}


## The RETREAT branch summary over `options` (best first): whether anywhere hides the NPC, the best
## spot, and how hurt it is.
func _retreat_summary(options: Array, dmg: float) -> String:
	if options.is_empty():
		return ""
	var best: Dictionary = options[0]
	return "best: %s, %s; you are %s" % [best["label"],
		"out of their sight" if best["tags"]["hidden"] else "farther from them, still in their sight", _health_band(dmg)]


## What to investigate: lost hostiles (where last seen, and where they were heading), gunfire heard,
## where unseen shots came from, and allies' radio calls for support — freshest first.
func _lead_group(ctx: Dictionary, hostiles: Array) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var leads: Array = []
	for c in _know["lost"]:
		var moving: bool = (c["vel"] as Vector2).length() >= still_speed
		leads.append({ "age": c["age"], "id": "lead_seen_%d" % c["id"], "label": "where you last saw %s" % c["name"],
			"desc": "where you last saw %s — %s, %s — %s route%s" % [c["name"], _recency(c["age"]), _where(c),
				_route_band(_route_len(ctx, c["pos"])), ("; they were moving %s" % _compass(c["vel"])) if moving else ""],
			"point": c["pos"] })
		if moving:
			var ahead: Vector2 = _tactics.snap(ctx["map"], c["pos"] + c["vel"] * minf(c["age"], extrapolate_cap))
			leads.append({ "age": c["age"] + 0.01, "id": "lead_heading_%d" % c["id"], "label": "where %s was heading" % c["name"],
				"desc": "where %s was heading — %s of where you last saw them%s — %s route" % [c["name"], _compass(c["vel"]),
					_room_suffix(ahead), _route_band(_route_len(ctx, ahead))],
				"point": ahead })
	for rec in _memory.recall_aged(&"heard_gunfire"):
		var pos: Vector2 = rec["data"]["pos"]
		leads.append({ "age": rec["age"], "id": "lead_gunfire_%d_%d" % [floori(pos.x / 200.0), floori(pos.y / 200.0)],
			"label": "gunfire to the %s" % _compass(pos - self_pos),
			"desc": "gunfire heard to the %s — %s%s — %s route" % [_compass(pos - self_pos), _recency(rec["age"]),
				_room_suffix(pos), _route_band(_route_len(ctx, pos))],
			"point": _tactics.snap(ctx["map"], pos) })
	if _under_fire() and hostiles.is_empty():
		var from: Vector2 = _memory.recall(&"under_fire").get("from", Vector2.ZERO)
		var origin: Vector2 = _shot_origin(ctx)
		leads.append({ "age": 0.0, "id": "lead_shooter", "label": "where the shots came from",
			"desc": "where the shots at you came from — the %s, just now" % _compass(from), "point": origin })
	for c in ctx["callouts"]:
		if not str(c.get("path", "")).begins_with("combat"):
			continue
		var at: Vector2 = c.get("position", self_pos)
		var status: String = c.get("status", "")
		leads.append({ "age": c["age"], "id": "lead_ally_%d" % c["id"], "label": "support %s" % c["name"],
			"desc": "support %s — %s, %s of you%s — radio %s%s" % [c["name"], c.get("label", "fighting"), _compass(at - self_pos),
				_room_suffix(at), _recency(c["age"]), ("; " + status) if status != "" else ""],
			"point": _tactics.snap(ctx["map"], at) })
	# A lead checked more recently than the event behind it is spent (fresh news there is offered again).
	leads = leads.filter(func(l): return not _memory.age_of(&"checked_lead", "id", l["id"]) < l["age"])
	leads.sort_custom(func(x, y): return x["age"] < y["age"])
	var options: Array = []
	for l in leads.slice(0, max_options_per_level):
		options.append({ "id": l["id"], "label": l["label"], "desc": l["desc"],
			"params": { "point": l["point"], "lead": l["id"] }, "tags": { "inside": _is_inside(l["point"]) } })
	var summary := ""
	if not options.is_empty():
		summary = "%d lead%s (freshest: %s)" % [leads.size(), "" if leads.size() == 1 else "s", options[0]["desc"].get_slice(" — ", 0)]
	return { "summary": summary, "options": options }


## Under fire from someone the NPC cannot see: the one way to find them — toward where the shots came
## from. Empty unless under fire with no hostile known.
func _shooter_group(ctx: Dictionary, hostiles: Array) -> Dictionary:
	if not _under_fire() or not hostiles.is_empty():
		return { "summary": "", "options": [] }
	var from: Vector2 = _memory.recall(&"under_fire").get("from", Vector2.ZERO)
	var origin: Vector2 = _shot_origin(ctx)
	var dir := _compass(from)
	return { "summary": "the shots came from the %s" % dir, "options": [{
		"id": "toward_shots", "label": "toward the shots",
		"desc": "move toward where the shots came from — the %s%s — %s route" % [dir, _room_suffix(origin), _route_band(_route_len(ctx, origin))],
		"params": { "point": origin }, "tags": { "inside": _is_inside(origin) } }] }


## The world point to investigate when under fire from an unseen shooter: `investigate_distance` px
## from the NPC toward where the shots came from, snapped onto the navmesh unless `snapped` is false
## (the retreat group wants the raw direction as a threat position, not a reachable spot).
func _shot_origin(ctx: Dictionary, snapped := true) -> Vector2:
	var from: Vector2 = _memory.recall(&"under_fire").get("from", Vector2.ZERO)
	var p: Vector2 = (ctx["self_pos"] as Vector2) + from.normalized() * investigate_distance
	return _tactics.snap(ctx["map"], p) if snapped else p


## Which known room to search next: not-recently-searched first, then nearest; plus the entrance or
## the house itself while outside.
func _search_group(ctx: Dictionary, known_rooms: Array, rooms: Array) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var here := _room_at(self_pos, rooms)
	var candidates: Array = []
	var unsearched := 0
	for room in known_rooms:
		if not here.is_empty() and room["key"] == here["key"]:
			continue
		var age: float = _memory.age_of(&"visited_room", "key", room["key"])
		var point: Vector2 = _tactics.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		var stale := age > search_memory_ttl
		if stale:
			unsearched += 1
		candidates.append({ "room": room, "age": age, "stale": stale, "point": point, "len": _route_len(ctx, point) })
	candidates.sort_custom(func(x, y):
		if x["stale"] != y["stale"]:
			return x["stale"]
		return x["len"] < y["len"])
	var options: Array = []
	if here.is_empty():
		if _know["entry_point"] != Vector2.ZERO:
			options.append({ "id": "entrance", "label": "the front entrance",
				"desc": "the front entrance — %s route" % _route_band(_route_len(ctx, _know["entry_point"])),
				"params": { "point": _know["entry_point"] }, "tags": { "inside": false } })
		elif known_rooms.is_empty() and not rooms.is_empty():
			var centre := _house_centre(rooms)
			options.append({ "id": "approach", "label": "the house",
				"desc": "head for the house and find a way in — %s route" % _route_band(_route_len(ctx, centre)),
				"params": { "point": _tactics.snap(ctx["map"], centre) }, "tags": { "inside": false } })
	for c in candidates:
		if options.size() >= max_options_per_level:
			break
		var room: Dictionary = c["room"]
		options.append({ "id": "room_%s" % room["key"], "label": "the %s" % _room_name(room["type"]),
			"desc": "the %s — %s — %s route" % [_room_name(room["type"]),
				"unsearched" if c["stale"] else "searched %s" % _recency(c["age"]), _route_band(c["len"])],
			"params": { "point": c["point"], "look_around": true }, "tags": { "inside": true } })
	var summary := "%d of %d known rooms unsearched" % [unsearched, known_rooms.size()]
	if known_rooms.is_empty():
		summary = "find your way into the house and explore it"
	return { "summary": summary, "options": options }


## Unexplored parts of the house (rooms not yet seen), named by direction only — the NPC doesn't know
## what they are. One per compass direction, nearest first, at most two.
func _explore_group(ctx: Dictionary, rooms: Array) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var known: Dictionary = _know["known_room_keys"]
	var by_dir := {}
	for room in rooms:
		if known.has(room["key"]):
			continue
		var point: Vector2 = _tactics.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		var dir := _compass(point - self_pos)
		var dist := self_pos.distance_to(point)
		if not by_dir.has(dir) or dist < by_dir[dir]["dist"]:
			by_dir[dir] = { "room": room, "point": point, "dist": dist }
	var picks: Array = by_dir.values()
	picks.sort_custom(func(x, y): return x["dist"] < y["dist"])
	var options: Array = []
	for p in picks.slice(0, 2):
		var dir := _compass(p["point"] - self_pos)
		options.append({ "id": "explore_" + dir.replace("-", "_"), "label": "unexplored %s" % dir,
			"desc": "an unexplored part of the house to the %s — %s route" % [dir, _route_band(_route_len(ctx, p["point"]))],
			"params": { "point": p["point"], "look_around": true }, "tags": { "inside": true } })
	return { "summary": "explore the house", "options": options }


## The object interactions the NPC knows of: one option per DISTINCT action label, pointing at the
## nearest known object offering it (item-gated). Not capped — Von ranks them against the goal.
func _interaction_group(character, self_pos: Vector2, rooms: Array) -> Dictionary:
	var known_objs: Dictionary = _know["known_object_ids"]
	var nearest := {}  # action label -> nearest known object + its spec (+ squared distance).
	for obj in _know["interactables"]:
		if not is_instance_valid(obj) or not known_objs.has(obj.get_instance_id()):
			continue
		var d: float = obj.global_position.distance_squared_to(self_pos)
		for spec in obj.get_interactions():
			var needed: int = spec.get("requires_item", 0)
			if needed != 0 and not character.has_item(needed):
				continue
			var label: String = spec.get("label", spec.get("id", ""))
			if not nearest.has(label) or d < nearest[label]["d"]:
				nearest[label] = { "obj": obj, "id": spec.get("id", ""), "d": d }
	var options: Array = []
	for label in nearest:
		var obj = nearest[label]["obj"]
		options.append({ "id": "do_%d_%s" % [obj.get_instance_id(), nearest[label]["id"]], "label": label,
			"desc": "%s%s" % [label, _room_suffix(obj.global_position)],
			"params": { "object": obj, "id": nearest[label]["id"] }, "tags": { "inside": _is_inside(obj.global_position) } })
	var labels: Array = nearest.keys()
	var summary := "use furniture: %s%s" % [", ".join(labels.slice(0, 4)).to_lower(), ", …" if labels.size() > 4 else ""]
	return { "summary": summary if not labels.is_empty() else "", "options": options }


## Named places to go: each known room (except this one) and the NPC's starting position.
func _room_group(ctx: Dictionary, known_rooms: Array, rooms: Array) -> Dictionary:
	var here := _room_at(ctx["self_pos"], rooms)
	var options: Array = []
	for room in known_rooms:
		if not here.is_empty() and room["key"] == here["key"]:
			continue
		var point: Vector2 = _tactics.snap(ctx["map"], (room["rect"] as Rect2).get_center())
		options.append({ "id": "room_%s" % room["key"], "label": "the %s" % _room_name(room["type"]), "desc": "the %s" % _room_name(room["type"]),
			"params": { "point": point, "arrive_room": room["key"] }, "tags": { "inside": true } })
	options.append({ "id": "post", "label": "your starting position", "desc": "your starting position",
		"params": { "point": _know["post"] }, "tags": { "inside": _is_inside(_know["post"]) } })
	return { "summary": "", "options": options }


# --- Wording helpers (the bands Von reads) ---------------------------------------------------

## A room type as Von reads it ("kitchen_living" → "kitchen living").
func _room_name(kind) -> String:
	return str(kind).replace("_", " ")


## A distance as a combat band, from the NPC's own reach.
func _dist_band(d: float) -> String:
	if d <= punch_range * 1.5:
		return "point-blank"
	if d <= shoot_range * 0.5:
		return "close, in pistol range"
	if d <= shoot_range:
		return "in pistol range"
	return "too far to shoot"


## How long ago, as a band.
func _recency(age: float) -> String:
	if age <= recency_bands.x:
		return "just now"
	if age <= recency_bands.y:
		return "recently"
	return "a while ago"


## A route length as a band.
func _route_band(length: float) -> String:
	if length <= route_buckets.x:
		return "short"
	if length <= route_buckets.y:
		return "medium"
	return "long"


## A route as Von reads it: "short hidden" / "long exposed".
func _route_text(length: float, exposed: bool) -> String:
	return "%s %s" % [_route_band(length), "exposed" if exposed else "hidden"]


## The navigated route length (px) from the NPC to `p`.
func _route_len(ctx: Dictionary, p: Vector2) -> float:
	return _tactics.path_length(_tactics.route(ctx["map"], ctx["self_pos"], p))


## How a contact is moving, relative to the NPC ("moving west, toward you" / "standing still").
func _move_text(c: Dictionary, self_pos: Vector2) -> String:
	var vel: Vector2 = c.get("vel", Vector2.ZERO)
	var prefix := "" if c.get("visible", false) else "was "
	if vel.length() < still_speed:
		return prefix + "standing still"
	var rel := ""
	var a := absf(vel.angle_to(self_pos - (c["pos"] as Vector2)))
	if a < PI * 0.25:
		rel = ", toward you"
	elif a > PI * 0.75:
		rel = ", away from you"
	return "%smoving %s%s" % [prefix, _compass(vel), rel]


## Whether contact `c` (seen this tick) is coming toward the NPC, for an ambush.
func _coming_text(c: Dictionary, self_pos: Vector2) -> String:
	var vel: Vector2 = c.get("vel", Vector2.ZERO)
	if vel.length() < still_speed:
		return "they are standing still"
	if absf(vel.angle_to(self_pos - (c["pos"] as Vector2))) < PI * 0.25:
		return "they are coming this way"
	return "they are moving elsewhere"


## Who a VISIBLE contact is aiming at — the NPC, or another known character within `aim_cone` of its
## facing — or that it faces away from the NPC. Empty when unknown or unremarkable.
func _aim_text(c: Dictionary, self_pos: Vector2, others: Array) -> String:
	var facing: Vector2 = c.get("facing", Vector2.ZERO)
	if not c.get("visible", false) or facing == Vector2.ZERO:
		return ""
	var cone := deg_to_rad(aim_cone)
	var to_me: Vector2 = self_pos - (c["pos"] as Vector2)
	if absf(facing.angle_to(to_me)) <= cone:
		return "aiming at you"
	for o in others:
		if o["id"] != c["id"] and absf(facing.angle_to((o["pos"] as Vector2) - (c["pos"] as Vector2))) <= cone:
			return "aiming at %s" % o["name"]
	if absf(facing.angle_to(to_me)) >= PI * 0.66:
		return "facing away from you"
	return ""


## The ally (perceived near the target, or calling it on the radio) already fighting hostile `t`.
func _allies_on(ctx: Dictionary, t: Dictionary) -> String:
	for c in ctx["callouts"]:
		if c.get("target_id", 0) == t["id"]:
			return c["name"]
	for a in ctx["allies"]:
		if (a["pos"] as Vector2).distance_to(t["pos"]) <= flank_ally_radius * 0.5:
			return a["name"]
	return ""


## Where a contact is: "in the kitchen, inside the house" / "outside the house".
func _where(c: Dictionary) -> String:
	if not c.get("inside", false):
		return "outside the house"
	var room := _room_name(c.get("room_type", ""))
	return ("in the %s" % room) if room != "" else "inside the house"


## " (in the kitchen)" for a point inside a room, " (outside)" otherwise.
func _room_suffix(p: Vector2) -> String:
	var room := _room_at(p, _rooms)
	return (" (in the %s)" % _room_name(room["type"])) if not room.is_empty() else " (outside)"


## Accumulated damage as a band of how hurt a character is.
func _health_band(dmg: float) -> String:
	if dmg >= critical_threshold:
		return "badly wounded"
	if dmg >= hurt_threshold:
		return "hurt"
	return "unhurt"


## A seen character's visible wound band ("looks hurt"), or "" when unharmed.
func _wound_band(dmg: float) -> String:
	if dmg >= critical_threshold:
		return "looks badly wounded"
	if dmg >= hurt_threshold:
		return "looks hurt"
	return ""


## The 8-wind compass name for a direction vector (screen space, +y down = south).
func _compass(v: Vector2) -> String:
	var idx := int(round(atan2(v.y, v.x) / (TAU / 8.0))) % 8
	return COMPASS[idx + 8 if idx < 0 else idx]




# --- Author-local helpers --------------------------------------------------------------------

## Whether the NPC is currently under fire (a recent incoming/nearby hit) — a read of the memory the
## perception folds hits into. The perception owns the public `under_fire()`; this is the author's copy.
func _under_fire() -> bool:
	return _memory.is_fresh(&"under_fire")


## Whether the NPC was actually hit (not just shot at) within the under-fire window.
func _hit_recently() -> bool:
	return _under_fire() and _memory.recall(&"under_fire").get("hit", false)


## Whether the NPC is still committed to a fight (an `engaged` event is fresh).
func _engaged_fresh() -> bool:
	return _memory.is_fresh(&"engaged")


## The room dict whose rect contains `p`, or empty when `p` is outside every room.
func _room_at(p: Vector2, rooms: Array) -> Dictionary:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return room
	return {}


## Whether a world point lies inside the house (within any room of the decision being built).
func _is_inside(p: Vector2) -> bool:
	return not _room_at(p, _rooms).is_empty()


## The centre of the bounding box enclosing all rooms — "the house" for an NPC that knows no room.
func _house_centre(rooms: Array) -> Vector2:
	var bounds := (rooms[0]["rect"] as Rect2)
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	return bounds.get_center()
