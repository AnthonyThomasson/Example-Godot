class_name LoadoutConfig

## Items domain: the weapon loadouts a match can hand a character — which gun it carries, which magazine
## the gun starts loaded with, how many spares it carries and how many stun and frag grenades. There is no table of
## its own: the choices are the guns in `GunConfig.guns` and their magazines in `MagazineConfig.types`, and the grenades
## in `GrenadeConfig.grenades`, so one added there is offered everywhere automatically. The setup window never sees this
## class: Main passes it the plain `options()` and `grenade_options()` lists and gets plain
## `{ weapon, magazine, spares, stuns, frags }` dicts back.

## The weapon id meaning "a gun drawn at random" (the default: how every character spawned before loadouts
## could be chosen). It has no magazine choices; it takes the drawn gun's own magazine and spares.
const RANDOM := &"random"

## Upper bound of the spare-magazine choice.
static var max_spares: int = 4
## Upper bound of each grenade count (stuns, frags).
static var max_grenades: int = 3


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


## `loadout` ({ weapon, magazine, spares, stuns, frags }, anything blank/unknown = the default) made valid: `random`
## or a known gun, one of that gun's magazine types (blank for random), spares within `0..max_spares` (-1 when
## unset: the gun's own spare count) and each grenade count within `0..max_grenades` (0 when unset).
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
## chosen number of spares of it, and the chosen number of stun and frag grenades (the gun stays what is held).
## Returns the gun id it was armed with.
static func apply(character: Node, loadout: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var l := normalize(loadout)
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
	character.set_loadout(slots, slot, spare_types, magazine, counts)
	return gun


## A random valid loadout drawn from `rng`: any gun, any of its magazines, `0..max_spares` spares.
static func random(rng: RandomNumberGenerator) -> Dictionary:
	var guns := options().filter(func(o): return o["id"] != RANDOM)
	if guns.is_empty():
		return normalize({})
	var pick: Dictionary = guns[rng.randi() % guns.size()]
	var mags: Array = pick["magazines"]
	return normalize({
		"weapon": pick["id"],
		"magazine": mags[rng.randi() % mags.size()]["id"] if not mags.is_empty() else &"",
		"spares": rng.randi_range(0, max_spares),
	})


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
