class_name Outfit extends RefCounted

## What one character wears (Items domain; `docs/outfits.md`): a garment or nothing in each slot of `OutfitConfig`, the plate
## carrier's two plates and their condition. The Character owns one (`Character.set_outfit`) and asks it what stands between a
## round and the body (`layer`), wears its plates by the hits they take (`wear`) and weighs it (`weight`); the art reads
## `look()` and the UI `view()`. A new Outfit wears nothing: no protection, no weight, the character's own look.

## Slot (String) -> the id worn there (StringName, `&""` = nothing), every slot of `OutfitConfig.slots()`.
var _worn := {}
## Plate slot -> its condition, 1 new .. 0 spent (only the plates worn).
var _condition := {}
## Counts every change to what is worn or a plate's condition (`set_ids`, `wear`), so a reader that draws the outfit (the
## Character's art) checks one int each frame and re-reads `look()` only when it moved.
var revision := 0


func _init(worn_ids := {}) -> void:
	set_ids(worn_ids)


## Wear `worn_ids` (`{ head, body, vest, pants, feet, front_plate, back_plate }`, String keys; a missing, empty or unfitting id = nothing
## there), replacing everything worn before. A plate is worn only in a garment that holds plates (the plate carrier); one left in
## its slot keeps its condition, a new one starts at 1.
func set_ids(worn_ids: Dictionary) -> void:
	revision += 1
	var was := _worn
	_worn = {}
	for slot: String in OutfitConfig.slots():
		var id := StringName(worn_ids.get(slot, &""))
		_worn[slot] = id if id in OutfitConfig.choices(slot) else &""
	var keep := _condition
	_condition = {}
	for slot: String in OutfitConfig.PLATE_SLOTS:
		if not holds_plates():
			_worn[slot] = &""
		if _worn[slot] != &"":
			_condition[slot] = keep[slot] if keep.has(slot) and was.get(slot, &"") == _worn[slot] else 1.0


## The ids worn, by slot (a copy; the shape `set_ids` takes).
func ids() -> Dictionary:
	return _worn.duplicate()


## The id worn in `slot` (`&""` for nothing).
func worn(slot: String) -> StringName:
	return _worn.get(slot, &"")


## Whether the vest worn holds plates.
func holds_plates() -> bool:
	return bool(OutfitConfig.garment(worn("vest")).get("plates", false))


## The condition of the plate in `slot` (1 new .. 0 spent; 0 when none is worn there).
func condition(slot: String) -> float:
	return float(_condition.get(slot, 0.0))


## The armour a round meets striking hit zone `zone` (`feet legs torso head`) from side `side` (`front flank back`): `{}` when
## nothing protects it there, else `{ stop_power, penetration, material, color, blunt, reduction, blast, plate }` (`plate` = the
## plate slot it is, "" for a garment). A plate on that side lies over the garment's soft panel: its numbers, with its stop power
## falling toward the panel's as it wears, never below it.
func layer(zone: StringName, side: StringName) -> Dictionary:
	var base := {}
	for slot: String in OutfitConfig.GARMENT_SLOTS:
		var armour: Dictionary = OutfitConfig.garment(worn(slot)).get("armour", {})
		if armour.is_empty() or not zone in armour.get("zones", []):
			continue
		if armour.has("sides") and not side in armour["sides"]:
			continue
		if base.is_empty() or float(armour["stop_power"]) > float(base["stop_power"]):
			base = armour
	if base.is_empty():
		return {}
	var out := _numbers(base)
	var plate_slot := _plate_slot(zone, side)
	if plate_slot == "":
		return out
	var plate := OutfitConfig.plate(worn(plate_slot))
	var soft := float(base["stop_power"])
	var hard := maxf(float(plate["stop_power"]), soft)
	out = _numbers(plate)
	out["stop_power"] = lerpf(soft, hard, condition(plate_slot))
	out["reduction"] = maxf(float(plate["reduction"]), float(base["reduction"]))
	out["blast"] = maxf(float(plate["blast"]), float(base["blast"]))
	out["plate"] = plate_slot
	return out


## Wear the plate that covers `zone` from `side` by a hit of `damage` (its condition falls by damage / durability). Nothing
## else wears.
func wear(zone: StringName, side: StringName, damage: float) -> void:
	var slot := _plate_slot(zone, side)
	if slot == "":
		return
	var durability := float(OutfitConfig.plate(worn(slot)).get("durability", 0.0))
	if durability > 0.0 and damage > 0.0 and condition(slot) > 0.0:
		_condition[slot] = maxf(condition(slot) - damage / durability, 0.0)
		revision += 1


## Total weight worn (kg).
func weight() -> float:
	var total := 0.0
	for slot: String in OutfitConfig.GARMENT_SLOTS:
		total += float(OutfitConfig.garment(worn(slot)).get("weight", 0.0))
	for slot: String in OutfitConfig.PLATE_SLOTS:
		total += float(OutfitConfig.plate(worn(slot)).get("weight", 0.0))
	return total


## What the art draws: each garment slot worn -> `{ id, kind, color? }` (no `color` = the side's team colour), and each plate
## worn -> `{ id, condition, color }` (the plate's own colour, which shows where its wear tears the carrier). Nothing worn in a
## slot leaves it out (the character's own look there).
func look() -> Dictionary:
	var out := {}
	for slot: String in OutfitConfig.GARMENT_SLOTS:
		if worn(slot) == &"":
			continue
		var entry: Dictionary = (OutfitConfig.garment(worn(slot)).get("look", {}) as Dictionary).duplicate()
		entry["id"] = worn(slot)
		out[slot] = entry
	for slot: String in OutfitConfig.PLATE_SLOTS:
		if worn(slot) != &"":
			out[slot] = { "id": worn(slot), "condition": condition(slot), "color": OutfitConfig.plate(worn(slot)).get("color", Color.GRAY) }
	return out


## For the UI: each garment slot -> the garment's display name ("" for nothing), each plate slot -> `{ type, name, condition }`
## (`type` the plate id, `&""` for none; `name` its display name, "" for none).
func view() -> Dictionary:
	var out := {}
	for slot: String in OutfitConfig.GARMENT_SLOTS:
		out[slot] = OutfitConfig.name_of(slot, worn(slot))
	for slot: String in OutfitConfig.PLATE_SLOTS:
		out[slot] = { "type": worn(slot), "name": OutfitConfig.name_of(slot, worn(slot)), "condition": condition(slot) }
	return out


## The plate slot worn over `zone` on `side` ("" when none): the torso's front and back, in a garment that holds plates.
func _plate_slot(zone: StringName, side: StringName) -> String:
	if zone != &"torso":
		return ""
	for slot: String in OutfitConfig.PLATE_SLOTS:
		if OutfitConfig.PLATE_SIDE[slot] == side and worn(slot) != &"":
			return slot
	return ""


## The protection numbers of an armour or plate row.
static func _numbers(row: Dictionary) -> Dictionary:
	return {
		"stop_power": float(row["stop_power"]), "penetration": float(row["penetration"]), "material": str(row["material"]),
		"color": row.get("color", Color.GRAY), "blunt": float(row["blunt"]), "reduction": float(row["reduction"]),
		"blast": float(row.get("blast", 0.0)), "plate": "",
	}
