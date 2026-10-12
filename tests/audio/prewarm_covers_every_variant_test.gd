extends GameTest

## The sound service pre-renders its library in the background so no sound hitches the first time it plays. A variant
## nobody had rendered was synthesized in the middle of the first fight (a frame or three lost per new variant), so the
## pre-warm list holds every variant of every profile, the first variant of each ahead of the rest.


func describe() -> Dictionary:
	return {
		"name": "The sound pre-warm covers every variant",
		"description": "The list the service pre-renders names each profile's every variant once, the first variants first.",
		"tags": ["sound", "bank"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var library: Array = Sound.library()
	var profiles := SoundBank.profiles()
	var seen := {}
	var wanted := 0
	for profile in profiles:
		wanted += Sound._variants_of(profile)
	for pair in library:
		seen["%s#%d" % [pair[0], pair[1]]] = true
	t.expect_eq(library.size(), wanted, "every variant of every profile is listed")
	t.expect_eq(seen.size(), library.size(), "none is listed twice")
	t.check(library.slice(0, profiles.size()).all(func(pair): return pair[1] == 0), "the first variants come first")
	t.expect_eq(Sound._variants_of(&"footstep/wood/walk"), SoundConfig.category_variants[&"footstep"], "a step has its own variant count")
	t.expect_eq(Sound._variants_of(&"shot/pistol"), SoundConfig.variants, "a shot has the default count")
