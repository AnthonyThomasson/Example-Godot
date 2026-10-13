extends GameTest

## G16 (amended): crouching behind cover that shields from the blast (G7) counts as clear, and the NPC takes whichever of that cover or a spot out of
## line is nearer. A defender in the hall of the terrace house has a couch behind it against the south wall (the west end is the way out of line, 300 px off, by the
## living-room door); a hostile invader at the far end throws a frag that lands beside it (aimed 30 px past the defender: the burst comes to rest about 455 px along
## the hall). The couch is nearer, so the defender goes behind it and crouches, and is out of the blast. The whole pipeline runs (real Von, vision, hearing, the radio, the fight with the thrower).
##
## The set-up keeps the shadow spot behind the couch (about x 262) well inside the blast radius, about 195 px from the burst (a 55 px margin), so the premise
## check below holds whatever the throw's roll (a burst 60 px past the defender with the couch 15 px further west puts the spot 250 px away, the radius itself).
##
## Premise: the thrower is an invader *puppet* that cannot be killed (the scripted world event), armed here as Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A defender crouches behind a couch from a frag",
		"description": "A frag lands beside a defender with a couch behind it: it radios a grenade callout, is crouched behind the couch (out of the blast's reach) when it goes off, takes no blast and lives.",
		"tags": ["ai", "grenade", "evade", "cover", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.object(&"sofa", "sofa", Vector2(345, 436))  # against the south wall: centred in the 110 px hall it would seal it in the navmesh (lanes under a body wide)
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
	puppet.aim_at(d.global_position + Vector2(30, 0))
	await t.seconds(0.4)
	puppet.aim_at(d.global_position + Vector2(30, 0))
	await t.frames(3)
	var clicked := t.time
	puppet.shoot()
	var path: Array = []
	while t.time < clicked + 6.0 and Probe.booms(t, &"frag").is_empty():
		path.append({ "t": t.time, "p": d.global_position, "posture": d.posture() })
		await t.frames(1)
	if not t.require(not Probe.booms(t, &"frag").is_empty(), "the frag went off"):
		return
	var boom: Dictionary = Probe.booms(t, &"frag")[0]
	var at: Vector2 = boom["data"]["position"]
	await t.frames(3)
	t.check(not Probe.callouts(t, &"grenade", &"d").is_empty(), "the defender radioed a grenade callout")
	var last: Array = path.filter(func(s): return float(s["t"]) >= float(boom["time"]) - 0.25)
	t.check(not last.is_empty() and last.all(func(s): return s["posture"] == &"crouch"), "for the last 0.25 s before the bang the defender was crouched")
	t.check(d.global_position.distance_to(at) < Probe.BLAST_RADIUS, "still inside the blast radius, so it is the couch that protects it and not distance (%.0f px from the blast)" % d.global_position.distance_to(at))
	t.check(Probe.shielded(t, at, d), "which shields a crouched body from the blast")
	t.check(Probe.blast_hits(t, d).is_empty(), "it took no blast")
	t.check(not d.is_dead and d.health > 0.0, "and survived (%.0f HP)" % d.health)
