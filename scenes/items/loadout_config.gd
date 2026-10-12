class_name LoadoutConfig

## Items domain: the weapon loadouts a match can hand a character — which gun it carries, which magazine
## the gun starts loaded with and how many spares it carries. There is no table of its own: the choices are
## the guns in `GunConfig.guns` and their magazines in `MagazineConfig.types`, so a gun added there is
## offered everywhere automatically. The setup window never sees this class: Main passes it the plain
## `options()` list and gets plain `{ weapon, magazine, spares }` dicts back.

## The weapon id meaning "a gun drawn at random" (the default: how every character spawned before loadouts
## could be chosen). It has no magazine choices; it takes the drawn gun's own magazine and spares.
const RANDOM := &"random"

## Upper bound of the spare-magazine choice.
static var max_spares: int = 4


## The choices for a UI: `[{ id, label, magazines: [{ id, label }] }]` — Random first, then every gun by
## slot. A gun's own magazine comes first in its list (the default); Random has none.
static func options() -> Array:
	var out: Array = [{ "id": RANDOM, "label": "Random", "magazines": [] }]
	var guns: Array = GunConfig.guns.keys()
	guns.sort_custom(func(a, b): return int(GunConfig.row(a).get("slot", 0)) < int(GunConfig.row(b).get("slot", 0)))
	for gun: StringName in guns:
		out.append({ "id": gun, "label": GunConfig.row(gun).get("name", str(gun)), "magazines": _magazines_of(gun) })
	return out


## `loadout` ({ weapon, magazine, spares }, anything blank/unknown = the default) made valid: `random` or a
## known gun, one of that gun's magazine types (blank for random), spares within `0..max_spares` (-1 when
## unset: the gun's own spare count).
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
	return { "weapon": weapon, "magazine": magazine, "spares": spares }


## Arm `character` with the loadout (via `Character.set_loadout`): bare hands, fists, the key and one gun —
## the chosen one, or for `random` one drawn from `rng` — loaded with the chosen magazine and carrying the
## chosen number of spares of it. Returns the gun id it was armed with.
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
	character.set_loadout(ItemRegistry.loadout_for(slot), slot, spare_types, magazine)
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
