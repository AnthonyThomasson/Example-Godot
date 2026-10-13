extends GameTest

## G7: walls block the blast. A dummy 100 px from the blast point but behind a wall takes none of it; one the same
## distance away in the open does.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(100, 250)
const AIM := Vector2(450, 250)
const WALL_X := 500.0


func describe() -> Dictionary:
	return {
		"name": "A wall blocks a frag blast",
		"description": "A frag lands 50 px short of a wall: the dummy just beyond the wall is untouched by the blast, the one in the open at the same distance is struck.",
		"tags": ["grenade", "frag", "blast", "wall"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 500, 500) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(500, 0, 500, 500) },
	], [{ "pos": Vector2(900, 500), "width": 80.0 }])
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	s.actor(&"behind", &"puppet", Vector2(WALL_X + 40.0, 250), { "max_health": 100000.0 })
	s.actor(&"open", &"puppet", AIM + Vector2(0, -100), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag grenade goes off"):
		return
	var blast: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	await t.seconds(0.3)
	t.check(blast.x < WALL_X, "it went off on the west side of the wall (x %.0f)" % blast.x)
	var open_hits := Probe.blast_hits(t, t.actor(&"open"))
	t.check(not open_hits.is_empty(), "the dummy in the open, %.0f px away, takes a blast hit" % t.actor(&"open").global_position.distance_to(blast))
	var behind := t.actor(&"behind")
	t.check(behind.global_position.distance_to(blast) < Probe.KILL_RADIUS + 60.0, "the dummy behind the wall is well inside the blast radius (%.0f px)" % behind.global_position.distance_to(blast))
	t.check(Probe.blast_hits(t, behind).is_empty(), "but the wall between them blocks the blast: no blast hit on it")
