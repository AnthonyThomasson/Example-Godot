extends GameTest

## G17 (amended: "frag out, take cover"): a frag may be thrown at a hostile that lies inside the thrower's own danger zone when the thrower can
## get safe before the fuse is out. An invader with a frag stands 230 px from a hostile that is hidden behind a couch and a desk filling a
## hall, so the blast would reach it, but it is already on the near side of that cover, which shields a crouched body (G7). It throws, radios
## frag out, crouches and holds the crouch until the bang, and is unharmed by it; then it goes back to its gun. The whole pipeline runs, real Von
## at every level. A `require` that the AI took the GRENADE path comes first, so a different Von choice reads as a set-up finding.
##
## Premises: the hostile is a household *puppet* that cannot be killed and never shoots; the invader is armed with one frag here because the test
## world keeps the default inventory, the way Main arms a spawn.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const INVADER_AT := Vector2(570, 56)
const HOSTILE_AT := Vector2(800, 56)


func describe() -> Dictionary:
	return {
		"name": "An invader frags a hostile inside its own zone and takes cover from it",
		"description": "A hostile hides behind a couch and a desk 230 px from an invader with a frag: it takes the GRENADE tactic, throws, crouches on its side of the cover until the bang, takes no blast, and is back on its gun afterwards.",
		"tags": ["ai", "grenade", "combat", "cover", "von"],
		"requires_von": true,
		"timeout": 100.0,
	}


func configure(s: TestSetup) -> void:
	# A hall 100 px wide inside, wall to wall: a couch (coverage 45) and a desk (45) across it leave no line to the hostile and shield a crouched body.
	s.layout([{ "key": "hall", "type": "entry_hall", "rect": Rect2(0, 0, 900, 112) }], [{ "pos": Vector2(0, 56), "width": 80.0 }])
	s.object(&"sofa", "sofa", Vector2(700, 31))
	s.object(&"desk", "desk", Vector2(700, 81))
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
	var thrown: Dictionary = Probe.raw(t, &"throw")[0]
	t.check(thrown["data"].get("attacker") == inv and thrown["data"].get("kind") == &"frag", "the invader threw its frag")
	t.check(not Probe.callouts(t, &"frag_out", &"i").is_empty(), "and radioed frag out")

	# From the throw to the bang: the posture the thrower holds.
	var samples: Array = []
	while Probe.booms(t, &"frag").is_empty() and t.time < float(thrown["time"]) + 6.0:
		samples.append({ "t": t.time, "posture": inv.posture(), "p": inv.global_position })
		await t.frames(1)
	if not t.require(not Probe.booms(t, &"frag").is_empty(), "the frag went off"):
		return
	var boom: Dictionary = Probe.booms(t, &"frag")[0]
	var at: Vector2 = boom["data"]["position"]
	t.require(at.distance_to(inv.global_position) <= Probe.FRAG_ZONE, "set-up: the invader was inside the frag's %.0f px zone (%.0f px from where it went off)" % [Probe.FRAG_ZONE, at.distance_to(inv.global_position)])
	var last: Array = samples.filter(func(s): return float(s["t"]) >= float(boom["time"]) - 1.0)
	t.check(not last.is_empty() and last.all(func(s): return s["posture"] == &"crouch"), "for the last second before the bang the invader was crouched (%s)" % str(last.map(func(s): return s["posture"]).slice(0, 3)))
	t.check(Probe.shielded(t, at, inv), "behind the couch and desk, which shield a crouched body from the blast")
	t.check(Probe.blast_hits(t, inv).is_empty(), "so the blast did not touch it")
	t.check(not inv.is_dead and inv.health >= inv.max_health - 0.01, "and it is unhurt (%.0f / %.0f)" % [inv.health, inv.max_health])
	await t.seconds(1.5)
	t.expect_eq(inv.current_slot(), Probe.PISTOL, "after the bang it is back on its gun")
