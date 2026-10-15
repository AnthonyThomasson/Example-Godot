extends GameTest

## O9 (docs/outfits.md): a frag's blast is cut by the torso armour's `blast`. Three bodies at the same distance from one blast
## (its fragments switched off, so only the blast hurts): a bare one takes the blast's full damage (falling off linearly past the kill
## radius, whatever the zones: the blast strikes the whole body), a helmeted one the same (a helmet is not torso armour), and one
## in a tactical vest clearly less.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const AT := Vector2(500, 400)
const DISTANCE := 160.0
## Slack on the blast's fall-off (the body's radius against its centre).
const SLACK := 4.0


func describe() -> Dictionary:
	return {
		"name": "A vest cuts a frag's blast",
		"description": "One frag blast (no fragments) 160 px from a bare body, a helmeted one and a vested one: the bare and helmeted bodies take the blast's full damage, the vested one clearly less.",
		"tags": ["outfit", "armour", "grenade", "frag", "blast"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 800))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	var rows: Dictionary = GrenadeConfig.grenades.duplicate(true)
	rows[&"frag"]["fragments"] = 0
	s.set_static(GrenadeConfig, &"grenades", rows)
	s.actor(&"bare", &"puppet", AT + Vector2(0, -DISTANCE), { "max_health": 1000.0 })
	s.actor(&"helmet", &"puppet", AT + Vector2(-DISTANCE, 0), { "max_health": 1000.0 })
	s.actor(&"vest", &"puppet", AT + Vector2(0, DISTANCE), { "max_health": 1000.0 })


func run(t: TestContext) -> void:
	var vested := t.actor(&"vest")
	if not OutfitProbe.require_api(t, vested):
		return
	OutfitProbe.wear(vested, { "vest": &"tactical_vest" })
	OutfitProbe.wear(t.actor(&"helmet"), { "head": &"helmet" })
	await t.seconds(0.3)

	Explosion.frag(AT, t.world, null, GrenadeConfig.row(&"frag"))
	if not t.require(await t.until(func(): return not Probe.blast_hits(t, vested).is_empty(), 1.0), "the blast reaches the vested body"):
		return
	await t.frames(2)

	var want := Probe.blast_damage(DISTANCE)
	var lost := {}
	for id: StringName in [&"bare", &"helmet", &"vest"]:
		var body := t.actor(id)
		lost[id] = body.max_health - body.health
	t.expect_near(lost[&"bare"], want, SLACK, "a bare body takes the blast's full damage (%.1f, expected about %.1f)" % [lost[&"bare"], want])
	t.expect_near(lost[&"helmet"], lost[&"bare"], 0.5, "a helmet is not torso armour: the helmeted body takes the same (%.1f)" % lost[&"helmet"])
	t.check(lost[&"vest"] < lost[&"bare"] * 0.85, "the vest cuts the blast (%.1f against %.1f bare)" % [lost[&"vest"], lost[&"bare"]])
