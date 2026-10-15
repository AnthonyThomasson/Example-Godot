extends RefCounted

## Lighting domain (private): how one light behaves over time, as a factor on its energy and on the brightness of the
## overlay that glows with it. Seeded per light (WorldLighting seeds it from the world's seed and the piece), so two lights
## of a kind are never in step, and the same world lit with the same seed flickers the same:
##   `steady`  always on (no rhythm is made for it);
##   `buzz`    on, with the small fast jitter of a tube or a cheap bulb;
##   `failing` a dying tube or bulb: on most of the time, then a burst of stutters, now and then dark for a moment;
##   `blink`   a sign: on and off in its own rhythm (a period, a share of it on, sometimes a double blink);
##   `shimmer` a screen: a restless flicker, and every few seconds a cut to another picture (brighter or darker);
##   `pulse`   a slow breathing (a heating coil, a scanner's sweep, a status light).

const MODES := [&"steady", &"buzz", &"failing", &"blink", &"shimmer", &"pulse"]

var mode: StringName  ## One of MODES.
var _rng := RandomNumberGenerator.new()  ## Seeded per light: its periods, bursts, cuts and jitter.
var _t := 0.0  ## Its clock (s), started at a seeded point.
var _period := 1.0  ## blink, pulse: the cycle (s).
var _duty := 0.6  ## blink: the share of the cycle it is on.
var _double := false  ## blink: a second short blink in the off part.
var _phase := 0.0  ## Its seeded offset in the cycle (rad).
var _next := 0.0  ## failing: the time of the next burst; shimmer: of the next cut.
var _state := &"on"  ## failing: `on`, `burst` (stuttering) or `dark`.
var _burst_end := 0.0  ## failing: the end of the burst under way.
var _flip := 0.0  ## failing: the next stutter within a burst.
var _on := true  ## failing: lit right now, within a burst.
var _level := 1.0  ## shimmer: the picture's brightness.


## The mode drawn from `kinds` (`[[mode, weight], ...]`) by `rng`: the last one when the roll runs past the weights.
static func pick(kinds: Array, rng: RandomNumberGenerator) -> StringName:
	if kinds.is_empty():
		return &"steady"
	var total := 0.0
	for k: Array in kinds:
		total += float(k[1])
	var roll := rng.randf() * total
	for k: Array in kinds:
		roll -= float(k[1])
		if roll <= 0.0:
			return k[0]
	return kinds[-1][0]


## A rhythm of `kind` (one of MODES), seeded by `seed_value`.
func _init(kind: StringName, seed_value: int) -> void:
	mode = kind
	_rng.seed = seed_value
	_phase = _rng.randf() * TAU
	_t = _rng.randf() * 10.0
	match mode:
		&"blink":
			_period = _rng.randf_range(0.7, 2.2)
			_duty = _rng.randf_range(0.45, 0.8)
			_double = _rng.randf() < 0.35
		&"pulse":
			_period = _rng.randf_range(1.4, 4.0)
		&"failing":
			_next = _t + _rng.randf_range(0.5, 4.0)
		&"shimmer":
			_next = _t + _rng.randf_range(1.5, 6.0)
			_level = _rng.randf_range(0.85, 1.1)


## Advance by `delta` s; the factor on the light's energy now (0 = dark, 1 = its own level).
func step(delta: float) -> float:
	_t += delta
	match mode:
		&"buzz":
			return 0.93 + 0.07 * _rng.randf()
		&"failing":
			return _failing()
		&"blink":
			var at := fmod(_t + _phase, _period) / _period
			if at < _duty:
				return 1.0
			var off := (at - _duty) / (1.0 - _duty)
			return 1.0 if _double and off > 0.45 and off < 0.6 else 0.0
		&"shimmer":
			if _t >= _next:
				_next = _t + _rng.randf_range(1.5, 6.0)
				_level = _rng.randf_range(0.7, 1.15)
			return _level * (0.9 + 0.06 * sin(_t * 23.0 + _phase) + 0.04 * sin(_t * 61.0) + 0.04 * (_rng.randf() - 0.5))
		&"pulse":
			return 0.65 + 0.35 * (0.5 + 0.5 * sin(TAU * _t / _period + _phase))
	return 1.0


## failing: lit (on), a burst of stutters, or dark a moment before it catches again.
func _failing() -> float:
	match _state:
		&"on":
			if _t >= _next:
				_state = &"burst"
				_burst_end = _t + _rng.randf_range(0.15, 0.9)
				_flip = _t
		&"burst":
			if _t >= _burst_end:
				_on = true
				if _rng.randf() < 0.25:
					_state = &"dark"
					_next = _t + _rng.randf_range(0.3, 0.8)
				else:
					_state = &"on"
					_next = _t + _rng.randf_range(1.0, 6.0)
			elif _t >= _flip:
				_on = not _on
				_flip = _t + _rng.randf_range(0.02, 0.09)
		&"dark":
			if _t >= _next:
				_state = &"on"
				_next = _t + _rng.randf_range(1.0, 6.0)
	var lit := _state == &"on" or _state == &"burst" and _on
	return (0.92 + 0.08 * _rng.randf()) if lit else 0.04
