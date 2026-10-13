extends GameTest

## G17, when GRENADE is offered: only against a hostile that is hidden from the NPC's line of fire, within throw range
## (450 px), with a clear path for the lob. A hostile in the open, in the NPC's line of fire, gets no GRENADE (it is shot);
## a hostile behind a desk does; the same one pulled back out of throw range does not. Two walled rooms, scripted Von.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const OPEN_N := Vector2(100, 150)
const OPEN_H := Vector2(500, 150)
const HIDE_N := Vector2(100, 450)
const HIDE_H := Vector2(500, 450)
const HIDE_FAR := Vector2(840, 450)  ## 740 px off, past the throw range


func describe() -> Dictionary:
	return {
		"name": "A hostile in the line of fire gets no grenade",
		"description": "In one room an invader with a frag has a clear shot at a hostile: no GRENADE, but ENGAGE. In the next the hostile hides behind a desk: GRENADE is offered; pulled back out of throw range it is not.",
		"tags": ["ai", "grenade", "combat", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	# Two rooms with a wall between and no door, so neither pair sees the other; one outer door each, far from the action.
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 900, 300) },
		{ "key": "south", "type": "kitchen", "rect": Rect2(0, 300, 900, 300) },
	], [{ "pos": Vector2(880, 0), "width": 60.0 }, { "pos": Vector2(880, 600), "width": 60.0 }])
	s.object(&"desk", "desk", Vector2(330, 450))
	Flank.rules(s, [{ "pick": "combat" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	Flank.npc(s, &"open_n", OPEN_N, {}, &"invader", OPEN_H)
	Probe.hostile(s, &"open_h", OPEN_H, OPEN_N)
	Flank.npc(s, &"hide_n", HIDE_N, {}, &"invader", HIDE_H)
	Probe.hostile(s, &"hide_h", HIDE_H, HIDE_N)


func run(t: TestContext) -> void:
	for id in [&"open_n", &"hide_n"]:
		Probe.arm(t.actor(id), 0, 1)
	if not t.require(Probe.count(t.actor(&"open_n"), Probe.FRAG) == 1 and Probe.count(t.actor(&"hide_n"), Probe.FRAG) == 1, "both invaders carry a frag grenade"):
		return
	var open_brain := t.controller(&"open_n", &"current_act")
	var hide_brain := t.controller(&"hide_n", &"current_act")
	if not t.require(await Flank.settle(t, open_brain) and await Flank.settle(t, hide_brain), "both decide"):
		return
	var open_offer := Probe.offered(open_brain)
	t.check(open_offer.has("engage"), "with a clear shot the invader is offered ENGAGE (%s)" % str(open_offer))
	t.check(not open_offer.has("grenade"), "but no GRENADE: the hostile is in its line of fire (%s)" % str(open_offer))
	var hide_offer := Probe.offered(hide_brain)
	t.check(hide_offer.has("grenade"), "against the hostile hidden behind the desk GRENADE is offered (%s)" % str(hide_offer))

	t.actor(&"hide_h").global_position = HIDE_FAR
	await Flank.settle(t, hide_brain)
	t.check(not Probe.offered(hide_brain).has("grenade"), "the same hostile 740 px away is out of throw range: no GRENADE (%s)" % str(Probe.offered(hide_brain)))
