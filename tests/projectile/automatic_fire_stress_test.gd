extends GameTest

## Performance guard: four SMGs and four rifles hold the trigger for five seconds into a furnished arena — the
## sustained rate of an automatic gun (13 and 9 rounds a second each), spread and all. Every round runs the
## ballistic resolution (the rifle's goes on through what it hits), dents furniture, sprays debris and drops a
## casing. Frame cost stays within budget, the Despawner cap holds, and once the firing ends the world does not
## keep growing.

const Perf := preload("res://tests/_perf/perf_probe.gd")

# The SMGs on the left wall, the rifles on the right one, each firing across the room at its own lane.
const SMGS := [Vector2(60, 150), Vector2(60, 350), Vector2(60, 550), Vector2(60, 750)]
const RIFLES := [Vector2(1340, 250), Vector2(1340, 450), Vector2(1340, 650), Vector2(1340, 850)]
const TARGETS := 24
const FIRE_FRAMES := 300
# Baseline: avg ~19 / p95 ~31 / max ~44 ms per frame. Budgets ~4x. (The shooters' lanes interleave and the SMGs'
# spread lands rounds on each other, which also guards BloodWound under a sustained stream of hits.)
const AVG_MS := 70.0
const P95_MS := 120.0
const MAX_MS := 200.0
# Each tracked chip carries a visuals child, so a full Despawner (1000) is ~2000 nodes; baseline ~2200.
const NODE_GROWTH_AFTER_DRAIN := 4000


func describe() -> Dictionary:
	return {
		"name": "Sustained automatic fire stays cheap",
		"description": "Four SMGs and four rifles hold the trigger for 5 s into a furnished arena; frame cost stays within budget and the Despawner cap holds.",
		"tags": ["perf", "stress", "gun", "automatic", "smg", "rifle", "projectile", "debris", "casing"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 900))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.debris", true)
	s.switch(&"nav.rebake", false)  # shot pieces can overlap; nav re-baking is covered by navigation/bake_and_path_stress
	# Magazines big enough that no gun runs dry in the window: the guard is for sustained fire.
	var deep: Dictionary = MagazineConfig.types.duplicate(true)
	deep[&"smg_standard"]["capacity"] = 1000
	deep[&"rifle_standard"]["capacity"] = 1000
	s.set_static(MagazineConfig, "types", deep)
	for i in SMGS.size():
		s.actor(StringName("smg%d" % i), &"puppet", SMGS[i], { "start_slot": 5, "max_health": 100000.0 })
	for i in RIFLES.size():
		s.actor(StringName("rifle%d" % i), &"puppet", RIFLES[i], { "start_slot": 6, "max_health": 100000.0 })
	var kinds := ["chair", "bookshelf", "armchair", "side_table"]
	for i in TARGETS:
		s.object(StringName("target%d" % i), kinds[i % kinds.size()],
			Vector2(450 + (i % 6) * 100, 150 + (i / 6) * 200))


func run(t: TestContext) -> void:
	var guns: Array = []
	for i in SMGS.size():
		var gun := t.puppet(StringName("smg%d" % i))
		gun.aim_at(Vector2(700, SMGS[i].y))
		guns.append(gun)
	for i in RIFLES.size():
		var gun := t.puppet(StringName("rifle%d" % i))
		gun.aim_at(Vector2(700, RIFLES[i].y))
		guns.append(gun)
	await t.seconds(0.5)
	var nodes_before := Perf.nodes()

	for gun in guns:
		gun.hold_fire(true)
	var stats := await Perf.frame_stats(t, FIRE_FRAMES)
	for gun in guns:
		gun.hold_fire(false)
	Perf.within_frames(t, "automatic fire", stats, AVG_MS, P95_MS, MAX_MS)

	var seconds := float(FIRE_FRAMES) / float(Engine.physics_ticks_per_second)
	var wanted := 0.0
	for gun_id in [&"smg", &"rifle"]:
		wanted += 4.0 * seconds / float(GunConfig.row(gun_id)["fire_interval"])
	var fired := 0
	for i in SMGS.size():
		fired += t.actor(StringName("smg%d" % i)).ammo_capacity(5) - t.actor(StringName("smg%d" % i)).ammo(5)
	for i in RIFLES.size():
		fired += t.actor(StringName("rifle%d" % i)).ammo_capacity(6) - t.actor(StringName("rifle%d" % i)).ammo(6)
	t.check(float(fired) >= wanted * 0.8, "the guns really fired at their rates (%d rounds, wanted about %.0f)" % [fired, wanted])
	t.check(Despawner.count() <= Despawner.max_scene_objects, "the Despawner cap holds (%d tracked)" % Despawner.count())

	await t.seconds(8.0)  # let projectiles, casings and chips drain
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF automatic fire node growth after drain %d (Despawner tracks %d)" % [grown, Despawner.count()])
	t.trace("node growth after drain", grown)
	t.check(grown <= NODE_GROWTH_AFTER_DRAIN, "node growth after firing drains: %d, budget %d" % [grown, NODE_GROWTH_AFTER_DRAIN])
	t.check(Despawner.count() <= Despawner.max_scene_objects, "the Despawner cap still holds (%d tracked)" % Despawner.count())
