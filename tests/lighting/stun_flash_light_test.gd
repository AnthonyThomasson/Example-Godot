extends GameTest

## S8 (ticket #56, `docs/lighting.md` L9): a stun's burst is shown by the lighting. A puppet throws a stun into the open; at the
## burst one of the lighting's flash lights is lit where it went off, white, shadowed like every flash, and bright: a peak
## energy of at least 4.8, well over a frag's flash (2.6). It holds its full brightness for an instant, is still lit half a
## second after the burst and is dark within about a second. (That no drawn white disc goes with it is `physics/explosion_fx`.)
##
## The exact brightness and hold are the build's to set: the test asserts the shape (held, then faded inside ~1 s, a peak of at
## least 4.8), read off `WorldLighting.flashes()` (tests/_lighting/lighting_probe.gd).

const Probe := preload("res://tests/_lighting/lighting_probe.gd")
const Grenade := preload("res://tests/_ai/grenade_probe.gd")
const THROWER_AT := Vector2(200, 300)
const LOB := Vector2(600, 300)
const LIT_WITHIN := 3  ## Frames after the `explosion` event by which the flash is lit.
const MIN_PEAK := 4.8  ## "Bright": the least peak energy, well over a frag's flash (2.6).
const HELD_FRAMES := 3  ## "Holds full brightness for an instant": at least this many frames at its peak.
const STILL_LIT := 0.45  ## s after the burst it is still lit (the fade lasts about 0.5 to 1 s).
const DARK_BY := 1.1  ## s after the burst by which it is dark.


func describe() -> Dictionary:
	return {
		"name": "A stun bursts as a bright white flash light that holds, then fades",
		"description": "At a stun's burst a white, shadowed flash light is lit there, peaking at 4.8 or more, held at its peak a few frames, still lit after 0.45 s and dark within about a second.",
		"tags": ["lighting", "grenade", "stun", "flash"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.actor(&"thrower", &"puppet", THROWER_AT, { "start_slot": 3, "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var lighting := Probe.require_lighting(t)
	if lighting == null:
		return
	var flashes: Array = lighting.flashes()
	if not t.require(not flashes.is_empty(), "the lighting has its pool of flash lights (%d)" % flashes.size()):
		return
	Grenade.arm(t.actor(&"thrower"), 1, 0)
	await Grenade.throw_at(t, &"thrower", Grenade.STUN, LOB)
	if not t.require(await t.until(func() -> bool: return t.happened(&"explosion"), Grenade.FUSE_STUN + 3.0), "the stun goes off (an explosion event)"):
		return
	var at: Vector2 = t.events_of(&"explosion")[0]["position"]
	var burst := t.time

	var flash: PointLight2D = null
	for _i in LIT_WITHIN:
		for l: PointLight2D in flashes:
			if Probe.lit(l) and l.global_position.distance_to(at) <= Probe.FLASH_NEAR:
				flash = l
		if flash != null:
			break
		await t.frames(1)
	if not t.require(flash != null, "the stun lights a flash within %.0f px of its burst within %d frames" % [Probe.FLASH_NEAR, LIT_WITHIN]):
		return
	t.check(flash.color.r >= 0.9 and flash.color.g >= 0.9 and flash.color.b >= 0.9, "the flash is white (%s)" % str(flash.color))
	t.check(flash.shadow_enabled and (flash.shadow_item_cull_mask & (LightMasks.WALL | LightMasks.FURNITURE)) == (LightMasks.WALL | LightMasks.FURNITURE),
		"it is shadowed by walls and furniture, as every flash (shadows %s, mask %d)" % [str(flash.shadow_enabled), flash.shadow_item_cull_mask])

	# Its energy each frame from now on, until it is dark or DARK_BY + 0.5 s have passed.
	var energies: Array = []
	var lit_at_still := false
	var dark_at := -1.0
	while t.time - burst <= DARK_BY + 0.5:
		var e := flash.energy if Probe.lit(flash) else 0.0
		energies.append(e)
		if t.time - burst >= STILL_LIT and t.time - burst < STILL_LIT + 0.05 and e > 0.0:
			lit_at_still = true
		if e <= 0.0 and dark_at < 0.0:
			dark_at = t.time - burst
		if dark_at >= 0.0:
			break
		await t.frames(1)
	var peak := 0.0
	for e: float in energies:
		peak = maxf(peak, e)
	var held := 0
	for e: float in energies:
		if e >= peak * 0.95:
			held += 1
		elif held > 0:
			break
	t.check(peak >= MIN_PEAK, "the flash is bright, well over a frag's (peak energy %.2f, at least %.1f)" % [peak, MIN_PEAK])
	t.check(held >= HELD_FRAMES, "it holds its full brightness for an instant (%d frames at its peak, want %d)" % [held, HELD_FRAMES])
	t.check(lit_at_still, "it is still lit %.2f s after the burst" % STILL_LIT)
	t.check(dark_at >= 0.0 and dark_at <= DARK_BY, "and dark within about a second (dark after %.2f s)" % dark_at)
