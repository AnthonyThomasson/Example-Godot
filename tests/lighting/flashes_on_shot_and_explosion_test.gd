extends GameTest

## R10 (ticket #61): a shot and an explosion each light a flash for a moment, then it goes. A puppet fires a pistol at the far
## wall: within a few frames of the `shot` event one of the lighting's flash lights is lit at the muzzle, and within 0.25 s every
## flash is dark again. It then throws a frag into the open: within a few frames of the `explosion` event a flash is lit where
## the grenade went off, and within 1.5 s every flash is dark again.
##
## It reads (tests/_lighting/lighting_probe.gd) `WorldLighting` in the group `world_lighting`
## with `flashes()`, the pooled PointLight2Ds (lit: enabled with energy).

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const Grenade := preload("res://tests/_ai/grenade_probe.gd")
const GUNNER_AT := Vector2(200, 300)
const AIM := Vector2(880, 300)
const LOB := Vector2(560, 300)
const LIT_WITHIN := 3  ## Frames after the event by which a flash is lit.
const SHOT_GONE := 0.25  ## s after a shot by which every flash is dark.
const BLAST_GONE := 1.5  ## s after an explosion by which every flash is dark.


func describe() -> Dictionary:
	return {
		"name": "A shot and an explosion each light a brief flash",
		"description": "A pistol shot lights a flash at the muzzle that is gone within 0.25 s; a frag lights one where it bursts, gone within 1.5 s.",
		"tags": ["lighting", "grenade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.actor(&"gunner", &"puppet", GUNNER_AT, { "start_slot": 3, "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	var flashes: Array = lighting.flashes()
	if not t.require(not flashes.is_empty() and flashes.all(func(l: Variant) -> bool: return l is PointLight2D),
			"the lighting has a pool of flash PointLight2Ds (%d)" % flashes.size()):
		return
	t.check(not flashes.any(func(l: PointLight2D) -> bool: return Probe.lit(l)), "no flash is lit before anything happens")

	var gunner := t.puppet(&"gunner")
	gunner.aim_at(AIM)
	await t.seconds(0.4)
	gunner.shoot()
	if not t.require(await t.until(func() -> bool: return t.happened(&"shot"), 1.0), "the pistol fires (a shot event)"):
		return
	await _flash(t, flashes, t.events_of(&"shot")[0]["position"], "shot", SHOT_GONE)

	Grenade.arm(t.actor(&"gunner"), 0, 1)
	await Grenade.throw_at(t, &"gunner", Grenade.FRAG, LOB)
	if not t.require(await t.until(func() -> bool: return t.happened(&"explosion"), Grenade.FUSE_FRAG + 3.0), "the frag goes off (an explosion event)"):
		return
	await _flash(t, flashes, t.events_of(&"explosion")[0]["position"], "explosion", BLAST_GONE)


## Check that a flash is lit near `at` within `LIT_WITHIN` frames of the `what` event, and that every flash is dark within
## `gone` s of it.
func _flash(t: TestContext, flashes: Array, at: Vector2, what: String, gone: float) -> void:
	var near := func() -> bool:
		return flashes.any(func(l: PointLight2D) -> bool: return Probe.lit(l) and l.global_position.distance_to(at) <= Probe.FLASH_NEAR)
	var start := t.time
	var seen := false
	for _i in LIT_WITHIN:
		if near.call():
			seen = true
			break
		await t.frames(1)
	t.check(seen, "the %s lights a flash within %.0f px of it within %d frames" % [what, Probe.FLASH_NEAR, LIT_WITHIN])
	var dark := await t.until(func() -> bool: return not flashes.any(func(l: PointLight2D) -> bool: return Probe.lit(l)), gone + 1.0)
	t.check(dark and t.time - start <= gone, "the %s's flash is gone within %.2f s (dark after %.2f s)" % [what, gone, t.time - start])
