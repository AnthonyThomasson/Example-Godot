extends RefCounted

## Shared bits for the Audio tests (not a test). `const Probe := preload("res://tests/_audio/sound_probe.gd")`.

## A range so large that nothing is out of earshot: the tests that are not about distance use it, since the
## test camera frames the actors and would otherwise decide what they can hear.
const EVERYWHERE := { &"shot": 1.0e9, &"impact": 1.0e9, &"footstep": 1.0e9 }


## The `sound` events of `kind` (every kind when &"") whose profile starts with `prefix`, in order.
static func sounds(t: TestContext, kind: StringName = &"", prefix: String = "") -> Array:
	return t.events_of(&"sound", func(d: Dictionary) -> bool:
		return (kind == &"" or d["kind"] == kind) and String(d["profile"]).begins_with(prefix))


## The distinct profiles among `events` (sound events), in the order first heard.
static func profiles(events: Array) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if not out.has(e["profile"]):
			out.append(e["profile"])
	return out


## The samples (-1..1) of `profile`'s render number `variant`.
static func samples(profile: StringName, variant: int = 0) -> PackedFloat32Array:
	var data: PackedByteArray = SoundBank.sound(profile, variant)["stream"].data
	var out := PackedFloat32Array()
	out.resize(data.size() / 2)
	for i in out.size():
		out[i] = data.decode_s16(i * 2) / 32768.0
	return out


## How bright `s` is: the energy of its sample-to-sample change over its energy. A low rumble changes slowly
## (near 0); hiss, clicks and high ring change fast (0.1 and up is audibly tinny).
static func brightness(s: PackedFloat32Array) -> float:
	var energy := 0.0
	var change := 0.0
	for i in s.size():
		energy += s[i] * s[i]
		if i > 0:
			var d := s[i] - s[i - 1]
			change += d * d
	return change / maxf(energy, 0.000001)


## The share of `s`'s energy below about `hz` (two one-pole low-passes in a row), 0..1: how much low body it has.
static func low_share(s: PackedFloat32Array, hz: float = 250.0) -> float:
	var a := 1.0 - exp(-TAU * hz / SoundConfig.sample_rate)
	var one := 0.0
	var two := 0.0
	var low := 0.0
	var energy := 0.0
	for x in s:
		one += a * (x - one)
		two += a * (one - two)
		low += two * two
		energy += x * x
	return low / maxf(energy, 0.000001)


## The low-end energy `profile` actually puts out, in its own level: the low share of its (peak-normalized) render,
## scaled by its level trim. This is what "a heavier hit" means in numbers.
static func low_weight(profile: StringName, variant: int = 0) -> float:
	var energy := 0.0
	for x in samples(profile, variant):
		energy += x * x
	return low_share(samples(profile, variant)) * energy * pow(10.0, float(SoundBank.sound(profile, variant)["level_db"]) / 10.0)
