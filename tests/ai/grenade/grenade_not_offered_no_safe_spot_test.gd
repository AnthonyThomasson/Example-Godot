extends GameTest

## G17 (amended): GRENADE is dropped when the thrower itself would be inside the grenade's danger zone and has no way to get safe before the fuse is
## out: no cover that shields a crouched body from the landing spot (G7), and no spot out of the blast's line of sight within reach. It is offered
## when it does. Two walled rooms, the same layout in each: an invader with a frag, a hostile 260 px away (inside a frag's 370 px zone) hidden by
## a piece of furniture across the line. In one room the piece is a coffee table (coverage 30, below a crouched body's 35: it hides the hostile from
## a bullet and lets a lob over, but shields nobody) and the room has nothing else: no GRENADE. In the other it is a couch (45) a few steps away:
## GRENADE is offered. Scripted Von; the NPCs walk (they are not held) because "in time" depends on being able to move.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const BARE_N := Vector2(100, 150)
const BARE_H := Vector2(360, 150)
const COVER_N := Vector2(100, 450)
const COVER_H := Vector2(360, 450)


func describe() -> Dictionary:
	return {
		"name": "A grenade is not offered when the thrower could not get safe from it",
		"description": "An invader 260 px from a hidden hostile with only a coffee table (no shield) near gets no GRENADE; the same invader with a couch a few steps away, behind which it can crouch, does.",
		"tags": ["ai", "grenade", "combat", "cover", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	# Two rooms with a wall between and no door, one outer door each at the far end (over 600 px from the invaders: out of reach in a fuse).
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 900, 300) },
		{ "key": "south", "type": "kitchen", "rect": Rect2(0, 300, 900, 300) },
	], [{ "pos": Vector2(880, 0), "width": 60.0 }, { "pos": Vector2(880, 600), "width": 60.0 }])
	s.object(&"table", "coffee_table", Vector2(230, 150))
	s.object(&"couch", "sofa", Vector2(230, 450))
	Flank.rules(s, [{ "pick": "combat" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	for pair in [[&"bare_n", BARE_N, BARE_H, &"bare_h"], [&"cover_n", COVER_N, COVER_H, &"cover_h"]]:
		s.actor(pair[0], &"invader", pair[1], { "facing": Vector2.RIGHT })
		s.set_props(pair[0], "GoalController", { "max_commit_time": 0.4, "tactic_interval": 0.4, "decide_interval": 0.4 })
		Probe.hostile(s, pair[3], pair[2], pair[1])


func run(t: TestContext) -> void:
	for id in [&"bare_n", &"cover_n"]:
		Probe.arm(t.actor(id), 0, 1)
	if not t.require(Probe.count(t.actor(&"bare_n"), Probe.FRAG) == 1 and Probe.count(t.actor(&"cover_n"), Probe.FRAG) == 1, "both invaders carry a frag grenade"):
		return
	var seen := { &"bare": [], &"cover": [] }  # the tactic level offered at each frame the invader was inside the zone
	var pairs := { &"bare": [&"bare_n", &"bare_h"], &"cover": [&"cover_n", &"cover_h"] }
	var end := t.time + 8.0
	while t.time < end:
		for key in pairs:
			var n := t.actor(pairs[key][0])
			var h := t.actor(pairs[key][1])
			var offered := Probe.offered(t.controller(pairs[key][0], &"current_act"))
			if not offered.is_empty() and n.global_position.distance_to(h.global_position) <= Probe.FRAG_ZONE - 20.0:
				seen[key].append(offered)
		await t.frames(1)
	var real := func(key: StringName) -> Array: return seen[key].filter(func(o): return o.has("engage") or o.has("advance"))
	if not t.require(real.call(&"bare").size() >= 30 and real.call(&"cover").size() >= 30, "set-up: both invaders were deciding inside the zone (%d and %d frames)" % [real.call(&"bare").size(), real.call(&"cover").size()]):
		return
	t.check(seen[&"cover"].any(func(o): return o.has("grenade")), "the invader with a couch at hand is offered GRENADE")
	t.check(not seen[&"bare"].any(func(o): return o.has("grenade")), "the invader with only a coffee table (and no way out of line) is never offered it, though the hostile is hidden and in range")
	t.check(not t.happened(&"throw"), "and nothing was thrown")
