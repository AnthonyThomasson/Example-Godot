extends GameTest

## Issue #53, one mechanism: a body standing on the spot an NPC is heading for. An invader (scripted Von: ENTER the
## Terrace house's back door) walks to its stack slot, and a teammate that is not on the radio stands on that very spot.
## The invader does not walk into the teammate or move it; it stops short, and ends its walk at a free spot near the slot
## (`Locomotion`: a body on the destination).
##
## Switches and props: the teammate is a puppet that stands still (the body at rest the scenario is about), cannot die,
## and is put on the invader's slot once the invader has chosen it (the slot is not known before), while the invader is
## still out in the garden; nothing else is changed.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Bump := preload("res://tests/_ai/bump_probe.gd")

const START := Vector2(990, 330)
## How far from the slot (px, centre to centre) still counts as "near it": the next slot along the wall is 34 px away.
const NEAR_SLOT := 70.0


func describe() -> Dictionary:
	return {
		"name": "An NPC whose spot is taken stops at a free spot near it",
		"description": "A teammate stands on the invader's stack slot; the invader ends its walk at a free spot beside it, without walking into or moving it.",
		"tags": ["ai", "navigation", "character", "entry", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	s.von_script([{ "pick": "enter" }, { "pick": Entry.BACK["id"] }])
	s.actor(&"inv", &"invader", START)
	s.actor(&"mate", &"puppet", Vector2(1000, 450), { "faction": &"invader", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var mate := t.actor(&"mate")
	var brain := Entry.brain(t, &"inv")
	var has_slot := func(): return Entry.entry(brain).get("stack_point", null) is Vector2
	if not t.require(await t.until(has_slot, 10.0), "the invader chose the back door and its slot (%s, %s)" % [brain.current_act(), Entry.entry(brain)]):
		return
	var slot: Vector2 = Entry.entry(brain)["stack_point"]
	if not t.require(inv.global_position.distance_to(slot) > 60.0, "premise: the invader is still away from its slot (%.0f px)" % inv.global_position.distance_to(slot)):
		return
	mate.global_position = slot
	await t.frames(1)
	# Where the walk to the slot ended: the invader's position when its entry leaves the `approach` phase (it has stacked).
	var st := { "rest": Vector2.INF }
	var seen: Dictionary = await Bump.watch(t, [&"inv", &"mate"], 20.0, func():
		if String(Entry.entry(brain).get("phase", "")) not in ["", "approach"]:
			st["rest"] = inv.global_position
			return true
		return false)
	var bumps: Array = seen["bumps"]
	var rest: Vector2 = st["rest"]
	t.trace("mate_moved", mate.global_position.distance_to(slot))
	t.check(bumps.is_empty(), "it never walks into the teammate on its slot (%s)" % Bump.describe(bumps))
	t.check(mate.global_position.distance_to(slot) < 3.0, "the teammate is not moved (%.1f px off the slot)" % mate.global_position.distance_to(slot))
	if not t.check(rest != Vector2.INF, "it ends its walk to the slot (at %s, %.0f px from the slot, phase %s)" % [inv.global_position.round(), inv.global_position.distance_to(slot), Entry.entry(brain).get("phase", "")]):
		return
	t.check(rest.distance_to(slot) <= NEAR_SLOT, "at a spot near the slot (%.0f px from it)" % rest.distance_to(slot))
	t.check(rest.distance_to(mate.global_position) > Bump.RADIUS * 2.0 + Bump.CONTACT_TOL, "and free: not touching the teammate (%.1f px apart)" % rest.distance_to(mate.global_position))
