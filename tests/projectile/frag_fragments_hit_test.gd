extends GameTest

## G8: a frag throws 40 real fragments round the circle through `ProjectileSpawner`: low power, fast, short reach. None
## travels past `fragment_range` (500 px: a projectile can be given a maximum range, past which it is spent); they strike
## like bullets (cover, debris, blood, impact sounds) and each hit posts `&"hit"` with the thrower as `attacker`.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(80, 500)
const AIM := Vector2(480, 500)
const RANGE := 500.0
## One physics frame of a fast fragment (px), the slack on a position sampled once per frame.
const STEP := 70.0


func describe() -> Dictionary:
	return {
		"name": "A frag throws 40 fragments that hit like bullets",
		"description": "One frag in an open room spawns 40 projectiles; none is seen further than 500 px from the blast; their hits name the thrower and the furniture they strike sheds debris.",
		"tags": ["grenade", "frag", "fragments", "projectile"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 1000))
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100000.0 })
	s.object(&"wardrobe_a", "wardrobe", AIM + Vector2(0, -150))
	s.object(&"wardrobe_b", "wardrobe", AIM + Vector2(0, 150))


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade (Character.item_count(8) = %d)" % Probe.count(thrower, Probe.FRAG)):
		return
	var before := t.spawned("Projectile").size()
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag grenade goes off"):
		return
	var blast: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	var reach := 0.0
	for i in 90:  # 1.5 s of flight, sampled each frame
		for n in t.world.get_children():
			if String(n.name).begins_with("Projectile") and n is Node2D:
				reach = maxf(reach, (n as Node2D).global_position.distance_to(blast))
		await t.frames(1)
	t.expect_eq(t.spawned("Projectile").size() - before, 40, "the blast spawned 40 fragments")
	t.check(reach > 150.0, "they flew out from the blast (farthest seen %.0f px)" % reach)
	t.check(reach <= RANGE + STEP, "none was seen past the fragment range of %.0f px (farthest %.0f)" % [RANGE, reach])
	var live := t.world.get_children().filter(func(n): return String(n.name).begins_with("Projectile") and n is Node2D)
	t.check(live.is_empty(), "and every one is spent by now (%d still flying)" % live.size())
	var hits := t.events_of(&"hit", func(d): return d.get("attacker") == thrower and d.get("outcome") != &"blast")
	t.check(hits.size() >= 4, "fragment hits name the thrower as attacker (%d)" % hits.size())
	t.check(hits.any(func(e): return e.get("outcome") in [&"blocked", &"penetrate", &"ricochet"]), "and carry the usual bullet outcome")
	# Chips fly under the struck piece's parent (not the world root) and land into its DebrisLayer.
	var chips := 0
	for layer in t.world.find_children("DebrisLayer", "", true, false):
		chips += layer.count()
	t.check(chips > 0, "the furniture they strike sheds debris (%d chips landed)" % chips)
