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
## `vary` (0..1) makes every render of a recipe its own take: each layer's gain, decay, glide, cut-offs, partial levels
## and delay are nudged by up to that fraction (a pitch by about half of it), drawn from the seed, so one recipe
## yields many distinct but related sounds. A footstep wants it; a gunshot does not.
## The mix is normalized to SoundConfig.peak, optionally saturated, and faded out over its last few ms. A `loop` recipe is not
## faded and its stream loops forward over the whole clip: its layers must be whole cycles of the length to join without a seam.

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
	for source: Dictionary in recipe.get("layers", []):
		var layer := _varied(source, vary, rng) if vary > 0.0 else source
		match layer.get("type", ""):
			"noise":
				_noise(mix, layer, rate, rng)
			"tone":
				_tone(mix, layer, rate)
			"modes":
				_modes(mix, layer, rate, rng)
	return _to_stream(mix, rate, float(recipe.get("drive", 0.0)), bool(recipe.get("loop", false)))


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


## Samples a layer with envelope time constant `decay` runs for, starting at `start` in a clip of `size`.
static func _span(size: int, start: int, decay: float, rate: int, extra: int = 0) -> int:
	return maxi(mini(size - start, int(decay * rate * TAIL_CONSTANTS) + extra), 0)


## Mix a layer of decaying noise (shaped by a 2-pole low-pass and a 1-pole high-pass) into `mix`.
static func _noise(mix: PackedFloat32Array, layer: Dictionary, rate: int, rng: RandomNumberGenerator) -> void:
	var start := int(float(layer.get("delay", 0.0)) * rate)
	var gain: float = layer.get("gain", 1.0)
	var attack := maxi(int(float(layer.get("attack", 0.0005)) * rate), 1)
	var decay := maxf(float(layer.get("decay", 0.02)), 0.0005)
	var fall := exp(-1.0 / (decay * rate))
	var lp := _coef(float(layer.get("lp", 0.0)), rate)
	var hp_hz: float = layer.get("hp", 0.0)
	var hp := _coef(hp_hz, rate) if hp_hz > 0.0 else 0.0
	var n := _span(mix.size(), start, decay, rate, attack)
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
		mix[start + i] += y * env * gain * (float(i + 1) / attack if i < attack else 1.0)
		env *= fall
		if env < SILENCE:
			break


## Mix a layer of decaying sine, gliding from `freq` to `freq_end`, into `mix`.
static func _tone(mix: PackedFloat32Array, layer: Dictionary, rate: int) -> void:
	var start := int(float(layer.get("delay", 0.0)) * rate)
	var gain: float = layer.get("gain", 1.0)
	var f0: float = layer.get("freq", 100.0)
	var f1: float = layer.get("freq_end", f0)
	var sweep := maxf(float(layer.get("sweep", 0.03)), 0.0005)
	var decay := maxf(float(layer.get("decay", 0.05)), 0.0005)
	var glide := exp(-1.0 / (sweep * rate))
	var fall := exp(-1.0 / (decay * rate))
	var n := _span(mix.size(), start, decay, rate)
	var phase := 0.0
	var bend := f0 - f1
	var env := 1.0
	for i in n:
		phase += TAU * (f1 + bend) / rate
		mix[start + i] += sin(phase) * env * gain
		bend *= glide
		env *= fall
		if env < SILENCE:
			break


## Each mode is a two-pole resonator, y[n] = 2r·cos(w)·y[n-1] - r²·y[n-2]: a damped sine with no
## per-sample sin() or exp().
static func _modes(mix: PackedFloat32Array, layer: Dictionary, rate: int, rng: RandomNumberGenerator) -> void:
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
		var n := _span(mix.size(), start, decay, rate)
		if n < 2:
			continue
		var y2 := 0.0
		var y1 := amp * gain * r * sin(w)
		mix[start + 1] += y1
		for i in range(2, n):
			var y := c1 * y1 + c2 * y2
			mix[start + i] += y
			y2 = y1
			y1 = y
			if absf(y) + absf(y2) < SILENCE * 0.1:
				break


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
