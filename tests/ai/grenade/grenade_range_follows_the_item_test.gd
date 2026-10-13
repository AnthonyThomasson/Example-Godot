extends GameTest

## G17: what an NPC throws by is read off the grenades it carries (`Character.throw_stats`), not kept in a copy of its own. A hostile 430 px away,
## hidden behind a desk, is within a stun's throw range (450 px) and outside its 400 px flash zone, and, with the frag's row retuned to 300 px, out of a frag's. So an invader that
## carries both throws the stun at it and not the frag, though Von is scripted to prefer the frag: only a number read off the item can tell the two apart. Scripted Von, one scene.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const NPC_AT := Vector2(100, 450)
const HOSTILE_AT := Vector2(530, 450)
const FRAG_RANGE := 300.0


func describe() -> Dictionary:
	return {
		"name": "An NPC's throw range is read off the grenade it carries",
		"description": "An invader with a stun and a frag, a hostile hidden behind a desk 430 px off, the frag's throw range retuned to 300 px: it throws the stun though scripted Von prefers the frag.",
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
	Flank.npc(s, &"n", NPC_AT, {}, &"invader", HOSTILE_AT)
	Probe.hostile(s, &"h", HOSTILE_AT, NPC_AT)


func run(t: TestContext) -> void:
	var npc := t.actor(&"n")
	Probe.arm(npc, 1, 1)
	if not t.require(Probe.count(npc, Probe.STUN) == 1 and Probe.count(npc, Probe.FRAG) == 1, "the invader carries a stun and a frag"):
		return
	t.expect_near(float(npc.throw_stats(Probe.FRAG)["max_range"]), FRAG_RANGE, 0.01, "the frag it carries reports the retuned throw range")
	# Von is scripted to prefer the frag at the grenade level, so a frag in range would be the throw.
	if not t.require(await t.until(func(): return t.happened(&"throw"), 5.0), "the invader throws a grenade at the hostile hidden behind the desk"):
		return
	var thrown: Array = t.events_of(&"throw")
	t.expect_eq(thrown[0].get("kind"), &"stun", "the stun: 430 px is within its 450 px throw range and past the frag's retuned 300 px")
