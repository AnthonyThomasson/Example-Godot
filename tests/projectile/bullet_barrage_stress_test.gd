extends GameTest

## Performance guard: four shooters empty pistols into a furnished arena for six seconds. Every shot
## runs the ballistic resolution (penetrate / ricochet / block), dents furniture, sprays debris and
## drops a casing. Frame cost stays within budget, the Despawner cap holds, and once the barrage ends
## the world does not keep growing.

const Perf := preload("res://tests/_perf/perf_probe.gd")

# All on the left wall, firing right, so no bullet crosses another shooter.
const SHOOTERS := [Vector2(60, 200), Vector2(60, 400), Vector2(60, 600), Vector2(60, 800)]
const TARGETS := 24
const FIRE_FRAMES := 360
const FIRE_EVERY := 4
# Baseline: avg ~19 / p95 ~30 / max ~40 ms per frame. Budgets ~4-5x.
const AVG_MS := 80.0
const P95_MS := 130.0
const MAX_MS := 200.0
# Each tracked chip carries a visuals child, so a full Despawner (1000) is ~2000 nodes; baseline ~2200.
const NODE_GROWTH_AFTER_DRAIN := 4000


func describe() -> Dictionary:
	return {
		"name": "A bullet barrage stays cheap",
		"description": "Four pistols fire every 4th frame for 6 s into a furnished arena; frame cost stays within budget and the Despawner cap holds.",
		"tags": ["perf", "stress", "pistol", "projectile", "debris", "casing"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 900))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.debris", true)
	s.switch(&"nav.rebake", false)  # shot pieces can overlap; nav re-baking is covered by navigation/bake_and_path_stress
	# This guards the cost of resolving shots, not the pistol's fire rate: with no interval the pistol fires on every
	# press (automatic fire has its own guard, `automatic_fire_stress`).
	var uncapped: Dictionary = GunConfig.guns.duplicate(true)
	uncapped[&"pistol"]["fire_interval"] = 0.0
	s.set_static(GunConfig, "guns", uncapped)
	for i in SHOOTERS.size():
		s.actor(StringName("shooter%d" % i), &"puppet", SHOOTERS[i], { "start_slot": 3, "max_health": 100000.0 })
	var kinds := ["chair", "bookshelf", "armchair", "side_table"]
	for i in TARGETS:
		s.object(StringName("target%d" % i), kinds[i % kinds.size()],
			Vector2(450 + (i % 6) * 100, 200 + (i / 6) * 200))


func run(t: TestContext) -> void:
	var guns: Array = []
	for i in SHOOTERS.size():
		var gun := t.puppet(StringName("shooter%d" % i))
		gun.aim_at(Vector2(700, 200 + i * 200))
		guns.append(gun)
	await t.seconds(0.5)
	var nodes_before := Perf.nodes()

	var fire := func(frame: int):
		if frame % FIRE_EVERY == 0:
			for gun in guns:
				gun.shoot()
	var stats := await Perf.frame_stats(t, FIRE_FRAMES, fire)
	Perf.within_frames(t, "barrage", stats, AVG_MS, P95_MS, MAX_MS)

	t.check(t.events_of(&"hit").size() > FIRE_FRAMES / FIRE_EVERY, "the barrage actually landed hits (%d)" % t.events_of(&"hit").size())
	t.check(Despawner.count() <= Despawner.max_scene_objects, "the Despawner cap holds (%d tracked)" % Despawner.count())

	await t.seconds(8.0)  # let projectiles, casings and chips drain
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF barrage node growth after drain %d (Despawner tracks %d)" % [grown, Despawner.count()])
	t.trace("node growth after drain", grown)
	t.check(grown <= NODE_GROWTH_AFTER_DRAIN, "node growth after the barrage drains: %d, budget %d" % [grown, NODE_GROWTH_AFTER_DRAIN])
	t.check(Despawner.count() <= Despawner.max_scene_objects, "the Despawner cap still holds (%d tracked)" % Despawner.count())
