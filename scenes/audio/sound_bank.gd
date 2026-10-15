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
##   band      the projectile's weight, from its penetration power (`SoundConfig.light_power_max` /
##             `heavy_power_min`): `light` (SMG), `medium` (pistol), `heavy` (rifle).
##   surface   the floor underfoot (SoundSurface): wood tile stone concrete carpet outdoor.
##   gait      `walk` or `run`.
##   stage     a reload's `out` (the magazine released and drawn) or `in` (seated, then the action racked).
##   kind      a grenade's `stun` or `frag`: `throw/<kind>`, `grenade/<kind>/<surface>` (a bounce, voiced by the floor it
##             lands on), `explosion/<kind>`; and the one `tinnitus/whine` a deafened listener hears.
##   vehicle   a vehicle's kind (`car`, `van`; an unknown one is voiced as a car): `engine/<vehicle>` (a seamless loop the
##             service pitches by the revs), `ignition/<vehicle>`, `door/<vehicle>/<open|close|slide_open|slide_close>`;
##             the tyres' `skid/tyre` (a loop); and `crash/<material>/<band>`, the band by the closing speed
##             (SoundConfig.crash_medium_speed / crash_heavy_speed), `flesh` for a character struck.

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
	"composite": { "hard": true, "db": 0.0, "thump": 0.55, "modes": [380.0, 820.0, 1450.0], "amps": [1.0, 0.55, 0.3],
		"decays": [0.05, 0.035, 0.025], "lp": 4200.0, "grit": 0.014 },
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

## The grenades (`docs/grenades.md`, G14). The kinds a profile may name:
const GRENADE_KINDS: Array[String] = ["stun", "frag"]
## The throw: the lever springs off with a metal ping (ping = [pitch scale, gain]: the stun's canister is lighter) and the
## arm whips the grenade away in a whoosh (whoosh = gain). db trims the level.
const THROWS := {
	"frag": { "db": -2.0, "ping": [1.0, 0.55], "whoosh": 1.0 },
	"stun": { "db": -3.0, "ping": [0.82, 0.4], "whoosh": 0.9 },
}
## The bursts. frag: a big, low blast with a long tail (a crack, the boom and the sub-bass under it, the roar and a rumble
## that rolls on, debris pattering down). stun: the opposite, a sharp, very loud bang that is over at once (a crack, a ringing
## shell of high partials and a short thump). db trims the level.
const EXPLOSIONS := {
	"frag": { "db": 2.0 },
	"stun": { "db": 3.0 },
}
## The body of a grenade: the partials it rings at when it strikes a floor (Hz, level, decay s). A frag is a heavier iron
## shell, a stun a thin aluminium canister.
const GRENADE_BODIES := {
	"frag": { "db": 0.0, "modes": [740.0, 1560.0, 2480.0], "amps": [1.0, 0.7, 0.45], "decays": [0.07, 0.05, 0.035] },
	"stun": { "db": -2.0, "modes": [1050.0, 2300.0, 3500.0], "amps": [1.0, 0.7, 0.5], "decays": [0.05, 0.035, 0.025] },
}
## What a floor does to a grenade landing on it, by SoundSurface name: db = level trim, thud = [start Hz, end Hz, decay s,
## gain] (the floor taking the weight), knock = [low-pass Hz, high-pass Hz, decay s, gain] (the crack of contact), ring =
## how much of the shell's ring survives (a hard floor leaves it, carpet and grass swallow it).
const GRENADE_SURFACES := {
	"wood": { "db": 0.0, "thud": [180.0, 90.0, 0.035, 0.9], "knock": [2200.0, 300.0, 0.012, 0.5], "ring": 0.6 },
	"tile": { "db": 2.0, "thud": [210.0, 110.0, 0.030, 0.6], "knock": [5000.0, 600.0, 0.008, 0.8], "ring": 1.0 },
	"stone": { "db": 2.0, "thud": [200.0, 100.0, 0.030, 0.7], "knock": [4200.0, 500.0, 0.009, 0.8], "ring": 0.9 },
	"concrete": { "db": 1.0, "thud": [170.0, 85.0, 0.030, 0.8], "knock": [3800.0, 400.0, 0.010, 0.7], "ring": 0.55 },
	"carpet": { "db": -8.0, "thud": [120.0, 70.0, 0.040, 0.8], "knock": [900.0, 0.0, 0.020, 0.3], "ring": 0.08 },
	"outdoor": { "db": -3.0, "thud": [140.0, 80.0, 0.040, 0.8], "knock": [1800.0, 200.0, 0.020, 0.45], "ring": 0.2 },
}
## The tinnitus whine is a seamless loop (the voice runs for as long as the listener is deaf): its tones are whole numbers
## of cycles in `TINNITUS_LOOP` s, the pair a few Hz apart beating against each other.
const TINNITUS_LOOP := 0.8
const TINNITUS_TONES := [[4300.0, 1.0], [4305.0, 0.9], [6850.0, 0.35]]

## The vehicles. engine: the loop's firing train, `rate` firings a second at idle (whole firings per `ENGINE_LOOP` s and a
## whole number of `pattern`s, so it loops without a seam; the service pitches it up with the revs), each a noise burst
## of `burst` s through `lp`, its level cycling through `pattern` (the cylinders, so it chugs rather than buzzes) and rung
## through the exhaust's resonances `pipe` ([Hz, level, decay s]); `noise` is how much of the raw burst is heard. crank:
## the starter's [strokes, gap s, whine Hz]; door: the pitch scale (a heavier door lower) and level of its clunks; slide: a
## sliding door. db trims each sound's level. The van is the bigger, slower-firing, deeper engine.
const ENGINE_LOOP := 1.0
const VEHICLES := {
	"car": {
		"db": 0.0, "rate": 28.0, "pattern": [1.0, 0.72, 0.9, 0.66], "burst": 0.006, "lp": 1800.0, "noise": 0.6,
		"pipe": [[64.0, 0.55, 0.05], [128.0, 0.8, 0.035], [210.0, 0.9, 0.025], [340.0, 0.75, 0.018], [560.0, 0.45, 0.012],
			[900.0, 0.2, 0.008]],
		"crank": [4, 0.105, 290.0], "door": [1.0, 0.0], "slide": false,
	},
	"van": {
		"db": 1.0, "rate": 20.0, "pattern": [1.0, 0.86, 0.95, 0.8], "burst": 0.009, "lp": 1200.0, "noise": 0.4,
		"pipe": [[44.0, 0.8, 0.06], [88.0, 0.9, 0.045], [146.0, 0.85, 0.03], [235.0, 0.6, 0.02], [390.0, 0.35, 0.014],
			[640.0, 0.15, 0.01]],
		"crank": [5, 0.12, 230.0], "door": [0.82, 1.0], "slide": true,
	},
}
const DOOR_STAGES: Array[String] = ["open", "close", "slide_open", "slide_close"]
## A crash by how hard it was, from the closing speed: db trims the level, body scales the vehicle's mass thumping
## home, crunch the sheet metal folding, length the clip (s); glass = shards tinkling after it, debris = bits pattering.
const CRASH_BANDS := {
	"light": { "db": -6.0, "body": 0.7, "crunch": 0.55, "length": 0.4, "glass": 0.0, "debris": 0.0 },
	"medium": { "db": 0.0, "body": 1.0, "crunch": 1.0, "length": 0.55, "glass": 0.0, "debris": 0.6 },
	"heavy": { "db": 4.0, "body": 1.5, "crunch": 1.4, "length": 0.75, "glass": 1.0, "debris": 1.0 },
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


## The throw profile of a grenade of `kind`; &"" for an unknown kind.
static func throw_profile(kind: StringName) -> StringName:
	return StringName("throw/" + String(kind)) if THROWS.has(String(kind)) else &""


## The clatter profile of a grenade of `kind` landing on `surface` (a SoundSurface name; an unknown surface is the open
## ground); &"" for an unknown kind.
static func grenade_profile(kind: StringName, surface: StringName) -> StringName:
	if not GRENADE_BODIES.has(String(kind)):
		return &""
	var s := String(surface) if GRENADE_SURFACES.has(String(surface)) else "outdoor"
	return StringName("grenade/%s/%s" % [kind, s])


## The explosion profile of a burst of `kind`; &"" for an unknown kind.
static func explosion_profile(kind: StringName) -> StringName:
	return StringName("explosion/" + String(kind)) if EXPLOSIONS.has(String(kind)) else &""


## The whine a deafened listener hears.
static func tinnitus_profile() -> StringName:
	return &"tinnitus/whine"


## A vehicle kind the bank voices: `kind` itself, or a car for an unknown one.
static func vehicle_kind(kind: StringName) -> String:
	return String(kind) if VEHICLES.has(String(kind)) else "car"


## The engine loop of a vehicle of `kind`.
static func engine_profile(kind: StringName) -> StringName:
	return StringName("engine/" + vehicle_kind(kind))


## The starter cranking and the engine catching, for a vehicle of `kind`.
static func ignition_profile(kind: StringName) -> StringName:
	return StringName("ignition/" + vehicle_kind(kind))


## A door of a vehicle of `kind` at `stage` (`open`, `close`, `slide_open`, `slide_close`; a slide is voiced only for a
## kind with a sliding door). &"" for any other stage.
static func door_profile(kind: StringName, stage: StringName) -> StringName:
	var k := vehicle_kind(kind)
	if not DOOR_STAGES.has(String(stage)) or (String(stage).begins_with("slide") and not VEHICLES[k]["slide"]):
		return &""
	return StringName("door/%s/%s" % [k, stage])


## The tyres sliding (a loop).
static func skid_profile() -> StringName:
	return &"skid/tyre"


## The crash band (`light` / `medium` / `heavy`) of an impact at closing speed `speed` (px/s).
static func crash_band(speed: float) -> String:
	if speed >= SoundConfig.crash_heavy_speed:
		return "heavy"
	if speed >= SoundConfig.crash_medium_speed:
		return "medium"
	return "light"


## A vehicle striking `material` (a struck surface's; "" is a wall, `flesh` a character) at closing speed `speed`.
static func crash_profile(material: String, speed: float) -> StringName:
	var mat := "wall" if material == "" else (material if MATERIALS.has(material) else "default")
	return StringName("crash/%s/%s" % [mat, crash_band(speed)])


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
	for kind: String in GRENADE_KINDS:
		out.append(StringName("throw/" + kind))
		out.append(StringName("explosion/" + kind))
		for surface: String in GRENADE_SURFACES:
			out.append(StringName("grenade/%s/%s" % [kind, surface]))
	out.append(tinnitus_profile())
	for kind: String in VEHICLES:
		out.append(StringName("engine/" + kind))
		out.append(StringName("ignition/" + kind))
		for stage in DOOR_STAGES:
			if not stage.begins_with("slide") or VEHICLES[kind]["slide"]:
				out.append(StringName("door/%s/%s" % [kind, stage]))
	out.append(skid_profile())
	for mat: String in MATERIALS:
		for b: String in CRASH_BANDS:
			out.append(StringName("crash/%s/%s" % [mat, b]))
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
		"throw":
			return _throw(p[1]) if p.size() == 2 and THROWS.has(p[1]) else {}
		"grenade":
			if p.size() == 3 and GRENADE_BODIES.has(p[1]) and GRENADE_SURFACES.has(p[2]):
				return _grenade(p[1], p[2])
		"explosion":
			return _explosion(p[1]) if p.size() == 2 and EXPLOSIONS.has(p[1]) else {}
		"tinnitus":
			return _tinnitus() if p.size() == 2 and p[1] == "whine" else {}
		"engine":
			return _engine(p[1]) if p.size() == 2 and VEHICLES.has(p[1]) else {}
		"ignition":
			return _ignition(p[1]) if p.size() == 2 and VEHICLES.has(p[1]) else {}
		"door":
			if p.size() == 3 and VEHICLES.has(p[1]) and door_profile(StringName(p[1]), StringName(p[2])) == profile:
				return _door(p[1], p[2])
		"skid":
			return _skid() if p.size() == 2 and p[1] == "tyre" else {}
		"crash":
			if p.size() == 3 and MATERIALS.has(p[1]) and CRASH_BANDS.has(p[2]):
				return _crash(p[1], p[2])
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


## A grenade leaving the hand: the lever springs off with a ping and the arm whips it away in a rising whoosh.
static func _throw(kind: String) -> Dictionary:
	var t: Dictionary = THROWS[kind]
	var ping: Array = t["ping"]
	var scale: float = ping[0]
	var gain: float = t["whoosh"]
	return {
		"length": 0.45, "level_db": t["db"], "vary": 0.1,
		"layers": [
			{ "type": "modes", "gain": ping[1], "freqs": [3300.0 * scale, 5100.0 * scale, 7400.0 * scale], "amps": [1.0, 0.6, 0.35],
				"decays": [0.05, 0.035, 0.02], "detune": 0.02 },
			{ "type": "noise", "gain": gain, "attack": 0.10, "decay": 0.09, "lp": 2600.0, "hp": 600.0, "delay": 0.02 },
			{ "type": "noise", "gain": gain * 0.5, "attack": 0.14, "decay": 0.12, "lp": 900.0, "hp": 150.0, "delay": 0.04 },
		],
	}


## A grenade of `kind` landing on `surface`: the floor's thud and the crack of contact, the shell's ring (as much as the floor
## leaves), and a smaller second tick as it rattles over.
static func _grenade(kind: String, surface: String) -> Dictionary:
	var b: Dictionary = GRENADE_BODIES[kind]
	var s: Dictionary = GRENADE_SURFACES[surface]
	var thud: Array = s["thud"]
	var knock: Array = s["knock"]
	var ring: float = s["ring"]
	return {
		"length": 0.4, "level_db": float(b["db"]) + float(s["db"]), "vary": 0.12,
		"layers": [
			{ "type": "tone", "gain": thud[3], "freq": thud[0], "freq_end": thud[1], "sweep": 0.015, "decay": thud[2] },
			{ "type": "noise", "gain": knock[3], "lp": knock[0], "hp": knock[1], "decay": knock[2], "attack": 0.0003 },
			{ "type": "modes", "gain": 0.55 * ring, "freqs": b["modes"], "amps": b["amps"], "decays": b["decays"], "detune": 0.03 },
			{ "type": "noise", "gain": knock[3] * 0.4, "lp": knock[0], "hp": knock[1], "decay": knock[2], "delay": 0.07, "attack": 0.0003 },
			{ "type": "modes", "gain": 0.2 * ring, "freqs": b["modes"], "amps": b["amps"], "decays": b["decays"], "delay": 0.07, "detune": 0.03 },
		],
	}


## A burst of `kind`. The frag fills the second (the longest a profile may run), the stun's bang is over in under half of it.
static func _explosion(kind: String) -> Dictionary:
	var level := float(EXPLOSIONS[kind]["db"])
	if kind == "frag":
		return {
			"length": 0.97, "level_db": level, "drive": 2.2,
			"layers": [
				{ "type": "noise", "gain": 1.0, "decay": 0.018, "lp": 8000.0, "hp": 250.0, "attack": 0.0005 },
				{ "type": "tone", "gain": 1.6, "freq": 105.0, "freq_end": 32.0, "sweep": 0.09, "decay": 0.30 },
				{ "type": "tone", "gain": 1.2, "freq": 52.0, "freq_end": 26.0, "sweep": 0.15, "decay": 0.55 },
				{ "type": "noise", "gain": 1.1, "decay": 0.30, "lp": 520.0, "hp": 30.0, "attack": 0.008, "delay": 0.005 },
				{ "type": "noise", "gain": 0.6, "decay": 0.12, "lp": 2200.0, "hp": 200.0, "attack": 0.003 },
				{ "type": "noise", "gain": 0.55, "decay": 0.20, "lp": 380.0, "hp": 20.0, "attack": 0.08, "delay": 0.12 },
				{ "type": "noise", "gain": 0.18, "decay": 0.22, "lp": 3500.0, "hp": 700.0, "attack": 0.05, "delay": 0.2 },
			],
		}
	return {
		"length": 0.42, "level_db": level, "drive": 3.5,
		"layers": [
			{ "type": "noise", "gain": 1.5, "decay": 0.012, "lp": 11000.0, "hp": 1800.0, "attack": 0.0002 },
			{ "type": "noise", "gain": 1.0, "decay": 0.05, "lp": 9000.0, "hp": 900.0, "attack": 0.0004 },
			{ "type": "modes", "gain": 0.55, "freqs": [2900.0, 4300.0, 6100.0], "amps": [1.0, 0.8, 0.5], "decays": [0.09, 0.06, 0.04], "detune": 0.02 },
			{ "type": "tone", "gain": 0.55, "freq": 150.0, "freq_end": 70.0, "sweep": 0.02, "decay": 0.05 },
			{ "type": "noise", "gain": 0.35, "decay": 0.12, "lp": 4500.0, "hp": 600.0, "attack": 0.004, "delay": 0.015 },
		],
	}


## The ringing in the ears: a thin whine that loops without a seam for as long as it is played.
static func _tinnitus() -> Dictionary:
	var layers := []
	for tone: Array in TINNITUS_TONES:
		layers.append({ "type": "tone", "gain": tone[1], "freq": tone[0], "freq_end": tone[0], "decay": 100000.0 })
	return { "length": TINNITUS_LOOP, "level_db": -6.0, "loop": true, "layers": layers }


## A running engine at idle: one period of its firing train, every firing a burst rung through the exhaust's resonances,
## the cylinders each a little different (`pattern`) and never quite even (`spread`, `jitter`), so it chugs rather than
## buzzes. A seamless loop the service plays faster as the revs climb.
static func _engine(kind: String) -> Dictionary:
	var v: Dictionary = VEHICLES[kind]
	var freqs := []
	var amps := []
	var decays := []
	for pipe: Array in v["pipe"]:
		freqs.append(pipe[0])
		amps.append(pipe[1])
		decays.append(pipe[2])
	var rate: float = v["rate"]
	return {
		"length": ENGINE_LOOP, "level_db": -2.0 + float(v["db"]), "loop": true, "drive": 1.4,
		"layers": [
			{ "type": "pulses", "rate": rate, "pattern": v["pattern"], "spread": 0.08, "jitter": 0.025, "burst": v["burst"],
				"lp": v["lp"], "hp": 25.0, "noise": v["noise"], "freqs": freqs, "amps": amps, "decays": decays,
				"wobble": [2, 0.05] },
			# The block's hum at the firing rate and its double: whole cycles of the loop, so they join without a seam.
			{ "type": "tone", "gain": 0.06, "freq": rate, "decay": 100000.0 },
			{ "type": "tone", "gain": 0.05, "freq": rate * 2.0, "decay": 100000.0 },
			# The valves ticking over, faint and high.
			{ "type": "pulses", "rate": rate * 2.0, "burst": 0.0015, "lp": 5200.0, "hp": 1800.0, "noise": 0.05, "spread": 0.3 },
		],
	}


## The key turned: the starter cranks a few strokes (a geared whine that slows at each compression), the engine
## catches with a stumble of firings that race up and settle back to idle.
static func _ignition(kind: String) -> Dictionary:
	var v: Dictionary = VEHICLES[kind]
	var crank: Array = v["crank"]
	var strokes: int = crank[0]
	var gap: float = crank[1]
	var whine: float = crank[2]
	var low: float = v["pipe"][0][0]
	var layers := []
	for i in strokes:
		var stroke := i * gap
		layers.append({ "type": "noise", "gain": 0.45, "attack": 0.02, "decay": gap * 0.35, "lp": 2400.0, "hp": 260.0, "delay": stroke })
		layers.append({ "type": "tone", "gain": 0.3, "freq": whine * 1.1, "freq_end": whine * 0.85, "sweep": gap * 0.6,
			"decay": gap * 0.45, "delay": stroke })
		layers.append({ "type": "tone", "gain": 0.4, "freq": low * 1.6, "freq_end": low * 1.1, "sweep": 0.02, "decay": 0.04, "delay": stroke })
	# It catches: firings close up as it revs, then open out to the idle's beat.
	var at := strokes * gap + 0.02
	var idle := 1.0 / float(v["rate"])
	var k := 0
	while at < 0.93:
		var rev := clampf(float(k) / 7.0, 0.0, 1.0)
		var settle := clampf((at - (strokes * gap + 0.25)) / 0.3, 0.0, 1.0)
		var spacing := lerpf(lerpf(idle * 1.6, idle * 0.62, rev), idle * 0.95, settle)
		var level := lerpf(lerpf(0.6, 1.2, rev), 0.75, settle) * (0.85 if k % 2 == 1 else 1.0)
		layers.append({ "type": "tone", "gain": level, "freq": low * 2.2, "freq_end": low * 1.2, "sweep": 0.012, "decay": 0.03, "delay": at })
		layers.append({ "type": "noise", "gain": level * 0.6, "decay": float(v["burst"]) * 1.5, "lp": float(v["lp"]), "hp": 50.0, "delay": at })
		at += spacing
		k += 1
	return { "length": 0.98, "level_db": -2.0 + float(v["db"]), "drive": 1.3, "layers": layers }


## A door of `kind`, in a reload's register: dry mechanical clicks over a low thunk, nothing that creaks or rings. `open`:
## the handle's click, the latch letting go with a knock, and the door coming off its seal in a soft low thump. `close`:
## the slam, the door's weight thumping home with the body's low panels, the latch clicking shut into it and a dull
## knock of the trim. A sliding door's `slide_open` rolls back on its runners into the stop, its `slide_close` is the
## heavy thunk of it shutting with the catch clicking home.
static func _door(kind: String, stage: String) -> Dictionary:
	var v: Dictionary = VEHICLES[kind]
	var door: Array = v["door"]
	var p: float = door[0]
	var db: float = door[1]
	match stage:
		"open":
			return { "length": 0.3, "level_db": -5.0 + db, "vary": 0.08, "layers": [
				# The handle's click, then the latch letting go: two dry clicks, a knock under the second.
				{ "type": "noise", "gain": 0.35, "decay": 0.003, "lp": 4500.0 * p, "hp": 1500.0, "attack": 0.0002 },
				{ "type": "noise", "gain": 0.4, "decay": 0.004, "lp": 1900.0 * p, "hp": 400.0, "delay": 0.035, "attack": 0.0003 },
				{ "type": "tone", "gain": 0.75, "freq": 140.0 * p, "freq_end": 80.0 * p, "sweep": 0.012, "decay": 0.03, "delay": 0.035 },
				{ "type": "modes", "gain": 0.3, "freqs": [190.0 * p, 255.0 * p], "amps": [1.0, 0.5], "decays": [0.03, 0.02],
					"delay": 0.035, "detune": 0.02 },
				# The door coming off its seal: a soft, low thump as it swings free.
				{ "type": "tone", "gain": 0.6, "freq": 100.0 * p, "freq_end": 58.0 * p, "sweep": 0.02, "decay": 0.05, "delay": 0.06 },
				{ "type": "noise", "gain": 0.25, "attack": 0.004, "decay": 0.03, "lp": 420.0 * p, "hp": 60.0, "delay": 0.06 },
			] }
		"close":
			return { "length": 0.42, "level_db": -1.0 + db, "vary": 0.06, "drive": 1.2, "layers": [
				# The door's weight thumping home and the body's low panels taking it.
				{ "type": "tone", "gain": 1.2, "freq": 125.0 * p, "freq_end": 48.0 * p, "sweep": 0.02, "decay": 0.09 },
				{ "type": "modes", "gain": 0.7, "freqs": [150.0 * p, 230.0 * p], "amps": [1.0, 0.55], "decays": [0.07, 0.045],
					"detune": 0.02 },
				{ "type": "noise", "gain": 0.9, "decay": 0.014, "lp": 1100.0 * p, "hp": 80.0, "attack": 0.0004 },
				# The latch clicking shut into the slam, and a dull knock of the trim after it.
				{ "type": "noise", "gain": 0.3, "decay": 0.003, "lp": 4000.0 * p, "hp": 1400.0, "delay": 0.012, "attack": 0.0002 },
				{ "type": "tone", "gain": 0.3, "freq": 180.0 * p, "freq_end": 120.0 * p, "sweep": 0.01, "decay": 0.02, "delay": 0.05 },
			] }
		"slide_open":
			var rattle := []
			for i in 11:
				rattle.append({ "type": "noise", "gain": 0.16 + 0.05 * (i % 3), "decay": 0.003, "lp": 2600.0, "hp": 500.0,
					"delay": 0.07 + 0.037 * i + 0.006 * (i % 2) })
			return { "length": 0.68, "level_db": -3.0 + db, "vary": 0.06, "layers": rattle + [
				{ "type": "noise", "gain": 0.5, "decay": 0.004, "lp": 6000.0, "hp": 1800.0, "attack": 0.0002 },
				{ "type": "tone", "gain": 0.4, "freq": 140.0, "freq_end": 85.0, "sweep": 0.015, "decay": 0.03, "delay": 0.02 },
				# The runners: a low rumble with a rattle in it, rolling for the length of the track.
				{ "type": "noise", "gain": 0.75, "attack": 0.12, "decay": 0.16, "lp": 650.0, "hp": 70.0, "delay": 0.04 },
				# Into the stop.
				{ "type": "tone", "gain": 0.7, "freq": 115.0, "freq_end": 60.0, "sweep": 0.015, "decay": 0.04, "delay": 0.5 },
				{ "type": "noise", "gain": 0.5, "decay": 0.01, "lp": 2600.0, "hp": 200.0, "delay": 0.5 },
			] }
		"slide_close":
			return { "length": 0.5, "level_db": 0.0 + db, "vary": 0.06, "drive": 1.3, "layers": [
				# The heavy door running into its frame, the body's low panels taking it, and the catch clicking home.
				{ "type": "tone", "gain": 1.3, "freq": 105.0, "freq_end": 42.0, "sweep": 0.022, "decay": 0.1 },
				{ "type": "modes", "gain": 0.7, "freqs": [130.0, 210.0], "amps": [1.0, 0.6], "decays": [0.08, 0.05], "detune": 0.02 },
				{ "type": "noise", "gain": 1.0, "decay": 0.016, "lp": 1000.0, "hp": 70.0, "attack": 0.0004 },
				{ "type": "noise", "gain": 0.35, "decay": 0.004, "lp": 4000.0, "hp": 1300.0, "delay": 0.02, "attack": 0.0002 },
			] }
	return {}


## Tyres sliding over the ground: a screech (the rubber's stick-slip ringing the carcass at a few close pitches that
## beat and swell) over a hiss. A seamless loop the service plays as loud as the slide.
static func _skid() -> Dictionary:
	return {
		"length": 1.0, "level_db": -3.0, "loop": true,
		"layers": [
			{ "type": "pulses", "rate": 0.0, "lp": 3500.0, "hp": 500.0, "noise": 0.05, "freqs": [990.0, 1380.0, 1985.0, 2710.0],
				"amps": [1.0, 0.55, 0.35, 0.18], "decays": [0.035, 0.03, 0.022, 0.015], "wobble": [3, 0.3] },
			{ "type": "pulses", "gain": 0.6, "rate": 0.0, "lp": 4000.0, "hp": 600.0, "freqs": [1060.0, 1490.0],
				"amps": [1.0, 0.5], "decays": [0.03, 0.025], "wobble": [5, 0.4] },
		],
	}


## A vehicle striking `material` (`flesh`: a character) in crash band `band_id`: the vehicle's mass thumping home (and a
## boom under a hard one), the sheet metal folding and its panels ringing, the struck thing's own crack and ring; a hard
## one throws glass and bits after it. A character struck is a dull, heavy thud on the bonnet instead.
static func _crash(material: String, band_id: String) -> Dictionary:
	var m: Dictionary = MATERIALS[material]
	var b: Dictionary = CRASH_BANDS[band_id]
	var body: float = b["body"]
	var crunch: float = b["crunch"]
	var layers := [
		{ "type": "tone", "gain": 1.3 * body, "freq": 95.0, "freq_end": 38.0, "sweep": 0.03, "decay": 0.07 + 0.03 * body },
	]
	if material == "flesh":
		layers.append({ "type": "tone", "gain": 1.0, "freq": 115.0, "freq_end": 55.0, "sweep": 0.02, "decay": 0.07 })
		layers.append({ "type": "noise", "gain": 0.7, "decay": 0.03, "lp": 900.0, "hp": 80.0, "attack": 0.001 })
		layers.append({ "type": "modes", "gain": 0.6, "freqs": [170.0, 380.0], "amps": [1.0, 0.6], "decays": [0.06, 0.04] })
		return { "length": float(b["length"]) * 0.7, "level_db": float(b["db"]) - 2.0, "vary": 0.1, "layers": layers }
	if body > 1.0:
		layers.append({ "type": "tone", "gain": 0.8 * (body - 0.5), "freq": 56.0, "freq_end": 30.0, "sweep": 0.05, "decay": 0.1 })
	layers.append({ "type": "noise", "gain": 1.6 * crunch, "decay": 0.03, "lp": 4500.0, "hp": 250.0, "attack": 0.0004 })
	layers.append({ "type": "noise", "gain": 1.0 * crunch, "attack": 0.01, "decay": 0.03 + 0.02 * crunch, "lp": 2500.0, "hp": 200.0, "delay": 0.02 })
	layers.append({ "type": "modes", "gain": 0.8, "freqs": [170.0, 380.0, 690.0], "amps": [1.0, 0.8, 0.55],
		"decays": [0.035 + 0.03 * body, 0.03 + 0.02 * body, 0.025], "detune": 0.03 })
	var freqs := []
	for f: float in m["modes"]:
		freqs.append(f * 0.85)
	if not freqs.is_empty():
		layers.append({ "type": "modes", "gain": 0.5 if m["hard"] else 0.25, "freqs": freqs, "amps": m["amps"], "decays": m["decays"].map(func(d): return minf(float(d), 0.05)), "detune": 0.03 })
	layers.append({ "type": "noise", "gain": 0.6, "decay": float(m["grit"]) * 2.0, "lp": float(m["lp"]), "hp": 150.0, "attack": 0.0005 })
	for i in roundi(2.0 * float(b["glass"])):
		layers.append({ "type": "modes", "gain": 0.12, "freqs": [3200.0, 4700.0, 6100.0], "amps": [1.0, 0.7, 0.5],
			"decays": [0.018, 0.013, 0.01], "delay": 0.05 + 0.07 * i, "detune": 0.08 })
	for i in roundi(3.0 * float(b["debris"])):
		layers.append({ "type": "noise", "gain": 0.15, "decay": 0.01, "lp": 3000.0, "hp": 600.0, "delay": 0.15 + 0.09 * i })
	return { "length": b["length"], "level_db": float(b["db"]) + float(m["db"]) * 0.5, "vary": 0.1, "drive": 1.5, "layers": layers }
