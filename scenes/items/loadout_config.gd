class_name LoadoutConfig

## Items domain: the weapon loadouts a match can hand a character — which gun it carries, which magazine
## the gun starts loaded with, how many spares it carries and how many stun and frag grenades. There is no table of
## its own: the choices are the guns in `GunConfig.guns` and their magazines in `MagazineConfig.types`, and the grenades
## in `GrenadeConfig.grenades`, so one added there is offered everywhere automatically; the outfit's choices are the garments
## and plates in `OutfitConfig`. The setup window never sees this class: Main passes it the plain `options()`,
## `grenade_options()` and `outfit_options()` lists and gets plain `{ weapon, magazine, spares, stuns, frags, outfit }` dicts back.

## The weapon id meaning "a gun drawn at random" (the default: how every character spawned before loadouts
## could be chosen). It has no magazine choices; it takes the drawn gun's own magazine and spares.
const RANDOM := &"random"

## Upper bound of the spare-magazine choice.
static var max_spares: int = 4
## Upper bound of each grenade count (stuns, frags).
static var max_grenades: int = 3
## The outfit a loadout without one wears, and what replaces a slot's unknown or misplaced id (plain clothes).
static var default_outfit: Dictionary = {
	"head": &"", "body": &"tshirt", "vest": &"", "pants": &"jeans", "feet": &"shoes", "front_plate": &"", "back_plate": &"",
}
## The setup window's label of each outfit slot.
const OUTFIT_LABELS := {
	"head": "Head", "body": "Body", "vest": "Vest", "pants": "Pants", "feet": "Feet",
	"front_plate": "Front plate", "back_plate": "Back plate",
}


## The choices for a UI: `[{ id, label, magazines: [{ id, label }] }]` — Random first, then every gun by
## slot. A gun's own magazine comes first in its list (the default); Random has none.
static func options() -> Array:
	var out: Array = [{ "id": RANDOM, "label": "Random", "magazines": [] }]
	var guns: Array = GunConfig.guns.keys()
	guns.sort_custom(func(a, b): return int(GunConfig.row(a).get("slot", 0)) < int(GunConfig.row(b).get("slot", 0)))
	for gun: StringName in guns:
		out.append({ "id": gun, "label": GunConfig.row(gun).get("name", str(gun)), "magazines": _magazines_of(gun) })
	return out


## The grenade rows for a UI: `[{ id, label, slot, max }]`, in slot order (the stun, then the frag). A loadout names
## a row's count under the key `<id>s` (`stuns`, `frags`).
static func grenade_options() -> Array:
	var out: Array = []
	for slot: int in GrenadeConfig.slots():
		var kind := GrenadeConfig.kind_in_slot(slot)
		out.append({ "id": kind, "label": str(GrenadeConfig.row(kind).get("name", kind)).trim_suffix(" grenade"),
			"slot": slot, "max": max_grenades })
	return out


## The outfit rows for a UI: `[{ slot, label, choices: [{ id, label }] }]`, one per outfit slot in `OutfitConfig.slots()`
## order, each offering that slot's garments (or plates), with a "None" choice (`id` `&""`) first where it may be left empty.
## A garment choice that holds plates (its `OutfitConfig` row's `plates`: the plate carrier) is marked `plates: true`, and a
## plate slot's row `plate: true`, so a UI can offer the plates only while the vest picked holds them (a plate is worn in
## nothing else).
static func outfit_options() -> Array:
	var out: Array = []
	for slot: String in OutfitConfig.slots():
		var choices: Array = []
		if OutfitConfig.may_be_empty(slot):
			choices.append({ "id": &"", "label": "None" })
		for id: StringName in OutfitConfig.choices(slot):
			var choice := { "id": id, "label": OutfitConfig.name_of(slot, id) }
			if slot in OutfitConfig.GARMENT_SLOTS and OutfitConfig.garment(id).get("plates", false):
				choice["plates"] = true
			choices.append(choice)
		var row := { "slot": slot, "label": OUTFIT_LABELS.get(slot, slot.capitalize()), "choices": choices }
		if slot in OutfitConfig.PLATE_SLOTS:
			row["plate"] = true
		out.append(row)
	return out


## `loadout` ({ weapon, magazine, spares, stuns, frags, outfit }, anything blank/unknown = the default) made valid: `random`
## or a known gun, one of that gun's magazine types (blank for random), spares within `0..max_spares` (-1 when
## unset: the gun's own spare count), each grenade count within `0..max_grenades` (0 when unset) and an `outfit` naming
## every slot (`outfit_of`).
static func normalize(loadout: Dictionary) -> Dictionary:
	var weapon := StringName(loadout.get("weapon", RANDOM))
	if weapon != RANDOM and GunConfig.row(weapon).is_empty():
		weapon = RANDOM
	var mags := _magazines_of(weapon) if weapon != RANDOM else []
	var magazine := &""
	if not mags.is_empty():
		magazine = mags[0]["id"]  # the gun's own magazine, listed first
		for m in mags:
			if m["id"] == StringName(loadout.get("magazine", &"")):
				magazine = m["id"]
	var spares := -1
	if loadout.has("spares") and weapon != RANDOM:
		spares = clampi(int(loadout["spares"]), 0, max_spares)
	var out := { "weapon": weapon, "magazine": magazine, "spares": spares }
	out.merge(grenade_counts(loadout))
	out["outfit"] = outfit_of(loadout)
	return out


## The outfit of `loadout` made valid: every slot of `OutfitConfig.slots()` with an id that fits it (StringNames; String ids, the
## setup window's, are read too). A slot missing, unknown or holding another slot's id takes `default_outfit`'s, so the body,
## pants and feet are always worn; no outfit at all is `default_outfit`. Both plates are `&""` unless the vest holds plates (the
## plate carrier), so neither a saved setup nor `random` carries a plate that does nothing.
static func outfit_of(loadout: Dictionary) -> Dictionary:
	var given: Dictionary = loadout.get("outfit", {}) if loadout.get("outfit") is Dictionary else {}
	var out := {}
	for slot: String in OutfitConfig.slots():
		var id := StringName(given.get(slot, default_outfit.get(slot, &"")))
		if not OutfitConfig.fits(slot, id):
			id = StringName(default_outfit.get(slot, &""))
		if not OutfitConfig.fits(slot, id):  # a default retuned to nothing fitting: the slot's first choice
			id = &"" if OutfitConfig.may_be_empty(slot) else OutfitConfig.choices(slot)[0]
		out[slot] = id
	if not OutfitConfig.garment(out.get("vest", &"")).get("plates", false):
		for slot: String in OutfitConfig.PLATE_SLOTS:
			out[slot] = &""
	return out


## The grenade counts of `loadout`, each within `0..max_grenades` (0 when unset): `{ stuns, frags }`.
static func grenade_counts(loadout: Dictionary) -> Dictionary:
	var out := {}
	for option: Dictionary in grenade_options():
		var key := "%ss" % option["id"]
		out[key] = clampi(int(loadout.get(key, 0)), 0, int(option["max"]))
	return out


## Arm `character` with the loadout (via `Character.set_loadout`): bare hands, fists, the key and one gun —
## the chosen one, or for `random` one drawn from `rng` — loaded with the chosen magazine and carrying the
## chosen number of spares of it, and the chosen number of stun and frag grenades (the gun stays what is held); and dress it
## in the loadout's whole outfit (via `Character.set_outfit`), replacing whatever it wore. `style` is how it is all drawn (looks
## only): `look` (the character's style, with its `seed` and a police unit's `rank`, via `Character.set_style`; absent = the
## character's style is left as it is) and `weapon` (the weapon style every item it carries is drawn in, `Item.style`; absent =
## `police`). Returns the gun id it was armed with.
static func apply(character: Node, loadout: Dictionary, rng: RandomNumberGenerator, style := {}) -> StringName:
	var l := normalize(loadout)
	character.set_outfit(l["outfit"])
	if style.has("look"):
		character.set_style(StringName(style["look"]), int(style.get("seed", 0)), int(style.get("rank", 0)))
	var gun: StringName = l["weapon"]
	if gun == RANDOM:
		var random_slot := ItemRegistry.random_gun_slot(rng)
		if random_slot < 0:
			return &""
		gun = GunConfig.gun_in_slot(random_slot)
	var slot := int(GunConfig.row(gun)["slot"])
	var magazine: StringName = l["magazine"]
	var spare_types: Array
	if magazine == &"":
		spare_types = ItemRegistry.spares_for(slot)
	else:
		spare_types = []
		spare_types.resize(l["spares"] if l["spares"] >= 0 else int(GunConfig.row(gun).get("spare_magazines", 0)))
		spare_types.fill(magazine)
	var counts := {}  # Slot -> how many.
	for option: Dictionary in grenade_options():
		counts[int(option["slot"])] = l["%ss" % option["id"]]
	var slots := ItemRegistry.loadout_for(slot, counts.get(ItemRegistry.STUN_SLOT, 0), counts.get(ItemRegistry.FRAG_SLOT, 0))
	character.set_loadout(slots, slot, spare_types, magazine, counts, StringName(style.get("weapon", &"police")))
	return gun


## A random valid loadout drawn from `rng`: any gun, any of its magazines, `0..max_spares` spares, and any outfit
## (`random_outfit`).
static func random(rng: RandomNumberGenerator) -> Dictionary:
	var guns := options().filter(func(o): return o["id"] != RANDOM)
	if guns.is_empty():
		return normalize({ "outfit": random_outfit(rng) })
	var pick: Dictionary = guns[rng.randi() % guns.size()]
	var mags: Array = pick["magazines"]
	var loadout := {
		"weapon": pick["id"],
		"magazine": mags[rng.randi() % mags.size()]["id"] if not mags.is_empty() else &"",
		"spares": rng.randi_range(0, max_spares),
	}
	loadout["outfit"] = random_outfit(rng)  # drawn after the gun, so the outfit never shifts a seed's gun
	return normalize(loadout)


## A random valid outfit drawn from `rng`: each slot one of its `outfit_options()` choices (nothing included where it may be empty),
## the plates drawn too and then cleared unless the vest drawn holds them (`outfit_of`), so every outfit takes the same number of draws.
static func random_outfit(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for row: Dictionary in outfit_options():
		var choices: Array = row["choices"]
		out[row["slot"]] = choices[rng.randi() % choices.size()]["id"]
	return outfit_of({ "outfit": out })


## Gun `gun`'s magazine types as `[{ id, label }]`, its own (`GunConfig` `magazine`) first.
static func _magazines_of(gun: StringName) -> Array:
	var own := StringName(GunConfig.row(gun).get("magazine", &""))
	var out: Array = []
	for type: StringName in MagazineConfig.types:
		if MagazineConfig.types[type].get("gun", &"") == gun:
			var entry := { "id": type, "label": MagazineConfig.types[type].get("name", str(type)) }
			if type == own:
				out.push_front(entry)
			else:
				out.append(entry)
	return out
