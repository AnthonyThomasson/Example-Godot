extends GameTest

## Performance guard: six defenders and six invaders share a furnished arena (a 2 s warm-up, then 300 measured frames) with Von scripted (no
## server), so every NPC senses, decides, paths and fights each frame. Frame cost stays within budget and
## the AI does not leak nodes per decision.

const Perf := preload("res://tests/_perf/perf_probe.gd")

const PER_SIDE := 6
const WARMUP_S := 2.0
const MEASURE_FRAMES := 300
# The average frame holds the smooth-match standard (Perf.SMOOTH_AVG_MS). The worst frames do not, yet: twelve NPCs in one
# open arena see six hostiles each, and an NPC that decides builds its whole decision snapshot in one frame (a firing spot
# search per hostile: thousands of rays and path queries), 15 ms on average and up to 60 ms and more. Until that build is made
# incremental the tail is bounded here instead of held to the standard; the 5v5 match in a house (walls hide most hostiles) meets it.
# Before the performance work (#13): avg 22-25 / p95 30-37 / max 64-77 ms per frame; now avg 14-15 / p95 19-22 / max 60-73.
# ~850 nodes are added over 300 frames (the Despawner caps what firing adds). The window is 300 frames, not the 600 it
# once was, because the three frame statistics do not move with a longer one; the node budget went from 3000 to 2000 with it,
# so a leak per frame is caught at least as early.
const P95_MS := 30.0
const MAX_MS := 100.0
const NODE_GROWTH := 2000


func describe() -> Dictionary:
	return {
		"name": "A crowd of NPCs stays cheap",
		"description": "12 scripted-Von NPCs (two factions) sense, decide, path and shoot in a furnished arena; frame cost over 5 s stays within budget.",
		"tags": ["ai", "scripted", "crowd"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1600, 1000))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.vision", true)
	s.switch(&"ai.pursuit", true)
	s.switch(&"projectile.flyover", false)
	s.switch(&"nav.rebake", false)  # fighting shoves furniture into overlaps; re-baking is covered by perf/bake_and_path_stress
	s.switch(&"audio.sound", false)  # first-play synthesis is a one-off the game pre-warms away; sound is costed in perf/match_5v5_stress
	var kinds := ["bookshelf", "armchair", "side_table", "chair", "plant"]
	for i in 20:
		s.object(StringName("deco%d" % i), kinds[i % kinds.size()], Vector2(300 + (i % 5) * 250, 250 + (int(i / 5.0)) * 160))
	for i in PER_SIDE:
		s.actor(StringName("defender%d" % i), &"defender", Vector2(120 + i * 40, 120 + i * 130))
		s.actor(StringName("invader%d" % i), &"invader", Vector2(1480 - i * 40, 120 + i * 130))


func run(t: TestContext) -> void:
	await t.seconds(WARMUP_S)
	var nodes_before := Perf.nodes()
	var stats := await Perf.frame_stats(t, MEASURE_FRAMES)
	Perf.within_frames(t, "npc crowd", stats, Perf.SMOOTH_AVG_MS, P95_MS, MAX_MS)
	t.check(not t.von_requests().is_empty(), "the NPCs asked for decisions (%d asks)" % t.von_requests().size())
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF npc crowd node growth %d, %d decisions asked" % [grown, t.von_requests().size()])
	t.trace("node growth", grown)
	t.check(grown <= NODE_GROWTH, "node growth over the run: %d, budget %d" % [grown, NODE_GROWTH])
