class_name ItemRegistry

## The catalogue of items, keyed by selection slot (the 1–9 number keys). The character
## asks for an inventory here and otherwise never hard-codes item ids. To add an item:
## write its Item subclass in this folder and add a case below; to add a gun, also give it a row in
## `GunConfig` (its slot is that row's `slot`) and a case in `_new_gun`. Magazines are not slot items: they
## are carried in the character's magazine store (`create_magazines`).

## Slots of the plain items (guns take theirs from `GunConfig`).
const UNARMED_SLOT := 1
const FISTS_SLOT := 2
const KEY_SLOT := 4


## Create the item for a slot id, or null if the slot is empty. A gun comes loaded with the magazine its
## `GunConfig` row names (or `magazine`, a `MagazineConfig.types` id of that gun, when given), holding
## `rounds` (negative = full).
static func create(id: int, rounds := -1, magazine: StringName = &"") -> Item:
	match id:
		UNARMED_SLOT: return UnarmedItem.new()
		FISTS_SLOT: return FistsItem.new()
		KEY_SLOT: return KeyItem.new()
	var gun := GunConfig.gun_in_slot(id)
	if gun == &"":
		return null
	var item := _new_gun(gun)
	if item != null:
		var type := magazine if MagazineConfig.types.get(magazine, {}).get("gun", &"") == gun \
				else StringName(GunConfig.row(gun).get("magazine", &"standard"))
		item.magazine = Magazine.create(type, rounds)
	return item


## A fresh inventory: slot id -> Item, with everything the game has. Each character gets its own instances
## (items hold per-item state, e.g. the fists' alternating hand). `rounds` is what a gun starts loaded with
## (negative = full).
static func default_inventory(rounds := -1) -> Dictionary:
	return inventory_for([UNARMED_SLOT, FISTS_SLOT, KEY_SLOT] + gun_slots(), rounds)


## A fresh inventory of just the given slots (an empty slot id is skipped). A gun comes loaded with
## `magazine` when that type fits it.
static func inventory_for(slots: Array, rounds := -1, magazine: StringName = &"") -> Dictionary:
	var inv := {}
	for id in slots:
		var item := create(int(id), rounds, magazine)
		if item != null:
			inv[int(id)] = item
	return inv


## Every gun's inventory slot, lowest first.
static func gun_slots() -> Array:
	return GunConfig.slots()


## A random gun's slot, drawn from `rng` (-1 when there are no guns): a character spawning with a random weapon.
static func random_gun_slot(rng: RandomNumberGenerator) -> int:
	var slots := gun_slots()
	if slots.is_empty():
		return -1
	return slots[rng.randi() % slots.size()]


## The slots a character carrying only the gun in `gun_slot` has: bare hands, fists, the key and that gun.
static func loadout_for(gun_slot: int) -> Array:
	return [UNARMED_SLOT, FISTS_SLOT, KEY_SLOT, gun_slot]


## The spare magazines (`MagazineConfig.types` ids) a character carrying the gun in `gun_slot` also carries.
static func spares_for(gun_slot: int) -> Array:
	var row := GunConfig.row(GunConfig.gun_in_slot(gun_slot))
	var spares := []
	for i in int(row.get("spare_magazines", 0)):
		spares.append(StringName(row.get("magazine", &"standard")))
	return spares


## Full magazines for the given `MagazineConfig.types` ids (unknown ids are skipped).
static func create_magazines(type_ids: Array) -> Array:
	var mags := []
	for type_id in type_ids:
		if MagazineConfig.types.has(StringName(type_id)):
			mags.append(Magazine.create(StringName(type_id)))
	return mags


## A new gun of the given `GunConfig` id, or null for one with no class yet.
static func _new_gun(gun: StringName) -> GunItem:
	match gun:
		&"pistol": return PistolItem.new()
		&"smg": return SmgItem.new()
		&"rifle": return RifleItem.new()
	return null
