extends GameTest

## One mechanism (`docs/tactical-entry.md` E18 with the bodies-in-the-way rule of `domain-ai-behavior`): a walk that keeps out
## of a doorway's view still goes round a body at rest it knows of, or is held short of it, and never walks into it. The hall of
## `entry_route_round_door_view_inside`: a big hall with a long, narrow store room off its north wall, whose doorway's view is a
## band down the hall that ends short of the south wall. Gunfire is heard at the hall's east end; the walk there goes round the
## far end of the band on the avoid map (`way` "doors"). A teammate stands still on that way round, below the band: the walker
## goes round it (by the steering map, or held and re-planned), it does not stand pressed against it, once round it it goes back
## to the avoid map, and it gets to the east end.
##
## Scripted Von (INVESTIGATE, then the one lead, the gunfire): the subject is the walk, not the decision. The test requires that
## the walk was a door-avoiding one and that the walker saw the teammate before it got to it.
##
## Switches and props: the teammate is a puppet of the invader side that stands still (the body at rest the scenario is about)
## and cannot die; the gunfire is one shot heard at the hall's east end (a `hit` event nobody known fired, as
## tests/_ai/investigate_probe.gd posts it), first thing in `run`. Nothing else is changed.

const Bump := preload("res://tests/_ai/bump_probe.gd")
const Probe := preload("res://tests/_ai/investigate_probe.gd")
const HALL := Rect2(0, 300, 1000, 600)
const STORE := Rect2(450, 0, 100, 300)
const STORE_DOOR := Vector2(500, 300)
const START := Vector2(100, 450)
const GUNFIRE := Vector2(900, 450)
## On the way round the far end of the store room doorway's view.
const MATE := Vector2(440, 748)


func describe() -> Dictionary:
	return {
		"name": "A walk round a doorway's view goes round a body at rest on it",
		"description": "Walking round the far end of a store room doorway's view, the invader meets a teammate standing on that way round and goes round it or waits short of it, never into it.",
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
	s.actor(&"mate", &"puppet", MATE, { "faction": &"invader", "max_health": 1.0e6, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	Probe.gunfire(GUNFIRE)
	var inv := t.actor(&"inv")
	var mate := t.actor(&"mate")
	var brain := t.controller(&"inv", &"current_act")
	var doors := [false]  # the walk went on the avoid map (an Array: a lambda captures a bool by value)
	var ways := []        # the ways the walk went, in order, each once per change
	var saw := [false]    # the walker saw the teammate while still more than a body's width short of it
	var there := func(): return inv.global_position.x > 750.0
	var pressed := Bump.pressed_watch(inv, mate)
	var stood := [0.0]    # the longest the walker stood pressed against the teammate
	var seen: Dictionary = await Bump.watch(t, [&"inv", &"mate"], 30.0, func():
		var way := str(brain.debug_state().get("loco", {}).get("way", ""))
		doors[0] = doors[0] or way == "doors"
		if ways.is_empty() or ways[-1] != way:
			ways.append(way)
		if not saw[0] and inv.global_position.distance_to(mate.global_position) > 60.0:
			saw[0] = brain.known_contacts_for_display().any(func(c): return c["node"] == mate and c["visible"])
		stood[0] = pressed.call()
		return there.call())
	if not t.require(str(brain.current_act()).begins_with("investigate"), "the invader went to investigate the gunfire (%s)" % brain.current_act()):
		return
	if not t.require(doors[0], "premise: the walk kept out of the store room doorway's view on the avoid map"):
		return
	if not t.require(saw[0], "premise: the walker saw the teammate before it got to it"):
		return
	var bumps: Array = seen["bumps"]
	t.trace("mate_moved", mate.global_position.distance_to(MATE))
	t.check(bumps.is_empty(), "it never walks into the teammate at rest (%s)" % Bump.describe(bumps))
	t.check(stood[0] < Bump.PRESSED_MAX, "it never stands pressed against the teammate (stood %.2f s within %.0f px of it)" % [stood[0], Bump.PRESSED_GAP])
	t.check(mate.global_position.distance_to(MATE) < 3.0, "the teammate is not moved (%.1f px off its spot)" % mate.global_position.distance_to(MATE))
	var rounded := ways.find("round")
	t.check(rounded < 0 or ways.slice(rounded).has("doors"), "once round the teammate it keeps out of the view again (ways %s)" % [ways])
	t.check(there.call(), "the walker gets to the hall's east end (at %s, %s)" % [inv.global_position.round(), brain.current_act()])
