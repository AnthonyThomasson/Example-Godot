extends GameTest

## G1: a grenade tells its holder what it is, `Character.throw_stats(slot)` = `{ kind, max_range, danger_radius, fuse, flash_cover_reach }`, from its
## `GrenadeConfig` row: the numbers the AI throws by. A live grenade answers the same (`ThrownGrenade.throw_stats()`), taken from the row it was thrown
## with. Any other item, and a slot that is empty, answer {}.

const Probe := preload("res://tests/_ai/grenade_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A grenade tells its holder its throw stats",
		"description": "A carrier reads a stun's and a frag's range, danger radius, fuse and flash cover reach off the items; a live grenade answers the same; a gun and an empty slot answer nothing.",
		"tags": ["grenade", "item", "stats"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.actor(&"c", &"puppet", Vector2(100, 250), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var c := t.actor(&"c")
	Probe.arm(c, 1, 0)
	var stun: Dictionary = c.throw_stats(Probe.STUN)
	t.expect_eq(stun.get("kind"), &"stun", "a stun reports its kind")
	t.expect_near(float(stun.get("max_range", -1.0)), Probe.MAX_RANGE, 0.01, "the throw range of the spec")
	t.expect_near(float(stun.get("danger_radius", -1.0)), Probe.FLASH_RADIUS, 0.01, "its danger radius is the flash radius")
	t.expect_near(float(stun.get("fuse", -1.0)), Probe.FUSE_STUN, 0.01, "its fuse")
	t.expect_near(float(stun.get("flash_cover_reach", -1.0)), 30.0, 0.01, "and the reach furniture shields from its flash at")
	t.expect_eq(c.throw_stats(Probe.FRAG), {}, "no frag carried: nothing")
	t.expect_eq(c.throw_stats(Probe.PISTOL), {}, "a gun is not thrown: nothing")
	Probe.arm(c, 0, 1)
	var frag: Dictionary = c.throw_stats(Probe.FRAG)
	t.expect_eq(frag.get("kind"), &"frag", "a frag reports its kind")
	t.expect_near(float(frag.get("danger_radius", -1.0)), Probe.BLAST_RADIUS, 0.01, "its danger radius is the blast radius")
	t.expect_near(float(frag.get("fuse", -1.0)), Probe.FUSE_FRAG, 0.01, "its fuse")
	t.check(float(frag.get("flash_cover_reach", 0.0)) == INF, "a blast is shielded by furniture at any distance: INF")
	await Probe.throw_at(t, &"c", Probe.FRAG, Vector2(400, 250))
	if not t.require(await t.until(func(): return not Probe.live(t).is_empty(), 2.0), "the frag leaves the hand"):
		return
	t.expect_eq(Probe.live(t)[0].throw_stats(), frag, "the live grenade answers what its item did")
	t.expect_eq(c.throw_stats(Probe.FRAG), {}, "the last one thrown, the slot answers nothing")
