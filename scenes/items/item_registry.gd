class_name ItemRegistry

## The catalogue of items, keyed by selection slot (the 1–9 number keys). The character
## asks for an inventory here and otherwise never hard-codes item ids. To add an item:
## write its Item subclass in this folder and add a case below.

## Create the item for a slot id, or null if the slot is empty.
static func create(id: int) -> Item:
	match id:
		1: return UnarmedItem.new()
		2: return FistsItem.new()
		3: return PistolItem.new()
	return null


## A fresh inventory: slot id -> Item. Each character gets its own instances (items hold
## per-item state, e.g. the fists' alternating hand).
static func default_inventory() -> Dictionary:
	var inv := {}
	for id in [1, 2, 3]:
		inv[id] = create(id)
	return inv
