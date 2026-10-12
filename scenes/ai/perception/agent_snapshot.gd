extends RefCounted

## AI PERCEPTION sub-domain — the SNAPSHOT AUTHOR. The BUILD half of perception: given what the NPC
## currently knows (contacts, memory, learned house knowledge) and the combat geometry, it writes the
## decision SNAPSHOT the planner walks — named boolean `facts` the tree gates on, named state `sections`
## Von reads, and named option `groups` (places and things with the attributes a choice turns on). It is
## a pure transform: it reads the event memory and the tactics module, holds no state between calls, and
## never writes memory, decides or picks. The work is split three ways under `snapshot/`: the shared vocabulary and tuning
## (`vocab`), the state text (`_sections`) and the option groups (`_options`); this file assembles them. `agent_perception.gd` (the SEE half) owns it, like it owns
## vision / hostility / memory / tactics, and calls `build()` once per decision.
##
## Everything Von reads is worded for a CLASSIFIER that picks the option whose text best matches the
## state and cannot do arithmetic: distances, routes and ages are BANDS ("in pistol range", "short
## route", "recently"); each option carries the facts that distinguish it from its siblings, in a
## fixed order; there are NO negations (an encoder reads "no cover" as "cover" — say "in the open",
## "line blocked", "free", "unsearched"); and the state uses the same canonical phrases the decision
## tree's situation descriptions are written in, so a fact in the state lights up the option it argues
## for. Options are places and things, never verbs — the decision tree decides what to do at them.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const SnapshotSections = preload("res://scenes/ai/perception/snapshot/snapshot_sections.gd")
const SnapshotOptions = preload("res://scenes/ai/perception/snapshot/snapshot_options.gd")

## The shared vocabulary and tuning. The perception's apply_config() sets the tunables here (like it does on its other modules).
var vocab := SnapshotVocab.new()
var _sections := SnapshotSections.new()  ## The state text; see snapshot_sections.gd.
var _options := SnapshotOptions.new()    ## The option groups; see snapshot_options.gd.
var _memory: RefCounted   ## The agent's event memory (read-only here); see agent_memory.gd.
var _tactics: RefCounted  ## The combat geometry; see agent_tactics.gd.


## Capture the collaborators the author reads: the event memory and the combat geometry. Called once by
## the perception in its setup(), after it has built both. The config fields are set directly by the
## perception's apply_config() (like the other modules), so there is no separate configure step.
func setup(memory: RefCounted, tactics: RefCounted) -> void:
	_memory = memory
	_tactics = tactics
	_sections.setup(vocab, memory, tactics)
	_options.setup(vocab, memory, tactics)


## BUILD pass — run at the start of each decision. Assemble the snapshot the decision planner walks,
## from what the agent currently sees and remembers (NOT from ground truth): `goal` is the behaviour
## string Von ranks against; `activity` is the behaviour's line for what the NPC is doing now. The
## perception hands in the knowledge this reads over: `known` (its `contacts()`), `callouts`, and
## `knowledge` (learned rooms/objects, interactables, the NPC's post and entry point, and lost
## hostiles — see the perception's `sense()`). Returns { facts, sections, sections_per_target, options }.
func build(character, rooms: Array, goal: String, activity: String, known: Array, callouts: Array, knowledge: Dictionary) -> Dictionary:
	vocab.rooms = rooms
	_options.know = knowledge
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
		ctx["fronts"][h["id"]] = _tactics.front_angle(h, self_pos, h["visible"] or h["age"] <= vocab.recency_bands.y)
	var known_rooms: Array = knowledge["known_rooms"]

	# Per known hostile: the combat geometry, the option groups and the sections that follow from it.
	var per_target := {}
	var per_sections := {}
	var analyses := {}
	for t in hostiles.slice(0, vocab.max_options_per_level):
		var a := _analyze(ctx, t)
		analyses[t["id"]] = a
		per_target[t["id"]] = {
			"fire_positions": _options.fire_group(ctx, t, a),
			"flank_sides": _options.flank_group(t, a, rooms),
			"advance_positions": _options.advance_group(ctx, t, a),
			"melee": _options.melee_group(self_pos, t),
		}
		per_sections[t["id"]] = {
			"exposure": _sections.exposure_text(ctx, t, a),
			"flanks": _sections.flanks_text(t, a),
			"allies": _sections.allies_text(ctx, t, a),
		}

	var primary: Dictionary = hostiles[0] if not hostiles.is_empty() else {}
	var line: Dictionary = analyses[primary["id"]]["line"] if not primary.is_empty() else {}
	var leads := _options.lead_group(ctx, hostiles)
	var dmg: float = character.damage_taken()
	# Rounds in the gun it fights with (-1 without one): the AI shoots, reloads and plans around it.
	var gun: int = character.gun_slot()
	var ammo: int = character.ammo(gun) if gun >= 0 else -1
	var facts := {
		"hostile_known": not hostiles.is_empty(),
		"hostile_visible": hostiles.any(func(c): return c["visible"]),
		"threat_known": not hostiles.is_empty() or _under_fire(),
		"has_gun": gun >= 0,
		"gun_loaded": ammo > 0 and not character.is_reloading(),
		"weapon_empty": ammo == 0,
		"weapon_low": ammo >= 0 and ammo <= ceili(character.ammo_capacity(gun) * vocab.low_ammo_fraction),
		"can_reload": gun >= 0 and character.can_reload(gun),
		"under_fire": _under_fire(),
		"hit_recently": _hit_recently(),
		"engaged": _engaged_fresh(),
		"leads": not leads["options"].is_empty(),
		"hurt": dmg >= vocab.hurt_threshold,
		"critical": dmg >= vocab.critical_threshold,
		"inside": not SnapshotVocab.room_at(self_pos, rooms).is_empty(),
		"exposed": line.get("clear", false) or (primary.is_empty() and _under_fire()),
		"in_cover": line.get("cover", "") != "",
		"crouched": character.posture() == &"crouch",
	}
	var sections := {
		"goal": fill_goal(goal, character),
		"situation": _sections.situation_text(character, rooms),
		"loadout": _sections.loadout_text(character, gun, ammo),
		"current": ("Current activity: %s." % activity) if activity != "" else "",
		"odds": _sections.odds_text(hostiles, allies, ctx["callouts"], not leads["options"].is_empty()),
		"contacts": _sections.contacts_text(self_pos, known),
		"exposure": per_sections[primary["id"]]["exposure"] if not primary.is_empty() else _sections.unseen_fire_text(),
		"allies": per_sections[primary["id"]]["allies"] if not primary.is_empty() else _sections.allies_text(ctx, {}, {}),
		"flanks": per_sections[primary["id"]]["flanks"] if not primary.is_empty() else "",
		"awareness": _sections.awareness_text(self_pos, not hostiles.is_empty()),
	}
	var options := {
		"per_target": per_target,
		"threat": { "summary": _sections.threat_summary(self_pos, hostiles) },
		"hostiles": _options.hostile_group(ctx, hostiles, analyses),
		"reload": _options.reload_group(character, gun),
		"retreat_positions": _options.retreat_group(ctx, hostiles, known_rooms, dmg),
		"leads": leads,
		"shooter": _options.shooter_group(ctx, hostiles),
		"search_rooms": _options.search_group(ctx, known_rooms, rooms),
		"explore": _options.explore_group(ctx, rooms),
		"interactions": _options.interaction_group(character, self_pos, rooms),
		"rooms": _options.room_group(ctx, known_rooms, rooms),
	}
	return { "facts": facts, "sections": sections, "sections_per_target": per_sections, "options": options,
		"gun": vocab.gun_noun(character, gun) }


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
			"in_range": self_pos.distance_to(t["pos"]) <= vocab.shoot_range,
			"cover": _tactics.object_label(obj) if _tactics.is_cover(obj) else "",
			"blocker": _tactics.object_label(obj),
		},
		"fire": _tactics.fire_positions(ctx, t),
		"flanks": _tactics.flank_sides(ctx, t, front),
		"advance": _tactics.advance_positions(ctx, t),
	}


## The goal text with `{gun}` replaced by what `character` calls its gun ("shoot them with your {gun}" reads
## "...your pistol" or "...your assault rifle"), so one goal serves every weapon.
func fill_goal(goal: String, character) -> String:
	return goal.replace("{gun}", vocab.gun_noun(character, character.gun_slot()))


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
