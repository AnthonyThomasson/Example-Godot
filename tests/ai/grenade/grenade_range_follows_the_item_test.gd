extends GameTest

## G17: what an NPC throws by is read off the grenades it carries (`Character.throw_stats`), not kept in a copy of its own. A hostile 430 px away,
## hidden behind a desk, is within a stun's throw range (550 px) and, with the frag's row retuned to 300 px (the premise), out of a frag's from
## where the invader stands. Von is scripted to prefer the frag, which is offered through a throw spot (issue #51 R13): the invader walks there
## and throws the frag from within the frag's 300 px of the hostile, at least 130 px from where it stood. Only a range read off the item puts
## the throw spot there. Scripted Von, one scene; the invader walks (a plain invader actor).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const NPC_AT := Vector2(100, 450)
const HOSTILE_AT := Vector2(530, 450)
const FRAG_RANGE := 300.0


func describe() -> Dictionary:
	return {
		"name": "An NPC's throw range is read off the grenade it carries",
		"description": "An invader with a stun and a frag, a hostile hidden behind a desk 430 px off, the frag's throw range retuned to 300 px, scripted Von preferring the frag: it walks to a throw spot and throws the frag from within 300 px of the hostile.",
		"tags": ["ai", "grenade", "combat", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	var rows: Dictionary = GrenadeConfig.grenades.duplicate(true)
	rows[&"frag"]["max_range"] = FRAG_RANGE
	s.set_static(GrenadeConfig, "grenades", rows)
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 900, 300) },
		{ "key": "south", "type": "kitchen", "rect": Rect2(0, 300, 900, 300) },
	], [{ "pos": Vector2(880, 0), "width": 60.0 }, { "pos": Vector2(880, 600), "width": 60.0 }])
	s.object(&"desk", "desk", Vector2(330, 450))
	Flank.rules(s, [{ "pick": "combat" }, { "pick": "grenade" }, { "pick": "frag" }, { "pick": "stun" }, { "pick": "engage" }, { "pick": "advance" }, { "pick": "retreat" }])
	s.actor(&"n", &"invader", NPC_AT, { "facing": (HOSTILE_AT - NPC_AT).normalized() })
	Probe.hostile(s, &"h", HOSTILE_AT, NPC_AT)


func run(t: TestContext) -> void:
	var npc := t.actor(&"n")
	Probe.arm(npc, 1, 1)
	if not t.require(Probe.count(npc, Probe.STUN) == 1 and Probe.count(npc, Probe.FRAG) == 1, "the invader carries a stun and a frag"):
		return
	t.expect_near(float(npc.throw_stats(Probe.FRAG)["max_range"]), FRAG_RANGE, 0.01, "the frag it carries reports the retuned throw range")
	# Von is scripted to prefer the frag at the grenade level: the frag, from a throw spot within its own range.
	if not t.require(await t.until(func(): return t.happened(&"throw"), 10.0), "the invader throws a grenade at the hostile hidden behind the desk"):
		return
	var thrown: Array = t.events_of(&"throw")
	t.expect_eq(thrown[0].get("kind"), &"frag", "the frag, which scripted Von prefers")
	var at: Vector2 = thrown[0]["position"]
	t.check(at.distance_to(HOSTILE_AT) <= FRAG_RANGE, "released within the frag's retuned 300 px of the hostile (%.0f px)" % at.distance_to(HOSTILE_AT))
	t.check(at.distance_to(NPC_AT) >= 130.0, "after walking to a throw spot, not from where it stood 430 px off (%.0f px from there)" % at.distance_to(NPC_AT))
