extends GameTest

## A step is not one sample played over and over. On every surface a footstep has several takes that really differ
## from one another (they correlate only loosely, and differ in loudness and in when the toe lands), and each take is
## two beats: the heel strikes, then the toe taps a few ms later and softer.

const Probe := preload("res://tests/_audio/sound_probe.gd")

const SAMPLES_PER_MS := 22.05


func describe() -> Dictionary:
	return {
		"name": "Footsteps are varied two-beat steps, not one repeated sample",
		"description": "Each surface's footstep renders several takes that are mutually distinct, loosely correlated and differently loud, and each has a heel strike followed by a softer toe tap.",
		"tags": ["sound", "footstep", "variety"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


## Running totals of the samples' magnitudes (`totals[i]` = the sum over the first `i` samples), so the sum over any
## window is one subtraction.
func _magnitude_totals(samples: PackedFloat32Array) -> PackedFloat64Array:
	var totals := PackedFloat64Array()
	totals.resize(samples.size() + 1)
	var sum := 0.0
	for i in samples.size():
		sum += absf(samples[i])
		totals[i + 1] = sum
	return totals


## Peak of the smoothed envelope (a 4 ms moving average of the magnitudes, from `_magnitude_totals`) between
## `from_ms` and `to_ms`.
func _peak(totals: PackedFloat64Array, from_ms: float, to_ms: float) -> float:
	var peak := 0.0
	var window := 88  # 4 ms
	var start := int(from_ms * SAMPLES_PER_MS)
	var stop := mini(int(to_ms * SAMPLES_PER_MS), totals.size() - 1 - window)
	for i in range(start, stop, 4):
		peak = maxf(peak, (totals[i + window] - totals[i]) / window)
	return peak


func _similarity(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := mini(a.size(), b.size())
	var dot := 0.0
	var aa := 0.0
	var bb := 0.0
	for i in n:
		dot += a[i] * b[i]
		aa += a[i] * a[i]
		bb += b[i] * b[i]
	return dot / maxf(sqrt(aa * bb), 0.000001)


func run(t: TestContext) -> void:
	var takes := int(SoundConfig.category_variants[&"footstep"])
	t.check(takes >= 4, "footsteps have several takes (%d)" % takes)
	for surface in ["wood", "tile", "stone", "concrete", "carpet", "outdoor"]:
		for gait in ["walk", "run"]:
			var profile := StringName("footstep/%s/%s" % [surface, gait])
			var all: Array = []
			for v in takes:
				all.append(Probe.samples(profile, v))
			var total := 0.0
			var pairs := 0
			var identical := 0
			for i in takes:
				for j in range(i + 1, takes):
					if all[i] == all[j]:
						identical += 1
					total += _similarity(all[i], all[j])
					pairs += 1
			t.expect_eq(identical, 0, "%s: no two takes are the same" % profile)
			t.check(total / pairs < 0.85, "%s: takes are only loosely alike (mean similarity %.2f)" % [profile, total / pairs])

			var heel := 0.0
			var loudness: Array = []
			for v in takes:
				var s: PackedFloat32Array = all[v]
				var totals := _magnitude_totals(s)
				heel = _peak(totals, 0.0, 30.0)
				# The toe beat: after the heel's first 30 ms, before the step's tail.
				var toe := _peak(totals, 35.0, 110.0)
				t.check(toe > heel * 0.12, "%s take %d has a toe tap after the heel (%.3f vs heel %.3f)" % [profile, v, toe, heel])
				var energy := 0.0
				for x in s:
					energy += x * x
				loudness.append(energy)
			var lo: float = loudness.min()
			var hi: float = loudness.max()
			t.check(hi > lo * 1.12, "%s: takes differ in loudness (%.2f..%.2f)" % [profile, lo, hi])
