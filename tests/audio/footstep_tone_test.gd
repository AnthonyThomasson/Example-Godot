extends GameTest

## Footsteps are dull thuds, never tinny. Every take of every surface's walk and run keeps its energy low: the
## sample-to-sample change over the energy (brightness) stays far under what hiss, clicks or a high ring produce,
## and most of its energy sits below ~300 Hz. Different floors may sound alike; they may not sound sharp.

const Probe := preload("res://tests/_audio/sound_probe.gd")

## Measured worst case across all takes is ~0.010; a tinny step (hiss, clicks, a high ring) measures 0.08 or more.
const BRIGHTNESS_CEILING := 0.03
## Measured least ~0.51 of the energy below 300 Hz.
const LOW_FLOOR := 0.4


func describe() -> Dictionary:
	return {
		"name": "Footsteps are dull on every surface, never tinny",
		"description": "Every take of every surface's walk and run stays under a brightness ceiling and keeps most of its energy in the low end.",
		"tags": ["sound", "footstep", "tone"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var takes := int(SoundConfig.category_variants[&"footstep"])
	var worst := 0.0
	for surface in ["wood", "tile", "stone", "concrete", "carpet", "outdoor"]:
		for gait in ["walk", "run"]:
			var profile := StringName("footstep/%s/%s" % [surface, gait])
			var bright := 0.0
			var low := 1.0
			for v in takes:
				var s := Probe.samples(profile, v)
				bright = maxf(bright, Probe.brightness(s))
				low = minf(low, Probe.low_share(s, 300.0))
			worst = maxf(worst, bright)
			t.check(bright < BRIGHTNESS_CEILING, "%s is not tinny (brightness %.4f, ceiling %.2f)" % [profile, bright, BRIGHTNESS_CEILING])
			t.check(low > LOW_FLOOR, "%s keeps its weight low (%.2f of its energy under 300 Hz)" % [profile, low])
	t.trace("brightest footstep take", worst)
