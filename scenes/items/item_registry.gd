class_name ItemRegistry

## The catalogue of items, keyed by selection slot (the 1–9 number keys). The character
## asks for an inventory here and otherwise never hard-codes item ids. To add an item:
## write its Item subclass in this folder and add a case below. Magazines are not slot items: they
## are carried in the character's magazine store (`create_magazines`).

## Create the item for a slot id, or null if the slot is empty. A gun comes loaded with a
## `MagazineConfig.default_loaded` magazine holding `rounds` (negative = full).
static func create(id: int, rounds := -1) -> Item:
	match id:
		1: return UnarmedItem.new()
		2: return FistsItem.new()
		3:
			var pistol := PistolItem.new()
			pistol.magazine = Magazine.create(MagazineConfig.default_loaded, rounds)
			return pistol
		4: return KeyItem.new()
	return null


## A fresh inventory: slot id -> Item. Each character gets its own instances (items hold
## per-item state, e.g. the fists' alternating hand). `rounds` is what a gun starts loaded with
## (negative = full).
static func default_inventory(rounds := -1) -> Dictionary:
	var inv := {}
	for id in [1, 2, 3, 4]:
		inv[id] = create(id, rounds)
	return inv


## Full magazines for the given `MagazineConfig.types` ids (unknown ids are skipped).
static func create_magazines(type_ids: Array) -> Array:
	var mags := []
	for type_id in type_ids:
		if MagazineConfig.types.has(StringName(type_id)):
			mags.append(Magazine.create(StringName(type_id)))
	return mags
