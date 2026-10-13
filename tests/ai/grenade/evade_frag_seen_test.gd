extends GameTest

## G16, the reflex: an NPC that sees (or hears land) a live frag it is in the zone of radios a `grenade` callout and runs to the nearest
## escape spot it can reach before the fuse is out (out of the grenade's line, or beyond its radius), then holds and re-decides.
## A defender stands in the hall of the terrace house; a hostile invader at the far end throws a frag that lands beside it. The
## whole pipeline runs (real Von, vision, hearing, the radio, the fight with the thrower); nothing is scripted but the throw.
##
## Premise: the thrower is an invader *puppet* that cannot be killed, the scripted world event. It is armed here because the test
## world keeps the default inventory (no grenades), the way Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A defender runs from a frag that lands beside it",
		"description": "A frag lands 60 px from a defender in the hall: it radios a grenade callout, is out of the grenade's line of sight or past its radius before it goes off (3 s), takes no blast and lives.",
		"tags": ["ai", "grenade", "evade", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"d", &"defender", Maps.HALL_MIDDLE, { "facing": Vector2.RIGHT })
	s.actor(&"thrower", &"puppet", Vector2(760, 415), { "faction": &"invader", "max_health": 1000000.0, "aim_point": Vector2(0, 415) })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var d := t.actor(&"d")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	await t.seconds(0.8)
	var puppet := t.puppet(&"thrower")
	puppet.select_slot(Probe.FRAG)
	puppet.aim_at(d.global_position + Vector2(60, 0))
	await t.seconds(0.4)
	puppet.aim_at(d.global_position + Vector2(60, 0))
	await t.frames(3)
	var clicked := t.time
	puppet.shoot()
	var path: Array = []
	while t.time < clicked + 6.0 and Probe.booms(t, &"frag").is_empty():
		path.append({ "t": t.time, "p": d.global_position })
		await t.frames(1)
	if not t.require(not Probe.booms(t, &"frag").is_empty(), "the frag went off"):
		return
	var boom: Dictionary = Probe.booms(t, &"frag")[0]
	var at: Vector2 = boom["data"]["position"]
	await t.frames(3)

	var calls := Probe.callouts(t, &"grenade", &"d")
	t.check(not calls.is_empty(), "the defender radioed a grenade callout")
	if not calls.is_empty():
		t.check((calls[0]["data"].get("point", Vector2.INF) as Vector2).distance_to(at) < 90.0, "naming the grenade's spot (%s)" % str(calls[0]["data"].get("point")))
		t.check(calls[0]["data"].get("kind") == &"frag", "and its kind")
	var last: Array = path.filter(func(s): return float(s["t"]) >= float(boom["time"]) - 0.25)
	var covered := last.all(func(s): return Probe.safe_from_frag(t, at, s["p"]))
	t.check(covered, "for the last 0.25 s before it went off the defender was out of the grenade's line of sight or past its %.0f px radius (it was %.0f px away)" % [Probe.BLAST_RADIUS, d.global_position.distance_to(at)])
	var first_pos: Vector2 = path[0]["p"] if not path.is_empty() else d.global_position
	var ran := 0.0
	for i in range(1, path.size()):
		ran += (path[i]["p"] as Vector2).distance_to(path[i - 1]["p"])
	t.check(ran >= 80.0, "it ran to get there (%.0f px covered from %s)" % [ran, str(first_pos.round())])
	t.check(Probe.blast_hits(t, d).is_empty(), "it took no blast")
	t.check(not d.is_dead and d.health > 0.0, "and survived (%.0f HP)" % d.health)
