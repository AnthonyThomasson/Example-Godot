extends GameTest

## The sound bank can voice every profile it lists: each renders to a sane clip (not silent, not clipping, a
## believable length), the render is cached, variants and different sounds really differ, unknown profiles are
## refused, and the whole library renders inside a generous time budget. A few intent checks pin down the
## design: metal rings longer than wood, a rifle roars longer than an SMG, carpet is quieter than tile, a heavier
## round is louder.

## The whole library takes ~0.7 s to render on the machine it was written on; the budget is about 4x that.
const LIBRARY_BUDGET_MS := 3000.0


func describe() -> Dictionary:
	return {
		"name": "The sound bank voices every profile",
		"description": "Every profile renders a sane, cached clip; variants and neighbouring profiles differ; unknown profiles are refused; the library renders within budget.",
		"tags": ["sound", "bank", "perf"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var profiles := SoundBank.profiles()
	t.check(profiles.size() > 100, "the bank lists its profiles (%d)" % profiles.size())
	t.expect_eq(profiles.size(), _unique(profiles).size(), "none is listed twice")

	SoundBank.clear_cache()
	var started := Time.get_ticks_usec()
	var bad: Array[String] = []
	for profile in profiles:
		var entry := SoundBank.sound(profile, 0)
		if entry.is_empty():
			bad.append("%s did not render" % profile)
			continue
		var stream: AudioStreamWAV = entry["stream"]
		var peak := SoundSynth.peak_of(stream)
		if stream.get_length() < 0.05 or stream.get_length() > 1.0:
			bad.append("%s is %.2f s long" % [profile, stream.get_length()])
		if peak < SoundConfig.peak - 0.02 or peak > SoundConfig.peak + 0.01:
			bad.append("%s peaks at %.2f" % [profile, peak])
	var spent := (Time.get_ticks_usec() - started) / 1000.0
	t.check(bad.is_empty(), "every profile renders a sane clip: %s" % ", ".join(bad.slice(0, 5)))
	t.trace("library render ms", spent)
	t.check(spent < LIBRARY_BUDGET_MS, "the library renders within budget (%.0f ms of %.0f)" % [spent, LIBRARY_BUDGET_MS])
	t.expect_eq(SoundBank.cached_count(), profiles.size(), "each render was cached")

	var first := SoundBank.sound(&"shot/pistol", 0)
	t.check(SoundBank.sound(&"shot/pistol", 0)["stream"] == first["stream"], "asking again returns the cached stream")
	t.expect_eq(SoundBank.cached_count(), profiles.size(), "and renders nothing new")
	t.check(SoundBank.sound(&"shot/pistol", 1)["stream"].data != first["stream"].data, "a second variant is a different render")

	for pair in [
		[&"impact/metal/blocked/medium", &"impact/wood/blocked/medium"],
		[&"impact/wood/blocked/medium", &"impact/wood/penetrate/medium"],
		[&"impact/metal/blocked/medium", &"impact/metal/ricochet/medium"],
		[&"impact/stone/blocked/light", &"impact/stone/blocked/heavy"],
		[&"impact/flesh/punch", &"impact/flesh/blocked/medium"],
		[&"shot/pistol", &"shot/rifle"],
		[&"footstep/wood/walk", &"footstep/wood/run"],
		[&"footstep/tile/walk", &"footstep/carpet/walk"],
	]:
		t.check(SoundBank.sound(pair[0], 0)["stream"].data != SoundBank.sound(pair[1], 0)["stream"].data,
			"%s and %s sound different" % pair)

	for bogus in [&"", &"nonsense", &"shot/laser", &"shot", &"impact/metal/bounce/heavy", &"impact/unobtainium/blocked/heavy",
			&"impact/metal/blocked/huge", &"footstep/lava/walk", &"footstep/wood/skip", &"casing/wood/medium", &"shot/pistol/extra"]:
		t.check(SoundBank.sound(bogus, 0).is_empty() and SoundBank.recipe_for(bogus).is_empty(), "'%s' is not a profile" % bogus)

	# The design, in numbers.
	t.check(_length(&"impact/metal/ricochet/medium") > _length(&"impact/wood/blocked/medium") * 2.0, "a ricochet off metal rings far longer than a hit on wood")
	t.check(_length(&"shot/rifle") > _length(&"shot/smg"), "a rifle's report outlasts an SMG's")
	t.check(_level(&"footstep/carpet/walk") < _level(&"footstep/tile/walk"), "carpet is quieter underfoot than tile")
	t.check(_level(&"footstep/wood/run") > _level(&"footstep/wood/walk"), "a run is louder than a walk")
	t.check(_level(&"impact/wall/blocked/heavy") > _level(&"impact/wall/blocked/light"), "a heavy round hits louder than a light one")
	t.check(_level(&"impact/flesh/punch") < _level(&"impact/flesh/blocked/medium"), "a punch is quieter than a bullet")
	t.check(_level(&"shot/rifle") > _level(&"shot/smg"), "a rifle is louder than an SMG")
	t.check(_length(&"reload/rifle/in") > _length(&"reload/rifle/out") * 1.5, "seating a magazine and racking the action takes longer than drawing it")
	t.check(_length(&"reload/rifle/in") > _length(&"reload/pistol/in"), "a rifle's action is racked later than a pistol's")
	t.check(_level(&"reload/rifle/in") > _level(&"reload/smg/in"), "a rifle reloads louder than an SMG")
	t.check(SoundBank.sound(&"reload/pistol/out", 0)["stream"].data != SoundBank.sound(&"reload/pistol/in", 0)["stream"].data, "out and in sound different")


func _length(profile: StringName) -> float:
	return (SoundBank.sound(profile, 0)["stream"] as AudioStreamWAV).get_length()


func _level(profile: StringName) -> float:
	return SoundBank.sound(profile, 0)["level_db"]


func _unique(items: Array) -> Array:
	var out: Array = []
	for i in items:
		if not out.has(i):
			out.append(i)
	return out
