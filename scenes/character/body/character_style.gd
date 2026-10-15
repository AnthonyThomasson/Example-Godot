extends RefCounted

## Character body: how a character looks in its style (`Character.style`, `look_seed`, `rank`; `docs/outfits.md`, styles).
## `resolve` turns the style's row (`CharacterConfig.styles`) and what the character wears in that style (`Outfit.look(style)`)
## into the one look every body painter draws from (`style_art.gd` registers it, the painters get its handle):
## - the character's own variety, drawn from its look seed in a fixed order (`_variety`): skin, hair and hair style, gloves,
##   a pack, its optics and face, the colours of its eyes and ink, the implants (tattoos, inlays, a headset, a spine rig, cables, a
##   patched sleeve), chrome arms and a chrome shin, and the sides a face plate and a patch sit on;
## - each garment worn, its `kind` and its colour: the garment look's own (a police livery's) or one drawn from the style's
##   palette it names, by the look seed and the palette (so a character keeps a colour as it changes clothes);
## - where nothing is worn on the body, the legs or the feet, the style's `bare` palettes;
## - the sleeves per side (a colour, or null: bare to the shoulder or chrome) and a carrier's front and back panels.
## Nothing here changes what the body does.

## The look keys a garment slot's `kind` is stored under, and the key of its resolved colour.
const _COLOURS := { "head": "helm", "body": "shirt", "vest": "vest_col", "pants": "pants_col", "feet": "feet_col" }


## The look of a character in `style` (unknown = `CharacterConfig.default_style`) with variety seed `seed_value` and police
## `rank`, wearing `worn` (`Outfit.look(style)`).
static func resolve(style: StringName, seed_value: int, rank: int, worn: Dictionary) -> Dictionary:
	if not CharacterConfig.styles.has(style):
		style = CharacterConfig.default_style
	var row: Dictionary = CharacterConfig.styles[style]
	var look := _variety(row, style, seed_value)
	look["style"] = String(style)
	look["police"] = bool(row.get("police", false))
	look["rank"] = rank if look["police"] else 0
	for key in ["trim", "edge", "visor", "led", "pad", "chrome", "pack_kind"]:
		look[key] = row.get(key)
	look["pack_col"] = _palette(row, style, seed_value, "pack", Color(0.2, 0.2, 0.2))
	look["patch"] = _palette(row, style, seed_value, "patch", Color(0.3, 0.3, 0.3))
	var bare: Dictionary = row.get("bare", {})
	for slot: String in _COLOURS:
		var entry: Dictionary = worn.get(slot, {})
		look[slot] = String(entry.get("kind", ""))
		var colour: Variant = entry.get("color")
		if colour == null:
			var palette := String(entry.get("palette", bare.get(slot, "")))
			colour = _palette(row, style, seed_value, palette, Color(0.3, 0.3, 0.3)) if palette != "" else null
		look[_COLOURS[slot]] = colour
	for face in ["front", "back"]:
		var cover: String = face + "_cover"
		look[cover] = look["vest_col"] if look["police"] or look["vest"] != "carrier" \
			else _palette(row, style, seed_value, "cover_" + face, look["vest_col"])
	look["sleeves"] = _sleeves(look)
	return look


## Side `side`'s sleeve in `look`: its colour, or null where the arm is bare to the shoulder (a borg's torn or missing sleeve,
## a tank top) or chrome; a merc's long sleeve on its patch side is patched.
static func _sleeves(look: Dictionary) -> Array:
	var shirt: Variant = look["shirt"]
	var long: bool = look["body"] == "long_sleeves"
	var out: Array = [shirt, shirt]
	match String(look["style"]):
		"merc":
			if long and look["patchwork"]:
				out[look["patch_side"]] = look["patch"]
		"borg":
			out = [null, null]
			if long:  # One sleeve torn off: the chrome side bare, or the patch side when neither or both are chrome.
				var arms: Array = look["chrome_arm"]
				var torn: int = 0 if arms[0] and not arms[1] else 1 if arms[1] and not arms[0] else look["patch_side"]
				out[1 - torn] = shirt
	for side in 2:
		if look["chrome_arm"][side]:
			out[side] = null
	return out


## The character's own variety within its style, drawn from `seed_value` in a fixed order (so a draw added at the end never shifts
## the ones before it).
static func _variety(row: Dictionary, style: StringName, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(style), seed_value])
	var look := {}
	look["skin"] = _from(rng, row.get("skin", [Color(0.8, 0.62, 0.48)]))
	look["hair"] = _from(rng, row.get("hair", [Color.BLACK]))
	look["hair_style"] = _weighted(rng, row.get("hair_styles", { "short": 1 }))
	look["glove"] = row.get("glove", look["skin"]) if rng.randf() < float(row.get("gloves", 0.0)) else look["skin"]
	look["pack"] = rng.randf() < float(row.get("pack", 0.0))
	var optics: Array = _weighted_entry(rng, row.get("optics", [[1, "", ""]]))
	look["eyes"] = optics[1]
	look["face"] = optics[2]
	look["glow"] = _from(rng, row.get("glows", [Color.RED]))
	look["ink"] = _from(rng, row.get("inks", [Color.BLACK]))
	for implant in ["tattoo", "inlays", "headset", "spine", "cables", "patchwork"]:
		look[implant] = rng.randf() < float(row.get(implant, 0.0))
	var arms: Array = row.get("chrome_arms", [0.0, 0.0])
	var roll := rng.randf()
	var side := rng.randi() % 2
	look["chrome_arm"] = [true, true] if roll < float(arms[1]) else \
		([side == 0, side == 1] if roll < float(arms[0]) + float(arms[1]) else [false, false])
	var legged := rng.randf() < float(row.get("chrome_leg", 0.0))
	side = rng.randi() % 2
	look["chrome_leg"] = [legged and side == 0, legged and side == 1]
	look["patch_side"] = rng.randi() % 2
	look["plate_side"] = rng.randi() % 2
	return look


## A colour from the style's palette `name` for this character: drawn by its seed and the palette's name, so it does not depend
## on what else it wears. `fallback` when the style has no such palette.
static func _palette(row: Dictionary, style: StringName, seed_value: int, name: String, fallback: Variant) -> Variant:
	var list: Array = (row.get("palettes", {}) as Dictionary).get(name, [])
	if list.is_empty():
		return fallback
	return list[absi(hash([seed_value, name, String(style)])) % list.size()]


## An entry of `list`, drawn by `rng`.
static func _from(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi() % list.size()]


## A key of `weights` (key -> weight), drawn by weight.
static func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll < 0.0:
			return String(k)
	return String(weights.keys()[0])


## One of `entries` (each `[weight, ...]`), drawn by weight.
static func _weighted_entry(rng: RandomNumberGenerator, entries: Array) -> Array:
	var total := 0.0
	for e: Array in entries:
		total += float(e[0])
	var roll := rng.randf() * total
	for e: Array in entries:
		roll -= float(e[0])
		if roll < 0.0:
			return e
	return entries[0]
