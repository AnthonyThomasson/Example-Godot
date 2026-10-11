extends GameTest

## Performance guard: six defenders and six invaders share a furnished arena for 15 s with Von scripted (no
## server), so every NPC senses, decides, paths and fights each frame. Frame cost stays within budget and
## the AI does not leak nodes per decision.

const Perf := preload("res://tests/_perf/perf_probe.gd")

const PER_SIDE := 6
const WARMUP_S := 2.0
const MEASURE_FRAMES := 600
# Baseline: avg ~15 / p95 ~19 / max ~65 ms per frame, ~1000 nodes added (capped by the Despawner). Budgets ~4x.
const AVG_MS := 60.0
const P95_MS := 80.0
const MAX_MS := 260.0
const NODE_GROWTH := 3000


func describe() -> Dictionary:
	return {
		"name": "A crowd of NPCs stays cheap",
		"description": "12 scripted-Von NPCs (two factions) sense, decide, path and shoot in a furnished arena; frame cost over 10 s stays within budget.",
		"tags": ["perf", "stress", "ai", "scripted", "crowd"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 1000))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.vision", true)
	s.switch(&"ai.pursuit", true)
	s.switch(&"projectile.flyover", false)
	s.switch(&"nav.rebake", false)  # fighting shoves furniture into overlaps; re-baking is covered by navigation/bake_and_path_stress
	var kinds := ["bookshelf", "armchair", "side_table", "chair", "plant"]
	for i in 20:
		s.object(StringName("deco%d" % i), kinds[i % kinds.size()], Vector2(300 + (i % 5) * 250, 250 + (i / 5) * 160))
	for i in PER_SIDE:
		s.actor(StringName("defender%d" % i), &"defender", Vector2(120 + i * 40, 120 + i * 130))
		s.actor(StringName("invader%d" % i), &"invader", Vector2(1480 - i * 40, 120 + i * 130))


func run(t: TestContext) -> void:
	await t.seconds(WARMUP_S)
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	Perf.within_frames(t, "npc crowd", stats, AVG_MS, P95_MS, MAX_MS)
	t.check(not t.von_requests().is_empty(), "the NPCs asked for decisions (%d asks)" % t.von_requests().size())
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF npc crowd node growth %d, %d decisions asked" % [grown, t.von_requests().size()])
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])
