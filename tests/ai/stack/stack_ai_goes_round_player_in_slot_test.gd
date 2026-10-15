extends GameTest

## Issue #53 (E16 with E2): the human stands still in its own stack slot, against the wall, and an AI teammate comes to the
## slot nearer the door from the far side of it. The human is in the way along the wall, but the open floor out from the
## wall is free: the AI goes round the human (out from the wall and back in), takes its slot and radios `ready`. It never
## walks into the human or moves it, and it never stands still for `STILL_CAP` s or more on the way (a stop short of the
## human, a moment's wait and a new plan within 5 s is the most it may do; it never waits for ever).
##
## The match is built the way `main.gd` builds one (`tests/_ai/match_world_probe.gd`: the house, its navmesh and re-baker,
## then the NPC and the human in the same frame, in a world of its own), because a test world waits for its navigation
## maps before an actor spawns and a match does not. The human is the player's character with the player's controller (no
## input: it stands still) and its stack radio as `MatchSpawner.bind_player` gives it. The AI is held where it starts
## (speed 0) until the human stands in its slot: the premise is an AI arriving at a stack the human is already in.
## Scripted Von (ENTER the back door) and the shared entry switches; nothing else changed.

const Bump := preload("res://tests/_ai/bump_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Match := preload("res://tests/_ai/match_world_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")

## The AI starts against the back wall well past where the second slot will be (the far side of the human from the door).
const AI_START := Vector2(872, -10)
## The human starts near the door, on the AI's side of it.
const HUMAN_START := Vector2(905, 250)
## Moving less than this (px) is standing still.
const STILL_PX := 4.0
## The longest the AI may stand still on its way to its slot (s): a stop, a wait and a new plan within 5 s.
const STILL_CAP := 5.0
## How long (s) the AI gets to reach its slot once let go: about 250 px of walking round the human at 150 px/s (under
## 2 s), plus one stop, wait and re-plan (`STILL_CAP`), plus the walk from wherever the re-plan takes it, with room to spare.
const REACH_S := 14.0
## How far (px) the human may be moved: not at all, beyond the jitter of a body at rest.
const HUMAN_MOVE_MAX := 2.0


func describe() -> Dictionary:
	return {
		"name": "An AI goes round the human standing in its stack slot",
		"description": "In a match built as main.gd builds one, the human holds slot 2 against the wall; the AI coming from beyond it goes round it to slot 1, never walks into it or moves it, and never stands for 5 s.",
		"tags": ["ai", "entry", "stack", "scripted", "navigation"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Entry.rules(s, Entry.BACK)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var layout := TestSetup.new()
	Maps.house(layout, false)
	var m := Match.build(layout, t.world, [AI_START], HUMAN_START)
	var ai: Node2D = m["npcs"][0]
	var me: Node2D = m["human"]
	var stack: Node = m["stack"]
	var brain: Node = TestContext.controller_of(ai)
	ai.set("speed", 0.0)  # Held until the human stands in its slot (the premise).
	if not t.require(stack != null, "the human has a stack radio (MatchSpawner.bind_player)"):
		return
	if not t.require(await t.until(func(): return Stack.mine(stack) == 2, 20.0), "the human was reserved slot 2 behind the AI (act %s)" % brain.current_act()):
		return
	t.expect_eq(int(brain.debug_entry().get("slot", 0)), 1, "the AI holds slot 1")
	var mine := Stack.slot_point(stack, 2)
	var target := Stack.slot_point(stack, 1)
	t.check(Entry.beside_door(door, mine), "slot 2 is against the wall beside the door (%s)" % mine)
	t.check(absf(Entry.lateral(door, AI_START)) > absf(Entry.lateral(door, mine)) + 40.0 and signf(Entry.lateral(door, AI_START)) == signf(Entry.lateral(door, mine)),
			"the AI starts beyond the human's slot along the wall (lateral %.0f vs %.0f)" % [Entry.lateral(door, AI_START), Entry.lateral(door, mine)])
	# The human steps into its slot and stands there; the AI is let go once its track of the human is at rest.
	me.global_position = mine
	await t.seconds(1.0)
	ai.set("speed", 150.0)
	var human_at: Vector2 = me.global_position
	# Lambdas capture plain values by copy: the per-frame state lives in one Dictionary.
	var st := { "anchor": ai.global_position, "anchor_t": t.time, "longest": 0.0, "longest_at": Vector2.INF, "moved": 0.0,
			"held_max": 0.0, "ways": {} }
	var sample := func() -> bool:
		var p: Vector2 = ai.global_position
		if p.distance_to(st["anchor"]) > STILL_PX:
			st["anchor"] = p
			st["anchor_t"] = t.time
		elif t.time - float(st["anchor_t"]) > float(st["longest"]):
			st["longest"] = t.time - float(st["anchor_t"])
			st["longest_at"] = p
		st["moved"] = maxf(float(st["moved"]), me.global_position.distance_to(human_at))
		var loco: Dictionary = brain.debug_state().get("loco", {})
		st["held_max"] = maxf(float(st["held_max"]), float(loco.get("held_for", 0.0)))
		st["ways"][str(loco.get("way", "?"))] = true
		t.trace("ai_to_slot", p.distance_to(target))
		t.trace("ai_to_human", p.distance_to(me.global_position))
		t.trace("ai_out", Entry.outward(door, p))
		return not Match.calls(t, ai, "ready").is_empty()
	var seen := await Bump.watch(t, [ai, me], REACH_S, sample)
	var ready := Match.calls(t, ai, "ready")
	var into_me := (seen["bumps"] as Array).filter(func(b): return b["walker"] == StringName(ai.name))
	t.check(not ready.is_empty(), "the AI reached slot 1 and radioed ready within %.0f s (phase %s at %s, %.0f px from its slot, ways %s)" % [REACH_S,
			brain.debug_entry().get("phase", "?"), ai.global_position, ai.global_position.distance_to(target), (st["ways"] as Dictionary).keys()])
	if not ready.is_empty():
		t.check(ai.global_position.distance_to(target) <= 12.0, "it stands in slot 1 (%.0f px off)" % ai.global_position.distance_to(target))
	t.check(into_me.is_empty(), "the AI never walks into the human (%s)" % Bump.describe(into_me))
	t.check(float(st["moved"]) <= HUMAN_MOVE_MAX, "the human was not moved (%.1f px)" % float(st["moved"]))
	t.check(float(st["longest"]) < STILL_CAP, "the AI never stood still %.0f s or more on its way (%.1f s at %s, held %.1f s at most)" % [STILL_CAP,
			float(st["longest"]), st["longest_at"], float(st["held_max"])])
