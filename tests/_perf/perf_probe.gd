extends RefCounted

## Shared helper for the performance stress tests (tag `perf`). Load it with
## `const Perf := preload("res://tests/_perf/perf_probe.gd")`. Not a test (no `_test.gd` suffix).
##
## Headless runs use `--fixed-fps 60`, which outruns the wall clock, so the wall time between two
## physics frames is the real CPU cost of a frame. Budgets are wall-clock limits set well above the
## measured baseline (see each test), so they catch large regressions, not machine jitter.


## Wall-clock milliseconds one synchronous `work.call()` takes.
static func time_ms(work: Callable) -> float:
	var start := Time.get_ticks_usec()
	work.call()
	return (Time.get_ticks_usec() - start) / 1000.0


## Wall-clock cost of `frames` physics frames of the running test: `{ avg_ms, p95_ms, max_ms }`. `each`, if
## valid, is called with the frame index at the start of every measured frame (to keep applying load).
static func frame_stats(t: TestContext, frames: int, each := Callable()) -> Dictionary:
	var samples: Array[float] = []
	await t.frames(1)
	var last := Time.get_ticks_usec()
	for i in frames:
		if each.is_valid():
			each.call(i)
		await t.frames(1)
		var now := Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
	if samples.is_empty():
		return { "avg_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0 }
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s
	return {
		"avg_ms": total / samples.size(),
		"p95_ms": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))],
		"max_ms": sorted[sorted.size() - 1],
	}


## Live nodes in the whole scene tree (and detached trees), for leak checks.
static func nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


## Record `value` as the measurement `label` (printed as `PERF label value`, traced, kept in the failure
## bundle) and check it stays within `limit`. Returns whether it did.
static func within(t: TestContext, label: String, value: float, limit: float) -> bool:
	print("PERF %s %.2f (budget %.2f)" % [label, value, limit])
	t.trace(label, value)
	return t.check(value <= limit, "%s: %.2f is over its budget of %.2f" % [label, value, limit])


## `within` for each of a `frame_stats` result's average, 95th percentile and worst frame (ms).
static func within_frames(t: TestContext, label: String, stats: Dictionary, avg_limit: float, p95_limit: float, max_limit: float) -> void:
	within(t, label + " avg ms/frame", stats["avg_ms"], avg_limit)
	within(t, label + " p95 ms/frame", stats["p95_ms"], p95_limit)
	within(t, label + " max ms/frame", stats["max_ms"], max_limit)
