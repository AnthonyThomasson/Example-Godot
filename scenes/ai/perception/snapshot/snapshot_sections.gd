extends RefCounted

## AI PERCEPTION sub-domain — SNAPSHOT SECTIONS. Writes the state text Von reads: the situation, loadout, odds, contact lines,
## exposure, allies, flank digest and awareness lines. A pure read of the event memory, the tactics geometry and the shared
## vocabulary; it holds no state of its own. `agent_snapshot.gd` calls it from `build()`.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")

var _v: SnapshotVocab  ## The shared vocabulary and tuning; see snapshot_vocab.gd.
var _memory: RefCounted   ## The agent's event memory (read-only here); see agent_memory.gd.
var _tactics: RefCounted  ## The combat geometry; see agent_tactics.gd.


## Capture the collaborators the sections read. Called once by `AgentSnapshot.setup()`.
func setup(vocab: SnapshotVocab, memory: RefCounted, tactics: RefCounted) -> void:
	_v = vocab
	_memory = memory
	_tactics = tactics


## Where the NPC is, whether it is free, what it holds and how hurt it is.
func situation_text(character, rooms: Array) -> String:
	var room := SnapshotVocab.room_at(character.global_position, rooms)
	var where := ("in the %s, inside the house" % _v.room_name(room["type"])) if not room.is_empty() else "outside the house"
	var busy := (" You are busy: %s." % character.interaction_label()) if character.is_busy() else ""
	return "You are %s, holding a %s.%s%s You are %s." % [
		where, character.current_item().display_name, busy, _v.own_posture_text(character.posture()),
		_v.health_band(character.damage_taken())]


## The gun's state in the bands Von reads (never a round count): loaded, nearly empty, empty or being
## reloaded; once it runs low, whether spare magazines are carried. Then the grenades carried (`grenades`: the kinds, a frag
## first): "You carry a frag grenade and a stun grenade." Empty without a gun or a grenade.
func loadout_text(character, gun: int, ammo: int, grenades: Array = []) -> String:
	var lines: Array = []
	if ammo >= 0:
		lines.append(_gun_text(character, gun, ammo))
	if not grenades.is_empty():
		lines.append("You carry %s." % " and ".join(grenades.map(func(k): return "a %s grenade" % k)))
	return " ".join(lines)


## The gun's state, as `loadout_text` words it.
func _gun_text(character, gun: int, ammo: int) -> String:
	var noun := _v.gun_noun(character, gun)
	if character.is_reloading():
		return "You are reloading your %s." % noun
	var spares := "You carry spare magazines." if character.spare_magazines() > 0 else "You are out of spare magazines."
	if ammo == 0:
		return "Your %s is empty. %s" % [noun, spares]
	if ammo <= ceili(character.ammo_capacity(gun) * _v.low_ammo_fraction):
		return "Your %s is nearly empty. %s" % [noun, spares]
	return "Your %s is loaded." % noun


## How many hostiles the NPC knows of against which allies it has. With none known it says whether
## it is quiet or there is trouble out of sight (`trouble`: there are leads to investigate) — "All
## quiet" must not be said while gunfire is fresh, since the SEARCH situation echoes it.
func odds_text(hostiles: Array, allies: Array, callouts: Array, trouble: bool) -> String:
	var names: Array = allies.map(func(a): return a["name"])
	for c in callouts:
		if not names.has(c["name"]):
			names.append(c["name"])
	var ally_text := ", ".join(names) if not names.is_empty() else "none"
	if hostiles.is_empty():
		var lead := "All quiet so far."
		if _memory.under_fire():
			lead = "Someone you cannot see is shooting at you."
		elif trouble:
			lead = "There is trouble nearby, out of your sight."
		return "%s Allies near you: %s." % [lead, ally_text]
	var in_sight := hostiles.filter(func(c): return c["visible"]).size()
	return "Known hostiles: %d (%d in sight). Allies near you: %s." % [hostiles.size(), in_sight, ally_text]


## One line per known non-ally contact (hostiles first, up to `max_contacts_in_state`).
func contacts_text(self_pos: Vector2, known: Array) -> String:
	var others: Array = known.filter(func(c): return not c["ally"] or c["hostile"])
	if others.is_empty():
		return "Nobody else is in sight or known."
	var lines: Array = []
	for c in others.slice(0, _v.max_contacts_in_state):
		lines.append(_contact_line(c, self_pos, known))
	return "\n".join(lines)


## The line between the NPC and hostile `t`: whether each can shoot the other, what blocks it, and
## which other hostiles can see the NPC here. `throws` are the kinds of grenade it can throw onto their spot ("You can throw a frag
## grenade onto their spot.").
func exposure_text(ctx: Dictionary, t: Dictionary, a: Dictionary, throws: Array = []) -> String:
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
	if not throws.is_empty():
		text += " You can throw %s onto their spot." % " or ".join(throws.map(func(k): return "a %s grenade" % k))
	if t.get("blind", false):
		text += " %s is blinded by a flash and cannot see you." % t["name"]
	if t["visible"] and _v.aim_text(t, ctx["self_pos"], []) == "aiming at you":
		text += " They are aiming at you."
	var others: Array = _tactics.exposed_to(ctx["space"], ctx["self_pos"], ctx["hostiles"], t["id"], ctx["exclude"])
	if not others.is_empty():
		text += " You are also exposed to the fire of %s." % ", ".join(others)
	return text


## Exposure when under fire from someone the NPC cannot see.
func unseen_fire_text() -> String:
	if not _memory.under_fire():
		return ""
	return "You are being shot at by someone you cannot see, from the %s; you are exposed to their fire." % _v.compass(_memory.under_fire_from())


## The NPC's allies: where each perceived ally is — and which side of hostile `t` it holds, in `t`'s
## frame — plus what each ally last said on the radio. Empty when it knows of no ally.
func allies_text(ctx: Dictionary, t: Dictionary, a: Dictionary) -> String:
	var self_pos: Vector2 = ctx["self_pos"]
	var lines: Array = []
	for ally in ctx["allies"]:
		var parts: Array = [
			"%s (ally)" % ally["name"],
			"in sight" if ally["visible"] else "last seen %s" % _v.recency(ally["age"]),
			"%s of you, %s" % [_v.compass(ally["pos"] - self_pos), _v.where(ally)],
		]
		if not t.is_empty():
			var tpos: Vector2 = t["pos"]
			if (ally["pos"] as Vector2).distance_to(tpos) <= _v.flank_ally_radius:
				parts.append("on %s's %s" % [t["name"], SnapshotVocab.SIDE_WORDS[_tactics.side_of(tpos, a["front"], ally["pos"])].trim_prefix("their ")])
			else:
				parts.append("far from %s" % t["name"])
		parts.append(_v.move_text(ally, self_pos))
		var ally_wound := _v.wound_band(ally.get("wound_dmg", 0.0))
		if ally_wound != "":
			parts.append(ally_wound)
		lines.append(" — ".join(parts) + ".")
	for c in ctx["callouts"]:
		var status: String = c.get("status", "")
		lines.append("%s (radio, %s): %s%s." % [c["name"], _v.recency(c["age"]), c.get("label", "?"), ("; " + status) if status != "" else ""])
	return "\n".join(lines)


## A one-line digest of hostile `t`'s flanks: which side the NPC is on and, per other side, whether it
## is open, has a shot and cover, and how long and exposed the route is.
func flanks_text(t: Dictionary, a: Dictionary) -> String:
	if a["flanks"].is_empty():
		return "Every side of %s is out of reach." % t["name"]
	var parts: Array = []
	for s in a["flanks"]:
		parts.append("%s — %s, %s, %s, %s route" % [SnapshotVocab.SIDE_WORDS[s["side"]], _v.side_status(s),
			"clear shot" if s["clear_shot"] else "line blocked",
			"cover" if s["cover"] != "" else "in the open",
			_v.route_text(s["route_len"], s["route_exposed"])])
	return "Flanks on %s (you are on %s): %s." % [t["name"], SnapshotVocab.SIDE_WORDS[a["own_side"]], "; ".join(parts)]


## Being shot at or hit (and from where), and gunfire heard nearby (only while no hostile is known — in a
## fight it is just the fight).
func awareness_text(self_pos: Vector2, fighting: bool) -> String:
	var out: Array = []
	if _memory.under_fire():
		var uf: Dictionary = _memory.recall(&"under_fire")
		var dir := _v.compass(_memory.under_fire_from())
		out.append(("You are being hit, from the %s!" if uf.get("hit", false) else "You are under fire: shots are landing near you, from the %s!") % dir)
	for rec in _memory.recall_aged(&"heard_gunfire"):
		if not fighting and rec["age"] <= _v.recency_bands.y:
			out.append("Gunfire heard to the %s, %s, %s." % [_v.compass(rec["data"]["pos"] - self_pos), _v.place(rec["data"]["pos"]), _v.recency(rec["age"])])
			break
	return "\n".join(out)


## The COMBAT branch summary: the threat in one line.
func threat_summary(self_pos: Vector2, hostiles: Array) -> String:
	if hostiles.is_empty():
		if _memory.under_fire():
			return "shots from the %s" % _v.compass(_memory.under_fire_from())
		return ""
	var t: Dictionary = hostiles[0]
	var desc := "%s, %s" % ["in sight" if t["visible"] else "last seen %s" % _v.recency(t["age"]), _v.dist_band(self_pos.distance_to(t["pos"]))]
	var aim := _v.aim_text(t, self_pos, [])
	if aim != "":
		desc += ", " + aim
	if hostiles.size() == 1:
		return "%s: %s, holding a %s" % [t["name"], desc, t.get("item", "nothing")]
	return "%d hostiles; nearest %s: %s" % [hostiles.size(), t["name"], desc]


## A contact as Von reads it: who, hostility, sight, distance band + bearing + place, movement, aim,
## weapon and visible wounds.
func _contact_line(c: Dictionary, self_pos: Vector2, everyone: Array) -> String:
	var parts: Array = [
		"%s — %s" % [c["name"], ("HOSTILE (%s)" % c["reason"]) if c["hostile"] else "neutral"],
		"in sight" if c["visible"] else "last seen %s" % _v.recency(c["age"]),
		"%s, %s of you, %s" % [_v.dist_band(self_pos.distance_to(c["pos"])), _v.compass(c["pos"] - self_pos), _v.where(c)],
		_v.move_text(c, self_pos),
	]
	var aim := _v.aim_text(c, self_pos, everyone)
	if aim != "":
		parts.append(aim)
	# A body seen low (and only while it is in sight: the last-seen posture may be stale).
	var low := _v.contact_posture_text(c.get("posture", &"stand")) if c["visible"] else ""
	if low != "":
		parts.append(low)
	if _v.blind_text(c) != "":
		parts.append(_v.blind_text(c))
	parts.append("holding a %s" % c.get("item", "nothing"))
	if c.get("reloading", false):
		parts.append("reloading")
	var wound := _v.wound_band(c.get("wound_dmg", 0.0))
	if wound != "":
		parts.append(wound)
	return " — ".join(parts) + "."
