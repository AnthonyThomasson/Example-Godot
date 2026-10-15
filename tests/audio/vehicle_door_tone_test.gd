extends GameTest

## V7 / F2 (ticket #54, feedback round 1): a vehicle's door sounds sit in a reload's register: lower-pitched and
## mechanical (clicks, the latch, a thunk), no high creak or ring. Every take of every `door/<kind>/<stage>` profile is
## no brighter than the brightest take of the guns' reloads (`reload/<gun>/<out|in>`, measured here, not copied), and
## keeps most of its energy low, as the footstep and impact tone tests measure it.

const Probe := preload("res://tests/_audio/sound_probe.gd")

## Most of a door take's energy sits under this many Hz (the footstep tone test's band)...
const LOW_HZ := 300.0
## ... more than this share of it: a creak or a panel ring above ~300 Hz pulls a take under it, and footsteps and impacts
## measure ~0.83. The doors' brightness sits far under the reloads' clicks, so that ceiling is a guard, and this share
## is what pins the register.
const LOW_FLOOR := 0.75


func describe() -> Dictionary:
	return {
		"name": "Vehicle doors sound in a reload's register",
		"description": "Every take of every vehicle door profile is no brighter than the brightest reload take, and keeps over three quarters of its energy under 300 Hz.",
		"tags": ["sound", "vehicle", "door", "tone"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var reloads: Array = []
	var doors: Array = []
	for profile in SoundBank.profiles():
		if String(profile).begins_with("reload/"):
			reloads.append(profile)
		elif String(profile).begins_with("door/"):
			doors.append(profile)
	if not t.require(not reloads.is_empty(), "the bank voices reloads"):
		return
	if not t.require(not doors.is_empty(), "the bank voices vehicle doors"):
		return

	# The reference: the brightest take of any reload.
	var ceiling := 0.0
	var brightest_reload := &""
	for profile: StringName in reloads:
		for v in _takes(&"reload"):
			var b := Probe.brightness(Probe.samples(profile, v))
			if b > ceiling:
				ceiling = b
				brightest_reload = profile
	t.trace("brightest reload take", ceiling)

	var worst := 0.0
	for profile: StringName in doors:
		var bright := 0.0
		var low := 1.0
		for v in _takes(&"vehicle"):
			var s := Probe.samples(profile, v)
			bright = maxf(bright, Probe.brightness(s))
			low = minf(low, Probe.low_share(s, LOW_HZ))
		worst = maxf(worst, bright)
		t.check(bright <= ceiling, "%s is no brighter than a reload (brightness %.4f, the brightest reload %s %.4f)" % [profile, bright, brightest_reload, ceiling])
		t.check(low > LOW_FLOOR, "%s keeps most of its energy low (%.3f of it under %.0f Hz, more than %.2f)" % [profile, low, LOW_HZ, LOW_FLOOR])
	t.trace("brightest door take", worst)


## The take numbers `category` renders (as the Sound service picks them).
func _takes(category: StringName) -> Array:
	return range(maxi(int(SoundConfig.category_variants.get(category, SoundConfig.variants)), 1))
