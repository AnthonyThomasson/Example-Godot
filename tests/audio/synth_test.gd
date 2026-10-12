extends GameTest

## The synth turns a recipe into a 16-bit mono stream: the same recipe and seed always give the same bytes, a
## different seed different noise, the loudest sample sits at SoundConfig.peak, each layer type sounds at the pitch
## it asks for, a layer's delay holds it back, and a recipe it cannot voice (no layers, past the sample rate's
## limit) renders silence without a fuss.


func describe() -> Dictionary:
	return {
		"name": "The synth renders deterministic, correctly pitched sounds",
		"description": "SoundSynth.render is repeatable per seed, normalizes to the peak level, voices tones and modes at their frequency, honours delays and survives empty or unplayable recipes.",
		"tags": ["synth", "sound"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


## Sign changes in the first `seconds` of `stream` (a sine of f Hz has 2f of them a second).
func _crossings(stream: AudioStreamWAV, seconds: float) -> int:
	var data := stream.data
	var n := mini(int(seconds * stream.mix_rate), int(data.size() / 2.0))
	var crossings := 0
	var last := 0
	for i in n:
		var v := data.decode_s16(i * 2)
		if v != 0:
			if last != 0 and (v > 0) != (last > 0):
				crossings += 1
			last = v
	return crossings


## The largest absolute sample (0..1) between `from` and `to` seconds.
func _peak_between(stream: AudioStreamWAV, from: float, to: float) -> float:
	var data := stream.data
	var peak := 0
	for i in range(int(from * stream.mix_rate), mini(int(to * stream.mix_rate), int(data.size() / 2.0))):
		peak = maxi(peak, absi(data.decode_s16(i * 2)))
	return peak / 32768.0


func run(t: TestContext) -> void:
	var rate := SoundConfig.sample_rate
	var mixed := {
		"length": 0.3,
		"layers": [
			{ "type": "noise", "decay": 0.05, "lp": 4000.0, "hp": 200.0 },
			{ "type": "tone", "freq": 300.0, "freq_end": 80.0, "decay": 0.1 },
			{ "type": "modes", "freqs": [900.0, 1700.0], "decays": [0.1, 0.05] },
		],
	}
	var a := SoundSynth.render(mixed, 5)
	t.check(a.data == SoundSynth.render(mixed, 5).data, "the same recipe and seed render the same bytes")
	t.check(a.data != SoundSynth.render(mixed, 6).data, "another seed gives other noise")

	t.expect_eq(a.format, AudioStreamWAV.FORMAT_16_BITS, "16-bit samples")
	t.expect_eq(a.mix_rate, rate, "at the configured sample rate")
	t.check(not a.stereo, "mono")
	t.check(absf(a.get_length() - 0.3) < 0.01, "as long as the recipe says (%.3f s)" % a.get_length())
	t.check(absf(SoundSynth.peak_of(a) - SoundConfig.peak) < 0.01, "normalized to the peak level (%.3f)" % SoundSynth.peak_of(a))
	t.check(absf(a.data.decode_s16(a.data.size() - 2)) < 0.02 * 32768.0, "it fades out instead of ending on a click")

	# Pitch: a 500 Hz tone and a 1000 Hz mode, undamped enough to count the first tenth of a second.
	var tone := SoundSynth.render({ "length": 0.2, "layers": [{ "type": "tone", "freq": 500.0, "decay": 2.0 }] }, 1)
	t.check(absi(_crossings(tone, 0.1) - 100) <= 3, "a 500 Hz tone crosses zero ~100 times in 0.1 s (%d)" % _crossings(tone, 0.1))
	var mode := SoundSynth.render({ "length": 0.2, "layers": [{ "type": "modes", "freqs": [1000.0], "decays": [2.0] }] }, 1)
	t.check(absi(_crossings(mode, 0.1) - 200) <= 4, "a 1000 Hz mode crosses zero ~200 times in 0.1 s (%d)" % _crossings(mode, 0.1))
	# A glide falls: the first stretch of a 2 kHz -> 200 Hz tone has more crossings than a later one of equal length.
	var glide := SoundSynth.render({ "length": 0.4, "layers": [{ "type": "tone", "freq": 2000.0, "freq_end": 200.0, "sweep": 0.05, "decay": 3.0 }] }, 1)
	var early := _crossings(glide, 0.03)
	t.check(early > 40, "the glide starts high (%d crossings in 30 ms)" % early)
	t.check(_crossings(glide, 0.4) - _crossings(glide, 0.37) < int(early / 2.0), "and ends low")

	# A delayed layer is silent until its time.
	var late := SoundSynth.render({ "length": 0.3, "layers": [{ "type": "noise", "delay": 0.1, "decay": 0.05 }] }, 1)
	t.check(_peak_between(late, 0.0, 0.095) == 0.0, "nothing sounds before the layer's delay")
	t.check(_peak_between(late, 0.1, 0.15) > 0.5, "then it sounds")

	# Nothing to play, or nothing it can carry: silence, no errors (an error would fail the test).
	var empty := SoundSynth.render({ "length": 0.1, "layers": [] }, 1)
	t.expect_eq(SoundSynth.peak_of(empty), 0.0, "an empty recipe is silent")
	var too_high := SoundSynth.render({ "length": 0.1, "layers": [{ "type": "modes", "freqs": [rate * 0.6], "decays": [0.1] }] }, 1)
	t.expect_eq(SoundSynth.peak_of(too_high), 0.0, "a mode above what the sample rate can carry is dropped")
	var tiny := SoundSynth.render({}, 1)
	t.check(tiny.data.size() >= 2, "a recipe with no length still renders a sample")

	# Saturation keeps the same peak but fattens the waveform (more energy at equal peak).
	var plain := SoundSynth.render({ "length": 0.1, "layers": [{ "type": "noise", "decay": 0.03 }] }, 3)
	var driven := SoundSynth.render({ "length": 0.1, "drive": 3.0, "layers": [{ "type": "noise", "decay": 0.03 }] }, 3)
	t.check(absf(SoundSynth.peak_of(driven) - SoundConfig.peak) < 0.01, "saturation still peaks at the peak level (%.3f)" % SoundSynth.peak_of(driven))
	t.check(_energy(driven) > _energy(plain) * 1.15, "and is denser (%.0f vs %.0f)" % [_energy(driven), _energy(plain)])


func _energy(stream: AudioStreamWAV) -> float:
	var sum := 0.0
	for i in int(stream.data.size() / 2.0):
		var v := stream.data.decode_s16(i * 2) / 32768.0
		sum += v * v
	return sum
