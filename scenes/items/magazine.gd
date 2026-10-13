class_name Magazine extends Item

## A magazine of rounds for a gun. It is carried, never held: it lives in the character's magazine
## store, not in an inventory slot, so no number key selects it and several can be carried at once.
## Different types hold different amounts (`MagazineConfig.types`). A gun is loaded with one, shooting
## spends its rounds, and a reload swaps it for another carried one.

## Which row of `MagazineConfig.types` this is.
var type: StringName = &"standard"
## The kind of gun it fits (a `GunConfig` id, e.g. `PistolItem.GUN`).
var gun: StringName = &"pistol"
## Rounds it holds when full.
var capacity := 0
## Rounds left in it.
var rounds := 0


## A magazine of `type` holding `loaded` rounds (negative = full, and never more than it can hold).
static func create(type_id: StringName, loaded := -1) -> Magazine:
	var mag := Magazine.new()
	var row: Dictionary = MagazineConfig.types.get(type_id, {})
	mag.type = type_id
	mag.display_name = row.get("name", "Magazine")
	mag.gun = row.get("gun", &"pistol")
	mag.capacity = MagazineConfig.capacity_of(type_id)
	mag.rounds = mag.capacity if loaded < 0 else mini(loaded, mag.capacity)
	return mag
