extends GameTest

## Performance guard: generating and furnishing many houses stays fast, and a house's node count stays in
## a band (catches a runaway spawn or a leak). Budgets are wall-clock ms with headroom over the baseline.

const Perf := preload("res://tests/_perf/perf_probe.gd")

const SEEDS := [101, 202, 303, 404, 505, 606, 707, 808, 909, 1010, 1111, 1212]
const FIXED_SEED := 424242
# Baseline (cold caches, the slowest case): 12 houses ~1560 ms, worst ~355 ms, ~334 nodes. Budgets ~4x.
const TOTAL_BUDGET_MS := 6200.0
const WORST_HOUSE_BUDGET_MS := 1400.0
const NODE_BAND := [250, 420]


func describe() -> Dictionary:
	return {
		"name": "Generating many houses stays fast",
		"description": "WorldGen.generate for a dozen seeds: total and worst-house wall time, and a fixed seed's node count, stay within budget.",
		"tags": ["perf", "stress", "worldgen", "house"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func _house(house_seed: int, t: TestContext) -> void:
	var house := WorldGen.generate(house_seed, "", Vector2.ZERO, t.world)
	house.free()


func run(t: TestContext) -> void:
	var worst := 0.0
	var total := 0.0
	for house_seed in SEEDS:
		var ms := Perf.time_ms(func(): _house(house_seed, t))
		worst = maxf(worst, ms)
		total += ms
	Perf.within(t, "generate %d houses total ms" % SEEDS.size(), total, TOTAL_BUDGET_MS)
	Perf.within(t, "generate worst house ms", worst, WORST_HOUSE_BUDGET_MS)

	var before := Perf.nodes()
	var house := WorldGen.generate(FIXED_SEED, "", Vector2.ZERO, t.world)
	var count := Perf.nodes() - before
	GameLog.say("PERF house nodes %d" % count)
	t.trace("house nodes", count)
	t.check(count >= NODE_BAND[0] and count <= NODE_BAND[1], "a house spawns %d nodes, expected %d..%d" % [count, NODE_BAND[0], NODE_BAND[1]])
	house.free()
	await t.frames(1)
	t.check(Perf.nodes() <= before + 2, "freeing a house frees its nodes (%d left over)" % (Perf.nodes() - before))
