class_name SoundSynth

## Audio domain: the procedural sound engine. Renders a *recipe* — a length plus a list of layers — into a
## 16-bit mono AudioStreamWAV, with no files and no outside input: a recipe and a seed always render to the
## same bytes (the noise comes from a local RandomNumberGenerator, never the gameplay one).
##
## Recipe: { "length": s, "drive": 0 (optional tanh saturation), "vary": 0 (optional), "loop": false (optional), "layers": [layer, …] }. Every layer has
## `type`, `gain` (default 1) and `delay` (s, default 0) and runs from its delay until it has decayed:
##   noise  white noise through an envelope — `attack` (s), `decay` (time constant, s), `lp` / `hp`
##          (low-pass, two poles, and high-pass, one pole, cut-off in Hz; 0 = off). Cracks, scuffs, hiss, tails.
##   tone   a sine that glides from `freq` to `freq_end` (time constant `sweep`) under an envelope with
##          `decay`. Thumps, pings.
##   modes  damped sinusoids — `freqs`, optional `amps`, `decays` (one per mode, or one `decay` for all),
##          optional `detune` (± fraction, random per mode). How a struck material rings.
##   pulses a periodic excitation rung through resonators: `rate` pulses a second (rounded to whole pulses per clip; 0 =
##          continuous noise instead of pulses), each a burst of noise decaying over `burst` s, its level cycling through
##          `pattern` (an engine's cylinders) and nudged by `spread`, its timing by `jitter` (a fraction of the gap); the
##          excitation is shaped by `lp` / `hp`, then `noise` of it is heard as it is and the rest rings through the
##          resonators `freqs` / `amps` / `decays`; `wobble` [cycles per clip, depth] swells it. An engine's firing, a tyre's
##          squeal.
## `vary` (0..1) makes every render of a recipe its own take: each layer's gain, decay, glide, cut-offs, partial levels
## and delay are nudged by up to that fraction (a pitch by about half of it), drawn from the seed, so one recipe
## yields many distinct but related sounds. A footstep wants it; a gunshot does not.
## The mix is normalized to SoundConfig.peak, optionally saturated, and faded out over its last few ms. A `loop` recipe is not
## faded and its stream loops forward over the whole clip. In a loop, whatever a layer still sounds past the clip's end comes
## round again at its start (a pulse near the end rings on into the beginning), so decaying layers join without a seam; a
## steady tone must still be a whole number of cycles of the length.

## An envelope below this has ended; a layer stops there instead of running to the end of the clip.
const SILENCE := 0.0006
## Time constants a layer is run for before it is considered finished (e^-8 ≈ -70 dB).
const TAIL_CONSTANTS := 8.0
## Fade (s) applied to the end of every clip so it never ends on a click.
const FADE_OUT := 0.004


## Render `recipe` to a stream. `seed_value` fixes its noise and detune.
static func render(recipe: Dictionary, seed_value: int) -> AudioStreamWAV:
	var rate := SoundConfig.sample_rate
	var count := maxi(int(float(recipe.get("length", 0.3)) * rate), 1)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var vary: float = recipe.get("vary", 0.0)
	var loop: bool = recipe.get("loop", false)
	for source: Dictionary in recipe.get("layers", []):
		var layer := _varied(source, vary, rng) if vary > 0.0 else source
		match layer.get("type", ""):
			"noise":
				_noise(mix, layer, rate, rng, loop)
			"tone":
				_tone(mix, layer, rate, loop)
			"modes":
				_modes(mix, layer, rate, rng, loop)
			"pulses":
				_pulses(mix, layer, rate, rng, loop)
	return _to_stream(mix, rate, float(recipe.get("drive", 0.0)), loop)


## A copy of `layer` with its numbers nudged by up to `vary` (see the header): levels and times by the full
## amount, frequencies and cut-offs by half of it.
static func _varied(layer: Dictionary, vary: float, rng: RandomNumberGenerator) -> Dictionary:
	var out := layer.duplicate()
	for key: String in ["gain", "decay", "sweep", "attack"]:
		if out.has(key):
			out[key] = float(out[key]) * (1.0 + rng.randf_range(-vary, vary))
	for key: String in ["freq", "freq_end", "lp", "hp"]:
		if out.has(key) and float(out[key]) > 0.0:
			out[key] = float(out[key]) * (1.0 + rng.randf_range(-vary, vary) * 0.5)
	if out.has("delay") and float(out["delay"]) > 0.0:
		out["delay"] = float(out["delay"]) * (1.0 + rng.randf_range(-vary, vary) * 0.5)
	for key: String in ["amps", "freqs", "decays"]:
		if out.has(key):
			var scaled := []
			for v in out[key]:
				scaled.append(float(v) * (1.0 + rng.randf_range(-vary, vary) * (0.5 if key == "freqs" else 1.0)))
			out[key] = scaled
	return out


## Peak absolute sample (0..1) of a 16-bit mono stream made by `render`.
static func peak_of(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var peak := 0
	for i in range(0, data.size() - 1, 2):
		peak = maxi(peak, absi(data.decode_s16(i)))
	return peak / 32768.0


## One-pole low-pass coefficient for cut-off `hz` (1 = pass everything).
static func _coef(hz: float, rate: int) -> float:
	if hz <= 0.0:
		return 1.0
	return 1.0 - exp(-TAU * hz / rate)


## Samples a layer with envelope time constant `decay` runs for, starting at `start` in a clip of `size`: to the clip's
## end, or in a loop (`looped`) for at most one clip's length, round past the end.
static func _span(size: int, start: int, decay: float, rate: int, extra: int = 0, looped := false) -> int:
	return maxi(mini(size if looped else size - start, int(decay * rate * TAIL_CONSTANTS) + extra), 0)


## Where sample `i` lands in a clip of `size`: past the end it comes round to the start (a layer runs at most one clip long).
static func _at(i: int, size: int) -> int:
	return i - size if i >= size else i


## Mix a layer of decaying noise (shaped by a 2-pole low-pass and a 1-pole high-pass) into `mix`.
static func _noise(mix: PackedFloat32Array, layer: Dictionary, rate: int, rng: RandomNumberGenerator, looped := false) -> void:
	var start := int(float(layer.get("delay", 0.0)) * rate)
	var gain: float = layer.get("gain", 1.0)
	var attack := maxi(int(float(layer.get("attack", 0.0005)) * rate), 1)
	var decay := maxf(float(layer.get("decay", 0.02)), 0.0005)
	var fall := exp(-1.0 / (decay * rate))
	var lp := _coef(float(layer.get("lp", 0.0)), rate)
	var hp_hz: float = layer.get("hp", 0.0)
	var hp := _coef(hp_hz, rate) if hp_hz > 0.0 else 0.0
	var size := mix.size()
	var n := _span(size, start, decay, rate, attack, looped)
	var env := 1.0
	var low := 0.0
	var low2 := 0.0
	var slow := 0.0
	for i in n:
		low += lp * (rng.randf() * 2.0 - 1.0 - low)
		low2 += lp * (low - low2)  # two poles: a duller roll-off than one
		var y := low2
		if hp > 0.0:
			slow += hp * (y - slow)
			y -= slow
		mix[_at(start + i, size)] += y * env * gain * (float(i + 1) / attack if i < attack else 1.0)
		env *= fall
		if env < SILENCE:
			break


## Mix a layer of decaying sine, gliding from `freq` to `freq_end`, into `mix`.
static func _tone(mix: PackedFloat32Array, layer: Dictionary, rate: int, looped := false) -> void:
	var start := int(float(layer.get("delay", 0.0)) * rate)
	var gain: float = layer.get("gain", 1.0)
	var f0: float = layer.get("freq", 100.0)
	var f1: float = layer.get("freq_end", f0)
	var sweep := maxf(float(layer.get("sweep", 0.03)), 0.0005)
	var decay := maxf(float(layer.get("decay", 0.05)), 0.0005)
	var glide := exp(-1.0 / (sweep * rate))
	var fall := exp(-1.0 / (decay * rate))
	var size := mix.size()
	var n := _span(size, start, decay, rate, 0, looped)
	var phase := 0.0
	var bend := f0 - f1
	var env := 1.0
	for i in n:
		phase += TAU * (f1 + bend) / rate
		mix[_at(start + i, size)] += sin(phase) * env * gain
		bend *= glide
		env *= fall
		if env < SILENCE:
			break


## Each mode is a two-pole resonator, y[n] = 2r·cos(w)·y[n-1] - r²·y[n-2]: a damped sine with no
## per-sample sin() or exp().
static func _modes(mix: PackedFloat32Array, layer: Dictionary, rate: int, rng: RandomNumberGenerator, looped := false) -> void:
	var start := int(float(layer.get("delay", 0.0)) * rate)
	var gain: float = layer.get("gain", 1.0)
	var freqs: Array = layer.get("freqs", [])
	var amps: Array = layer.get("amps", [])
	var decays: Array = layer.get("decays", [])
	var detune: float = layer.get("detune", 0.0)
	for m in freqs.size():
		var hz := float(freqs[m]) * (1.0 + rng.randf_range(-detune, detune))
		if hz >= rate * 0.45:
			continue  # past what the sample rate can carry
		var amp := float(amps[m]) if m < amps.size() else 1.0
		var decay := maxf(float(decays[m]) if m < decays.size() else float(layer.get("decay", 0.05)), 0.0005)
		var w := TAU * hz / rate
		var r := exp(-1.0 / (decay * rate))
		var c1 := 2.0 * r * cos(w)
		var c2 := -r * r
		var size := mix.size()
		var n := _span(size, start, decay, rate, 0, looped)
		if n < 2:
			continue
		var y2 := 0.0
		var y1 := amp * gain * r * sin(w)
		mix[_at(start + 1, size)] += y1
		for i in range(2, n):
			var y := c1 * y1 + c2 * y2
			mix[_at(start + i, size)] += y
			y2 = y1
			y1 = y
			if absf(y) + absf(y2) < SILENCE * 0.1:
				break


## Mix a `pulses` layer (see the header) into `mix`. The excitation (a train of noise bursts, or continuous noise) is
## shaped by the low- and high-pass, heard directly at `noise`, and drives each resonator; everything runs on past the
## clip's end until it has decayed, and in a loop (`looped`) that overhang is folded back onto the start, so the clip is one
## period of a train that never began: it loops without a seam.
static func _pulses(mix: PackedFloat32Array, layer: Dictionary, rate: int, rng: RandomNumberGenerator, looped := false) -> void:
	var count := mix.size()
	var gain: float = layer.get("gain", 1.0)
	var per_second: float = layer.get("rate", 0.0)
	var burst := maxf(float(layer.get("burst", 0.01)), 0.0005)
	var freqs: Array = layer.get("freqs", [])
	var amps: Array = layer.get("amps", [])
	var decays: Array = layer.get("decays", [])
	var longest := burst
	for d in decays:
		longest = maxf(longest, float(d))
	var tail := int(longest * rate * TAIL_CONSTANTS)
	var n := count + tail
	var exc := PackedFloat32Array()
	exc.resize(n)
	if per_second > 0.0:
		var pulses := maxi(roundi(float(count) / rate * per_second), 1)
		var gap := float(count) / pulses
		var pattern: Array = layer.get("pattern", [1.0])
		var spread: float = layer.get("spread", 0.0)
		var jitter: float = layer.get("jitter", 0.0)
		var span := mini(int(burst * rate * TAIL_CONSTANTS), tail)
		var fall := exp(-1.0 / (burst * rate))
		for k in pulses:
			var at := roundi(k * gap + rng.randf_range(-jitter, jitter) * gap)
			if at < 0:
				at += count if looped else -at
			var level := float(pattern[k % pattern.size()]) * (1.0 + rng.randf_range(-spread, spread))
			var env := level
			for i in span:
				exc[at + i] += (rng.randf() * 2.0 - 1.0) * env
				env *= fall
	else:
		for i in count:
			exc[i] = rng.randf() * 2.0 - 1.0
	# Shape the excitation: two poles of low-pass, one of high-pass.
	var lp := _coef(float(layer.get("lp", 0.0)), rate)
	var hp_hz: float = layer.get("hp", 0.0)
	var hp := _coef(hp_hz, rate) if hp_hz > 0.0 else 0.0
	var low := 0.0
	var low2 := 0.0
	var slow := 0.0
	for i in n:
		low += lp * (exc[i] - low)
		low2 += lp * (low - low2)
		var y := low2
		if hp > 0.0:
			slow += hp * (y - slow)
			y -= slow
		exc[i] = y
	var out := PackedFloat32Array()
	out.resize(n)
	var direct: float = layer.get("noise", 0.0)
	if direct != 0.0:
		for i in n:
			out[i] = exc[i] * direct
	for m in freqs.size():
		var hz := float(freqs[m])
		if hz >= rate * 0.45:
			continue  # past what the sample rate can carry
		var w := TAU * hz / rate
		var r := exp(-1.0 / (maxf(float(decays[m]) if m < decays.size() else longest, 0.0005) * rate))
		var c1 := 2.0 * r * cos(w)
		var c2 := -r * r
		# Scaled so each resonator peaks near its `amp` whatever its frequency and decay.
		var drive := (float(amps[m]) if m < amps.size() else 1.0) * (1.0 - r) * 2.0 * sin(w)
		var y1 := 0.0
		var y2 := 0.0
		for i in n:
			var y := c1 * y1 + c2 * y2 + exc[i] * drive
			out[i] += y
			y2 = y1
			y1 = y
	var wobble: Array = layer.get("wobble", [0, 0.0])
	var cycles := float(wobble[0])
	var depth := float(wobble[1])
	for i in count:
		var v := out[i]
		if looped:
			var j := i + count
			while j < n:
				v += out[j]
				j += count
		if depth != 0.0:
			v *= 1.0 + depth * sin(TAU * cycles * i / count)
		mix[i] += v * gain


## Normalize, optionally saturate, fade the tail (unless it loops) and pack as 16-bit little-endian PCM.
static func _to_stream(mix: PackedFloat32Array, rate: int, drive: float, loop := false) -> AudioStreamWAV:
	var count := mix.size()
	var top := 0.0
	for i in count:
		top = maxf(top, absf(mix[i]))
	var fade := 0 if loop else maxi(int(FADE_OUT * rate), 1)
	var norm := 1.0 / tanh(drive) if drive > 0.0 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var v := mix[i] / top if top > 0.000001 else 0.0
		if drive > 0.0:
			v = tanh(v * drive) * norm
		v *= SoundConfig.peak
		if fade > 0 and i >= count - fade:
			v *= float(count - i) / fade
		bytes.encode_s16(i * 2, clampi(int(v * 32767.0), -32767, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream
