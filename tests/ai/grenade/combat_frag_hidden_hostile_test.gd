extends GameTest

## G17, the GRENADE tactic: an invader that carries a frag and knows a hostile hidden from its line of fire (behind low cover
## that stops a bullet but not a lob), within throw range with a clear path, throws the frag onto its spot instead of shooting at the
## cover. The whole pipeline runs: vision (it sees the hostile over the sofa), the snapshot, real Von at every level, the throw primitive, the radio.
##
## The world is a bare hall with a sofa and a coffee table across it, wall to wall, so no firing spot and no flank has a line to the
## hostile behind them: the throw is the natural pick. A `require` that the AI took the GRENADE path comes first, so a different Von
## choice reads as a set-up finding.
##
## The invader starts 420 px from the hostile, outside a frag's 370 px zone, so it needs no cover from its own grenade (the thrower inside its
## own zone, taking cover, is `combat_frag_take_cover`). Premises: the hostile is a household *puppet* that cannot be killed and never shoots (the thing to be hidden from); the invader is
## armed with one frag here because the test world keeps the default inventory, the way Main arms a spawn.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const INVADER_AT := Vector2(380, 50)
const HOSTILE_AT := Vector2(800, 50)


func describe() -> Dictionary:
	return {
		"name": "An invader frags a hostile hidden behind cover",
		"description": "A hostile stands behind a sofa and a coffee table that fill a hall: the invader with a frag, 420 px off, takes the GRENADE tactic, throws the frag onto its spot and radios frag out.",
		"tags": ["ai", "grenade", "combat", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "hall", "type": "hallway", "rect": Rect2(0, 0, 900, 100) }], [{ "pos": Vector2(0, 50), "width": 80.0 }])
	s.object(&"sofa", "sofa", Vector2(700, 31))
	s.object(&"table", "coffee_table", Vector2(700, 75))
	s.actor(&"i", &"invader", INVADER_AT, { "facing": Vector2.RIGHT })
	Probe.hostile(s, &"h", HOSTILE_AT, INVADER_AT)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 0, 1)
	if not t.require(Probe.count(inv, Probe.FRAG) == 1, "the invader carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(inv, Probe.FRAG)):
		return
	var seen: Array = []
	if not t.require(await Probe.wait_act(t, &"i", "grenade", 60.0, seen), "the AI took the GRENADE tactic (its acts: %s)" % str(seen)):
		return
	if not t.require(await t.until(func(): return t.happened(&"throw"), 12.0), "the invader threw something (acting: %s)" % str(seen.back())):
		return
	var throw: Dictionary = Probe.raw(t, &"throw")[0]
	t.check(throw["data"].get("attacker") == inv and throw["data"].get("kind") == &"frag", "the invader threw its frag")
	t.check(not Probe.callouts(t, &"frag_out", &"i").is_empty(), "and radioed frag out")
	if t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag went off"):
		var at: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
		t.check(at.distance_to(HOSTILE_AT) < 110.0, "onto the hostile's spot (%.0f px from it)" % at.distance_to(HOSTILE_AT))
		t.check(Probe.blast_hits(t, inv).is_empty(), "without catching the thrower in it")
