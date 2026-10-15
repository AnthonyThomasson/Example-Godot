extends GameTest

## One mechanism (`docs/tactical-entry.md` E18 with the bodies-in-the-way rule of `domain-ai-behavior`): a walk that keeps out
## of a doorway's view and finds a body at rest on its destination stops short of it, then takes a free spot beside it; it
## never walks into it. The hall of `entry_route_round_door_view_inside`: a big hall with a long, narrow store room off its north
## wall, whose doorway's view is a band down the hall that ends short of the south wall. Gunfire is heard just east of the
## band's far end; the walk there goes round the far end on the avoid map (`way` "doors"). A teammate stands still on the spot.
##
## Scripted Von (INVESTIGATE, then the one lead, the gunfire): the subject is the walk, not the decision. The test requires that
## the walk was a door-avoiding one and that the walker saw the teammate before it got to it.
##
## Switches and props: the teammate is a puppet of the invader side that stands still (the body at rest the scenario is about)
## and cannot die; the gunfire is one shot heard on the teammate's spot (a `hit` event nobody known fired, as
## tests/_ai/investigate_probe.gd posts it), first thing in `run`. Nothing else is changed.

const Bump := preload("res://tests/_ai/bump_probe.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const HALL := Rect2(0, 300, 1000, 600)
const STORE := Rect2(450, 0, 100, 300)
const STORE_DOOR := Vector2(500, 300)
const START := Vector2(100, 450)
## The destination, just east of the view's far end: the plain way there runs through the view.
const GOAL := Vector2(700, 700)
## A walk that ends beside a taken destination ends this close to it (px): the free spot's rings reach 96 px out.
const BESIDE := 110.0


func describe() -> Dictionary:
	return {
		"name": "A walk round a doorway's view stops short of a body on its destination",
		"description": "Walking round the far end of a store room doorway's view to a spot a teammate stands on, the invader stops short of it and takes a free spot beside it, never walking into it.",
		"tags": ["ai", "navigation", "character", "door_view", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "hallway", "rect": HALL },
		{ "key": "store", "type": "bedroom", "rect": STORE },
	], [
		{ "pos": STORE_DOOR, "width": 60.0 },
		{ "pos": Vector2(0, 600), "width": 80.0 },  # the hall's door to the garden
	])
	s.von_script([{ "pick": "investigate" }])
	s.actor(&"inv", &"invader", START, { "facing": Vector2.RIGHT })
	s.actor(&"mate", &"puppet", GOAL, { "faction": &"invader", "max_health": 1.0e6, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	Probe.gunfire(GOAL)
	var inv := t.actor(&"inv")
	var mate := t.actor(&"mate")
	var brain := t.controller(&"inv", &"current_act")
	var doors := [false]  # the walk went on the avoid map (an Array: a lambda captures a bool by value)
	var saw := [false]    # the walker saw the teammate while still more than a body's width short of it
	var stood := [0.0]    # the longest the walker stood pressed against the teammate
	var went := [false]   # the walker set off to investigate the gunfire
	var done := [false]   # that walk ended (the move arrived and the NPC decided again)
	var pressed := Bump.pressed_watch(inv, mate)
	var seen: Dictionary = await Bump.watch(t, [&"inv", &"mate"], 25.0, func():
		doors[0] = doors[0] or str(brain.debug_state().get("loco", {}).get("way", "")) == "doors"
		if not saw[0] and inv.global_position.distance_to(mate.global_position) > 60.0:
			saw[0] = brain.known_contacts_for_display().any(func(c): return c["node"] == mate and c["visible"])
		stood[0] = pressed.call()
		var investigating := str(brain.current_act()).begins_with("investigate")
		went[0] = went[0] or investigating
		done[0] = done[0] or (went[0] and not investigating)
		return done[0])
	if not t.require(went[0], "the invader went to investigate the gunfire (%s)" % brain.current_act()):
		return
	if not t.require(doors[0], "premise: the walk kept out of the store room doorway's view on the avoid map"):
		return
	if not t.require(saw[0], "premise: the walker saw the teammate before it got to it"):
		return
	var bumps: Array = seen["bumps"]
	var gap: float = inv.global_position.distance_to(GOAL)
	t.check(bumps.is_empty(), "it never walks into the teammate on its destination (%s)" % Bump.describe(bumps))
	t.check(stood[0] < Bump.PRESSED_MAX, "it never stands pressed against the teammate (stood %.2f s within %.0f px of it)" % [stood[0], Bump.PRESSED_GAP])
	t.check(mate.global_position.distance_to(GOAL) < 3.0, "the teammate is not moved (%.1f px off its spot)" % mate.global_position.distance_to(GOAL))
	t.check(done[0] and gap < BESIDE, "the walk ends beside the taken destination (%.0f px from it, %s)" % [gap, brain.current_act()])
