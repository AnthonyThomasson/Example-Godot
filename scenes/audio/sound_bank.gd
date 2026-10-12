class_name SoundBank

## Audio domain: the sound library. A *profile* is a StringName that fully describes one sound —
## `shot/rifle`, `impact/metal/ricochet/heavy`, `impact/flesh/punch`, `footstep/wood/run`,
## `reload/rifle/in` — and `sound(profile, variant)` builds its recipe from the tables below, renders it
## through SoundSynth once and caches the stream (a static cache, like PixelArt's, so it survives scene
## reloads). Which profile an event gets is decided by the `*_profile` functions, which render nothing.
##
## Pieces of a profile:
##   gun       a GunConfig id (`pistol`, `smg`, `rifle`); an unknown gun is voiced as the gun of its band.
##   material  what was struck: wood metal glass ceramic stone plastic fabric foliage electronics flesh,
##             `wall` (the empty material walls report) and `default` for anything else.
##   outcome   what the bullet did: `blocked` (embedded), `penetrate` (went through), `ricochet`; a fist is `punch`.
##   band      the projectile's weight, from its penetration power (SoundConfig.light/heavy_power): `light`
##             (SMG), `medium` (pistol), `heavy` (rifle).
##   surface   the floor underfoot (SoundSurface): wood tile stone concrete carpet outdoor.
##   gait      `walk` or `run`.
##   stage     a reload's `out` (the magazine released and drawn) or `in` (seated, then the action racked).

## Penetration outcomes a bullet impact is voiced for (a punch is its own thing).
const OUTCOMES: Array[StringName] = [&"blocked", &"penetrate", &"ricochet"]
const BAND_NAMES: Array[String] = ["light", "medium", "heavy"]
## The shot recipe an unlisted gun borrows, by band.
const BAND_SHOT := { "light": "smg", "medium": "pistol", "heavy": "rifle" }

## Reloads, by gun: pitch scales every click (heavier = lower), db trims the level, seat = the pitch (Hz) of the
## faint tick under the magazine seating click, rack = seconds from the magazine seating to the action being racked.
const RELOADS := {
	"pistol": { "pitch": 1.0, "db": 0.0, "seat": 190.0, "rack": 0.30 },
	"smg": { "pitch": 1.1, "db": -1.0, "seat": 210.0, "rack": 0.30 },
	"rifle": { "pitch": 0.85, "db": 2.0, "seat": 150.0, "rack": 0.42 },
}
const RELOAD_STAGES: Array[String] = ["out", "in"]

## How a projectile's weight colours an impact: crack loudness, pitch scale (heavier = lower), a level trim in dB,
## how much low body it carries (`body`: the thump every hit has) and `sub`: an extra deep boom under it that only
## the heavier rounds have.
const BANDS := {
	"light": { "crack": 0.55, "pitch": 1.15, "db": -4.0, "body": 0.8, "sub": 0.0 },
	"medium": { "crack": 1.0, "pitch": 1.0, "db": 0.0, "body": 1.0, "sub": 0.35 },
	"heavy": { "crack": 1.4, "pitch": 0.78, "db": 4.0, "body": 1.7, "sub": 0.8 },
}

## Gunshots. crack / bark = [decay s, low-pass Hz, gain] of the sharp snap and the mid-range bark; body = [start Hz,
## end Hz, decay s, gain] of the low thump that drops in pitch; tail = [decay s, low-pass Hz, gain] of the room's tail.
const SHOTS := {
	"pistol": { "length": 0.42, "level_db": 0.0, "crack": [0.011, 7500.0, 1.0], "bark": [0.030, 3200.0, 0.55],
		"body": [175.0, 58.0, 0.10, 0.85], "tail": [0.13, 1700.0, 0.35] },
	"smg": { "length": 0.28, "level_db": -3.0, "crack": [0.008, 9000.0, 1.0], "bark": [0.020, 3800.0, 0.50],
		"body": [210.0, 85.0, 0.055, 0.70], "tail": [0.07, 2100.0, 0.28] },
	"rifle": { "length": 0.80, "level_db": 2.0, "crack": [0.016, 9500.0, 1.2], "bark": [0.045, 2800.0, 0.70],
		"body": [125.0, 42.0, 0.15, 1.00], "tail": [0.26, 1300.0, 0.50] },
}

## What a struck material sounds like. hard = rings and throws a bullet back with a ping (soft materials whip
## instead); thump = how much low body a hit has (0 = none, 1 = all); modes / amps / decays = the partials it
## rings at (Hz, relative level, decay s); lp = the cut-off of its noise (Hz); grit = how long the crack of the
## hit lasts (s); heft = optional extra weight (default 0): more low body, a longer thud, the struck ring turned down
## (a ricochet still rings); db = its level trim (the synth normalizes every sound, so quiet materials say so here).
const MATERIALS := {
	"wood": { "hard": false, "db": 0.0, "thump": 0.6, "modes": [210.0, 380.0, 690.0], "amps": [1.0, 0.6, 0.4],
		"decays": [0.045, 0.03, 0.02], "lp": 2800.0, "grit": 0.020 },
	"metal": { "hard": true, "db": 2.0, "thump": 0.15, "heft": 0.9, "modes": [620.0, 1480.0, 2330.0, 3410.0], "amps": [1.0, 0.8, 0.6, 0.4],
		"decays": [0.22, 0.18, 0.14, 0.10], "lp": 7000.0, "grit": 0.008 },
	"glass": { "hard": true, "db": 0.0, "thump": 0.05, "modes": [1900.0, 3100.0, 4700.0], "amps": [1.0, 0.7, 0.5],
		"decays": [0.16, 0.12, 0.09], "lp": 9500.0, "grit": 0.006 },
	"ceramic": { "hard": true, "db": 0.0, "thump": 0.2, "modes": [950.0, 1900.0, 2900.0], "amps": [1.0, 0.7, 0.45],
		"decays": [0.09, 0.07, 0.05], "lp": 7000.0, "grit": 0.010 },
	"stone": { "hard": true, "db": 0.0, "thump": 0.4, "modes": [420.0, 880.0, 1500.0], "amps": [1.0, 0.6, 0.4],
		"decays": [0.06, 0.045, 0.03], "lp": 6000.0, "grit": 0.014 },
	"plastic": { "hard": false, "db": -2.0, "thump": 0.35, "modes": [330.0, 720.0], "amps": [1.0, 0.5],
		"decays": [0.04, 0.03], "lp": 3500.0, "grit": 0.012 },
	"fabric": { "hard": false, "db": -4.0, "thump": 0.8, "modes": [110.0, 190.0], "amps": [1.0, 0.5],
		"decays": [0.03, 0.02], "lp": 900.0, "grit": 0.025 },
	"foliage": { "hard": false, "db": -5.0, "thump": 0.1, "modes": [], "amps": [], "decays": [], "lp": 2400.0, "grit": 0.060 },
	"electronics": { "hard": true, "db": 0.0, "thump": 0.2, "modes": [780.0, 1700.0, 2900.0], "amps": [1.0, 0.7, 0.5],
		"decays": [0.07, 0.05, 0.04], "lp": 5500.0, "grit": 0.010 },
	"flesh": { "hard": false, "db": -1.0, "thump": 1.0, "modes": [95.0, 160.0], "amps": [1.0, 0.6],
		"decays": [0.05, 0.035], "lp": 1300.0, "grit": 0.030 },
	"wall": { "hard": true, "db": 0.0, "thump": 0.5, "modes": [150.0, 300.0, 520.0], "amps": [1.0, 0.6, 0.4],
		"decays": [0.04, 0.03, 0.02], "lp": 3200.0, "grit": 0.025 },
	"default": { "hard": false, "db": 0.0, "thump": 0.4, "modes": [260.0, 540.0], "amps": [1.0, 0.5],
		"decays": [0.04, 0.03], "lp": 3000.0, "grit": 0.015 },
}

## Footsteps by surface, all deliberately low and dull (high-passed noise and ring tones sound tinny): the heel thump
## leads, the scuff is a soft low-passed noise. db = level trim, thump = [start Hz, end Hz, decay s, gain] (the heel),
## scuff = [low-pass Hz, high-pass Hz, decay s, gain] (the sole on the surface), ring = { freqs, amps, decays, gain }
## (a hard floor's click), again = a second, softer scuff that follows (gravel, grass).
const FOOTSTEPS := {
	"wood": { "db": -3.0, "thump": [102.0, 56.0, 0.052, 1.0], "scuff": [1300.0, 140.0, 0.020, 0.34] },
	"tile": { "db": -3.0, "thump": [112.0, 66.0, 0.042, 1.0], "scuff": [1300.0, 180.0, 0.015, 0.30] },
	"stone": { "db": -3.0, "thump": [115.0, 72.0, 0.034, 1.0], "scuff": [1300.0, 200.0, 0.016, 0.32] },
	"concrete": { "db": 0.0, "thump": [105.0, 64.0, 0.030, 1.0], "scuff": [2000.0, 220.0, 0.020, 0.45] },
	"carpet": { "db": -6.0, "thump": [95.0, 62.0, 0.030, 0.65], "scuff": [750.0, 0.0, 0.030, 0.45] },
	"outdoor": { "db": -2.0, "thump": [90.0, 58.0, 0.040, 0.9], "scuff": [1600.0, 180.0, 0.040, 0.5], "again": 0.028 },
}

## Rendered sounds: "profile#variant" -> { stream, level_db }.
static var _cache: Dictionary = {}


# --- Choosing a profile (no rendering) ------------------------------------------------------

## The band (`light` / `medium` / `heavy`) a projectile of penetration `power` is voiced in.
static func band(power: float) -> String:
	if power < SoundConfig.light_power_max:
		return "light"
	if power >= SoundConfig.heavy_power_min:
		return "heavy"
	return "medium"


## The shot profile of `gun`; a gun without its own recipe borrows its band's from `power`.
static func shot_profile(gun: StringName, power: float = 1.0) -> StringName:
	var id := String(gun)
	if not SHOTS.has(id):
		id = BAND_SHOT[band(power)]
	return StringName("shot/" + id)


## The impact profile for a hit on `material` with `outcome` (`blocked` / `penetrate` / `ricochet` / `punch`)
## by a projectile of `power`; &"" when `outcome` is none of those.
static func impact_profile(material: String, outcome: StringName, power: float = 1.0) -> StringName:
	var mat := "wall" if material == "" else (material if MATERIALS.has(material) else "default")
	if outcome == &"punch":
		return StringName("impact/%s/punch" % mat)
	if not OUTCOMES.has(outcome):
		return &""
	return StringName("impact/%s/%s/%s" % [mat, outcome, band(power)])


## The footstep profile on `surface` (a SoundSurface name); an unknown surface is the open ground.
static func footstep_profile(surface: StringName, running: bool) -> StringName:
	var s := String(surface) if FOOTSTEPS.has(String(surface)) else "outdoor"
	return StringName("footstep/%s/%s" % [s, "run" if running else "walk"])


## The reload profile for `gun` at `stage` (&"out" or &"in"); a gun without its own recipe borrows its band's from
## `power`. &"" when `stage` is neither.
static func reload_profile(gun: StringName, stage: StringName, power: float = 1.0) -> StringName:
	if not RELOAD_STAGES.has(String(stage)):
		return &""
	var id := String(gun)
	if not RELOADS.has(id):
		id = BAND_SHOT[band(power)]
	return StringName("reload/%s/%s" % [id, stage])


## Every profile the bank can voice (what the pre-warm and the sound dump walk through).
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	for gun: String in SHOTS:
		out.append(StringName("shot/" + gun))
	for gun: String in RELOADS:
		for stage in RELOAD_STAGES:
			out.append(StringName("reload/%s/%s" % [gun, stage]))
	for mat: String in MATERIALS:
		out.append(StringName("impact/%s/punch" % mat))
		for outcome in OUTCOMES:
			for b in BAND_NAMES:
				out.append(StringName("impact/%s/%s/%s" % [mat, outcome, b]))
	for surface: String in FOOTSTEPS:
		out.append(StringName("footstep/%s/walk" % surface))
		out.append(StringName("footstep/%s/run" % surface))
	return out


# --- Rendering ------------------------------------------------------------------------------

## The sound of `profile`, variant number `variant`: { stream: AudioStreamWAV, level_db: float } (the profile's own
## level trim in dB). Rendered the first time it is asked for, then cached. {} for a profile that does not exist.
static func sound(profile: StringName, variant: int = 0) -> Dictionary:
	var key := "%s#%d" % [profile, variant]
	if _cache.has(key):
		return _cache[key]
	var recipe := recipe_for(profile)
	if recipe.is_empty():
		return {}
	var entry := { "stream": SoundSynth.render(recipe, hash(key)), "level_db": float(recipe.get("level_db", 0.0)) }
	_cache[key] = entry
	return entry


## The synthesis recipe of `profile` ({} if unknown).
static func recipe_for(profile: StringName) -> Dictionary:
	var p := String(profile).split("/")
	match p[0]:
		"shot":
			return _shot(p[1]) if p.size() == 2 and SHOTS.has(p[1]) else {}
		"impact":
			if p.size() == 3 and p[2] == "punch" and MATERIALS.has(p[1]):
				return _impact(p[1], "punch", "medium")
			if p.size() == 4 and MATERIALS.has(p[1]) and OUTCOMES.has(StringName(p[2])) and BANDS.has(p[3]):
				return _impact(p[1], p[2], p[3])
		"footstep":
			if p.size() == 3 and FOOTSTEPS.has(p[1]) and (p[2] == "walk" or p[2] == "run"):
				return _footstep(p[1], p[2] == "run")
		"reload":
			if p.size() == 3 and RELOADS.has(p[1]) and RELOAD_STAGES.has(p[2]):
				return _reload(p[1], p[2])
	return {}


## Forget every rendered sound (for tests).
static func clear_cache() -> void:
	_cache.clear()


## How many sounds are rendered and cached.
static func cached_count() -> int:
	return _cache.size()


## The recipe of `gun`'s report: the sharp crack, the mid-range bark, the low body thump and the room's tail.
static func _shot(gun: String) -> Dictionary:
	var g: Dictionary = SHOTS[gun]
	var crack: Array = g["crack"]
	var bark: Array = g["bark"]
	var body: Array = g["body"]
	var tail: Array = g["tail"]
	return {
		"length": g["length"], "level_db": g["level_db"], "drive": 2.0,
		"layers": [
			{ "type": "noise", "gain": crack[2], "decay": crack[0], "lp": crack[1], "hp": 500.0, "attack": 0.0003 },
			{ "type": "noise", "gain": bark[2], "decay": bark[0], "lp": bark[1], "hp": 150.0, "attack": 0.0006 },
			{ "type": "tone", "gain": body[3], "freq": body[0], "freq_end": body[1], "sweep": 0.025, "decay": body[2] },
			{ "type": "noise", "gain": tail[2], "decay": tail[0], "lp": tail[1], "hp": 120.0, "delay": 0.012, "attack": 0.006 },
		],
	}


## The recipe of a hit on `material` with `outcome` by a round of weight `band_id`: the material's ring, the crack, the
## low body thump every hit has, and what the outcome adds (a crunch through, a ping or whine off).
static func _impact(material: String, outcome: String, band_id: String) -> Dictionary:
	var m: Dictionary = MATERIALS[material]
	var b: Dictionary = BANDS[band_id]
	var pitch: float = b["pitch"] if outcome != "punch" else 1.0
	var crack: float = b["crack"] if outcome != "punch" else 1.0
	var body: float = b["body"] if outcome != "punch" else 0.8
	var sub: float = b["sub"] if outcome != "punch" else 0.0
	var hard: bool = m["hard"]
	var thump: float = m["thump"]
	var heft: float = m.get("heft", 0.0) if outcome != "punch" else 0.0
	var grit: float = m["grit"]
	var lp: float = m["lp"]
	# How hard the material rings in this outcome: a ricochet off something hard keeps ringing, one off
	# something soft barely does, a punch only taps it.
	var ring_gain := 0.35
	var ring_time := 1.0
	match outcome:
		"penetrate":
			ring_gain = 0.28
			ring_time = 0.8
		"ricochet":
			ring_gain = 1.0 if hard else 0.45
			ring_time = 1.6 if hard else 0.8
		"punch":
			ring_gain = 0.4
	if hard and outcome != "ricochet":
		ring_gain *= 0.7  # a hard thing struck without glancing off rings less than it thuds
		ring_gain *= 1.0 - 0.35 * heft
	var layers := []
	var length := 0.12
	var freqs: Array = []
	var decays: Array = []
	# The rings take only half the band's pitch shift: a light round must not turn a hard material into a tinkle.
	var ring_pitch := 1.0 + (pitch - 1.0) * 0.5
	for f: float in m["modes"]:
		freqs.append(f * ring_pitch)
	for d: float in m["decays"]:
		decays.append(d * ring_time)
		length = maxf(length, d * ring_time * 4.0 + 0.04)
	if not freqs.is_empty():
		layers.append({ "type": "modes", "gain": ring_gain, "freqs": freqs, "amps": m["amps"], "decays": decays, "detune": 0.03 })
	layers.append({ "type": "noise", "gain": (0.35 if outcome == "punch" else 0.7) * crack, "decay": grit + 0.004,
		"lp": lp, "hp": 120.0, "attack": 0.0004 })
	# Every hit has weight, whatever it struck: a low thump (the material only decides how much of it), and under a
	# heavier round a deep boom as well. This is what makes a strong hit land as one rather than ring thinly.
	layers.append({ "type": "tone", "gain": (0.65 + 0.35 * thump) * body * (1.0 + 0.8 * heft), "freq": 150.0 * pitch,
		"freq_end": 55.0 * pitch, "sweep": 0.018, "decay": 0.06 + 0.03 * thump + 0.03 * body + 0.04 * heft })
	if sub > 0.0:
		layers.append({ "type": "tone", "gain": sub * (0.8 + 0.4 * thump), "freq": 72.0 * pitch, "freq_end": 40.0 * pitch,
			"sweep": 0.03, "decay": 0.07 + 0.05 * sub })
		length = maxf(length, 0.14 + 0.06 * sub)
	match outcome:
		"penetrate":
			# Through and out: a crunch of what it broke, a hiss of air behind it, a deeper thud.
			layers.append({ "type": "noise", "gain": 0.6 * crack, "decay": grit * 2.0 + 0.01, "lp": lp * 0.7, "hp": 120.0,
				"delay": 0.004, "attack": 0.001 })
			layers.append({ "type": "noise", "gain": 0.15 * crack, "decay": 0.05, "lp": 7000.0, "hp": 2500.0,
				"delay": 0.012, "attack": 0.004 })
			layers.append({ "type": "tone", "gain": 0.35 + 0.4 * thump, "freq": 120.0 * pitch, "freq_end": 48.0 * pitch,
				"sweep": 0.02, "decay": 0.08, "delay": 0.006 })
			length = maxf(length, 0.22)
		"ricochet":
			layers.append({ "type": "noise", "gain": 0.5 * crack, "decay": 0.005, "lp": 9500.0, "hp": 2500.0 })
			if hard:
				# The whine of a spinning, flattened round: high, falling.
				layers.append({ "type": "tone", "gain": 0.35, "freq": 4300.0 * pitch, "freq_end": 1500.0 * pitch,
					"sweep": 0.11, "decay": 0.22 })
				length = maxf(length, 0.7)
			else:
				layers.append({ "type": "noise", "gain": 0.5 * crack, "decay": 0.05, "lp": 9000.0, "hp": 2500.0, "attack": 0.003 })
				length = maxf(length, 0.2)
		"punch":
			if material == "flesh":
				layers.append({ "type": "noise", "gain": 0.5, "decay": 0.018, "lp": 3500.0, "hp": 600.0 })
	return {
		"length": clampf(length, 0.12, 0.9),
		"level_db": (-6.0 if outcome == "punch" else float(b["db"])) + float(m["db"]),
		"layers": layers,
	}


## The recipe of a step on `surface`: the heel thump, a softer toe tap after it, the scuff and a faint cloth rustle.
static func _footstep(surface: String, running: bool) -> Dictionary:
	var s: Dictionary = FOOTSTEPS[surface]
	var thump: Array = s["thump"]
	var scuff: Array = s["scuff"]
	var punch := 1.2 if running else 1.0
	var quick := 0.85 if running else 1.0
	var pitch := 1.08 if running else 1.0
	# A step is two beats, not one: the heel lands, then the ball of the foot and toes tap down a few ms later
	# (sooner and flatter at a run). The toe is a little higher, shorter and softer than the heel, in the same dull tone.
	var toe_at := 0.045 if running else 0.062
	var layers := [
		{ "type": "tone", "gain": thump[3] * punch, "freq": thump[0] * pitch, "freq_end": thump[1] * pitch,
			"sweep": 0.015, "decay": thump[2] * quick },
		{ "type": "noise", "gain": scuff[3] * punch, "lp": scuff[0], "hp": scuff[1], "decay": scuff[2] * quick,
			"attack": 0.0006 },
		{ "type": "tone", "gain": thump[3] * 0.4 * punch, "freq": thump[0] * 1.2 * pitch, "freq_end": thump[1] * 1.15 * pitch,
			"sweep": 0.01, "decay": thump[2] * 0.7 * quick, "delay": toe_at },
		{ "type": "noise", "gain": scuff[3] * 0.5 * punch, "lp": scuff[0], "hp": scuff[1],
			"decay": scuff[2] * 0.7 * quick, "delay": toe_at, "attack": 0.001 },
		# Cloth and the weight shifting: a faint low rustle under the whole step.
		{ "type": "noise", "gain": 0.1 * float(s.get("rustle", 1.0)), "lp": 1400.0, "hp": 250.0, "decay": 0.09,
			"delay": 0.012, "attack": 0.02 },
	]
	var length: float = maxf(thump[2], scuff[2]) * 6.0
	length = maxf(length, toe_at + scuff[2] * 5.0)
	if s.has("ring"):
		var ring: Dictionary = s["ring"]
		layers.append({ "type": "modes", "gain": ring["gain"] * punch, "freqs": ring["freqs"], "amps": ring["amps"],
			"decays": ring["decays"], "detune": 0.03 })
		for d: float in ring["decays"]:
			length = maxf(length, d * 5.0)
	if s.has("again"):
		layers.append({ "type": "noise", "gain": scuff[3] * 0.6 * punch, "lp": scuff[0] * 0.8, "hp": scuff[1],
			"decay": scuff[2] * quick, "delay": s["again"], "attack": 0.001 })
		length += float(s["again"])
	return { "length": clampf(length, 0.1, 0.4), "level_db": (-1.0 if running else -5.0) + float(s["db"]),
		"vary": 0.22, "layers": layers }


## A reload in two beats, each kept to dry, quiet clicks. `out`: the release click and a faint tick of the magazine
## dropping free. `in`: a seat click, then a rack click.
static func _reload(gun: String, stage: String) -> Dictionary:
	var g: Dictionary = RELOADS[gun]
	var p: float = g["pitch"]
	var layers := []
	var length := 0.3
	if stage == "out":
		# One dry click as the catch lets go, and a faint tick of the magazine dropping free.
		layers = [
			{ "type": "noise", "gain": 0.8, "decay": 0.004, "lp": 5000.0 * p, "hp": 1800.0, "attack": 0.0002 },
			{ "type": "tone", "gain": 0.15, "freq": 140.0 * p, "freq_end": 90.0 * p, "sweep": 0.012, "decay": 0.025, "delay": 0.14 },
			{ "type": "noise", "gain": 0.2, "decay": 0.008, "lp": 2500.0, "hp": 400.0, "delay": 0.14 },
		]
		length = 0.22
	else:
		var rack: float = g["rack"]
		# Two small clicks: the magazine seating, then the action racked. No rasp, ring or slam.
		layers = [
			{ "type": "noise", "gain": 0.5, "decay": 0.007, "lp": 3800.0 * p, "hp": 1200.0, "delay": 0.09, "attack": 0.0003 },
			{ "type": "tone", "gain": 0.12, "freq": float(g["seat"]), "freq_end": float(g["seat"]) * 0.6, "sweep": 0.01,
				"decay": 0.02, "delay": 0.09 },
			{ "type": "noise", "gain": 0.6, "decay": 0.009, "lp": 4000.0 * p, "hp": 900.0, "delay": 0.09 + rack, "attack": 0.0003 },
		]
		length = 0.09 + rack + 0.1
	return { "length": length, "level_db": float(g["db"]) + (-6.0 if stage == "out" else -4.0), "vary": 0.06, "layers": layers }
