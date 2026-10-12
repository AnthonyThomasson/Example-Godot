extends GameTest

## Which sound an event gets, decided without rendering anything: a gun with its own recipe uses it and an unknown
## gun borrows the recipe of its weight band; an impact is named by material, outcome and the round's band
## (a punch has no band); a footstep by surface and gait. Anything unrecognised
## falls back (an unknown material is `default`, an unknown surface is the open ground) except an outcome
## nobody voices, which makes no sound at all.


func describe() -> Dictionary:
	return {
		"name": "Events map to the right sound profile",
		"description": "SoundBank's *_profile functions name the shot, impact, footstep and reload profile for each case, with the documented fallbacks.",
		"tags": ["sound", "profile", "bank"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	# Weight bands follow the guns' own penetration (SMG 0.8, pistol 1.0, rifle 2.2).
	t.expect_eq(SoundBank.band(0.8), "light", "an SMG round is light")
	t.expect_eq(SoundBank.band(1.0), "medium", "a pistol round is medium")
	t.expect_eq(SoundBank.band(2.2), "heavy", "a rifle round is heavy")
	for gun: StringName in GunConfig.guns:
		t.check(SoundBank.recipe_for(SoundBank.shot_profile(gun, GunConfig.guns[gun]["penetration"])).size() > 0,
			"the %s has a shot recipe" % gun)

	t.expect_eq(SoundBank.shot_profile(&"pistol"), &"shot/pistol", "a pistol shot")
	t.expect_eq(SoundBank.shot_profile(&"rifle", 0.1), &"shot/rifle", "a known gun ignores power")
	t.expect_eq(SoundBank.shot_profile(&"railgun", 3.0), &"shot/rifle", "an unknown heavy gun sounds like the rifle")
	t.expect_eq(SoundBank.shot_profile(&"railgun", 1.0), &"shot/pistol", "an unknown medium gun like the pistol")
	t.expect_eq(SoundBank.shot_profile(&"", 0.5), &"shot/smg", "no gun at all, a light round: the SMG")

	t.expect_eq(SoundBank.impact_profile("metal", &"ricochet", 2.2), &"impact/metal/ricochet/heavy", "a rifle ricochet off metal")
	t.expect_eq(SoundBank.impact_profile("wood", &"penetrate", 1.0), &"impact/wood/penetrate/medium", "a pistol round through wood")
	t.expect_eq(SoundBank.impact_profile("fabric", &"blocked", 0.8), &"impact/fabric/blocked/light", "an SMG round stopped by fabric")
	t.expect_eq(SoundBank.impact_profile("", &"blocked", 1.0), &"impact/wall/blocked/medium", "the empty material is a wall")
	t.expect_eq(SoundBank.impact_profile("flesh", &"penetrate", 2.2), &"impact/flesh/penetrate/heavy", "a body is flesh")
	t.expect_eq(SoundBank.impact_profile("unobtainium", &"blocked", 1.0), &"impact/default/blocked/medium", "an unknown material is the default")
	t.expect_eq(SoundBank.impact_profile("flesh", &"punch", 9.0), &"impact/flesh/punch", "a punch has no band")
	t.expect_eq(SoundBank.impact_profile("", &"punch"), &"impact/wall/punch", "a punch on a wall")
	t.expect_eq(SoundBank.impact_profile("metal", &"flyover", 1.0), &"", "an outcome nobody voices makes no sound")
	t.expect_eq(SoundBank.impact_profile("metal", &"", 1.0), &"", "nor does no outcome")

	t.expect_eq(SoundBank.footstep_profile(&"carpet", false), &"footstep/carpet/walk", "walking on carpet")
	t.expect_eq(SoundBank.footstep_profile(&"tile", true), &"footstep/tile/run", "running on tile")
	t.expect_eq(SoundBank.footstep_profile(&"outdoor", false), &"footstep/outdoor/walk", "walking outside")
	t.expect_eq(SoundBank.footstep_profile(&"lava", true), &"footstep/outdoor/run", "an unknown surface is the open ground")

	t.expect_eq(SoundBank.reload_profile(&"rifle", &"out"), &"reload/rifle/out", "a rifle's magazine coming out")
	t.expect_eq(SoundBank.reload_profile(&"pistol", &"in"), &"reload/pistol/in", "a pistol's going in")
	t.expect_eq(SoundBank.reload_profile(&"railgun", &"in", 3.0), &"reload/rifle/in", "an unknown heavy gun reloads like the rifle")
	t.expect_eq(SoundBank.reload_profile(&"", &"out", 0.5), &"reload/smg/out", "no gun, a light round: the SMG")
	t.expect_eq(SoundBank.reload_profile(&"pistol", &"start"), &"", "only `out` and `in` are stages")
	for gun: StringName in GunConfig.guns:
		for stage in [&"out", &"in"]:
			t.check(not SoundBank.recipe_for(SoundBank.reload_profile(gun, stage, GunConfig.guns[gun]["penetration"])).is_empty(),
				"the %s has a reload %s sound" % [gun, stage])

	# Whatever the functions name, the bank can voice.
	var named: Array[StringName] = []
	for material in ["", "wood", "metal", "glass", "ceramic", "stone", "plastic", "fabric", "foliage", "electronics", "flesh", "x"]:
		for outcome in [&"blocked", &"penetrate", &"ricochet", &"punch"]:
			for power in [0.8, 1.0, 2.2]:
				named.append(SoundBank.impact_profile(material, outcome, power))
	for surface in [&"wood", &"tile", &"stone", &"concrete", &"carpet", &"outdoor", &"x"]:
		for running in [false, true]:
			named.append(SoundBank.footstep_profile(surface, running))
	var unvoiced := named.filter(func(p): return SoundBank.recipe_for(p).is_empty())
	t.check(unvoiced.is_empty(), "every profile a function can name has a recipe: %s" % [unvoiced.slice(0, 3)])
