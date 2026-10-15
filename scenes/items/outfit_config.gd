class_name OutfitConfig

## Tuning for what a character wears (Items domain). Static vars, like the other config holders, so a test or tool can
## change them (tests restore them with `set_static`). The spec behind every number is `docs/outfits.md` (O1 to O14). An
## `Outfit` (outfit.gd) is one character's worn set; the Character reads its armour through `Outfit.layer`.
##
## The outfit's slots are Strings (like a loadout's own keys): the five garment slots in `GARMENT_SLOTS`, then the carrier's
## two plate slots in `PLATE_SLOTS`. Garment and plate ids are StringNames, `&""` = nothing worn there.
##
## Garment row keys:
##   name        display name (the setup window, the debug panel, the inspector).
##   slot        the outfit slot it is worn in.
##   weight      kg; the outfit's total slows the walk and tires the run (`CharacterConfig.outfit_*`).
##   plates      true = it holds a front and a back plate (the plate carrier); a plate is worn only in such a garment.
##   look        what the art draws: `kind` (the painter's style name) and `color` (absent = the side's team colour).
##   armour      absent = no protection (looks and weight only). Else the zones it covers (`zones`, of `ZONES`), the sides
##               (`sides`, of `SIDES`; absent = all round) and the protection numbers below.
## Protection numbers (an armour row, a plate row):
##   stop_power  a round whose power x speed factor is below it is stopped (round power: `GunConfig` `penetration`, pistol
##               1.0, SMG 0.8, rifle 2.2; a frag's fragment 0.4).
##   penetration the surface's P (0..100) a round that gets through loses speed against; P >= the bounce minimum
##               (`BallisticsConfig.penetration_bounce_min`) ricochets a glancing round.
##   material    what a stopped round strikes (debris, the hit event, the impact sound); `color` its debris colour.
##   blunt       share of a stopped round's damage still dealt.
##   reduction   share cut from a round that gets through.
##   blast       share cut from a frag's blast (torso armour only).
## Plate row keys add `durability`: a hit wears the plate's condition (1 new .. 0 spent) by its damage / durability, and its
## stop power falls toward the soft panel's under it as it wears.

const GARMENT_SLOTS: Array[String] = ["head", "body", "vest", "pants", "feet"]
const PLATE_SLOTS: Array[String] = ["front_plate", "back_plate"]
## The side of the torso each plate slot covers.
const PLATE_SIDE := { "front_plate": &"front", "back_plate": &"back" }
## Hit zones, feet up, and the sides a round strikes from (Character: zone by bullet height, side by the shot's direction).
const ZONES: Array[StringName] = [&"feet", &"legs", &"torso", &"head"]
const SIDES: Array[StringName] = [&"front", &"flank", &"back"]

## The garment slots that may be left empty (the rest are always worn once an outfit is chosen); the plate slots may always be.
static var optional_slots: Array[String] = ["head", "vest"]

## The garments by id, one row each (the row keys above).
static var garments: Dictionary = {
	&"hat": { "name": "Cap", "slot": "head", "weight": 0.1,
		"look": { "kind": &"cap", "color": Color(0.18, 0.22, 0.36) } },
	&"helmet": { "name": "Helmet", "slot": "head", "weight": 1.5,
		"look": { "kind": &"helmet", "color": Color(0.30, 0.33, 0.24) },
		"armour": { "zones": [&"head"], "stop_power": 1.2, "penetration": 60.0, "material": "composite",
			"color": Color(0.30, 0.33, 0.24), "blunt": 0.2, "reduction": 0.2, "blast": 0.0 } },
	&"tshirt": { "name": "T-shirt", "slot": "body", "weight": 0.2, "look": { "kind": &"short_sleeves" } },
	&"shirt": { "name": "Shirt", "slot": "body", "weight": 0.4, "look": { "kind": &"long_sleeves" } },
	&"tactical_vest": { "name": "Tactical vest", "slot": "vest", "weight": 2.0,
		"look": { "kind": &"vest", "color": Color(0.24, 0.27, 0.22) },
		"armour": { "zones": [&"torso"], "stop_power": 1.2, "penetration": 30.0, "material": "fabric",
			"color": Color(0.24, 0.27, 0.22), "blunt": 0.2, "reduction": 0.25, "blast": 0.35 } },
	&"plate_carrier": { "name": "Plate carrier", "slot": "vest", "weight": 2.5, "plates": true,
		"look": { "kind": &"carrier", "color": Color(0.36, 0.33, 0.24) },
		"armour": { "zones": [&"torso"], "stop_power": 1.2, "penetration": 30.0, "material": "fabric",
			"color": Color(0.36, 0.33, 0.24), "blunt": 0.2, "reduction": 0.25, "blast": 0.35 } },
	&"jeans": { "name": "Jeans", "slot": "pants", "weight": 0.7, "look": { "kind": &"jeans", "color": Color(0.20, 0.27, 0.42) } },
	&"tactical_pants": { "name": "Tactical pants", "slot": "pants", "weight": 0.8,
		"look": { "kind": &"tactical", "color": Color(0.30, 0.31, 0.25) } },
	&"shoes": { "name": "Shoes", "slot": "feet", "weight": 0.8, "look": { "kind": &"shoes", "color": Color(0.32, 0.22, 0.15) } },
	&"boots": { "name": "Boots", "slot": "feet", "weight": 1.6, "look": { "kind": &"boots", "color": Color(0.16, 0.14, 0.12) } },
}

## The plates by id, one row each (the protection numbers above, plus `durability`).
static var plates: Dictionary = {
	&"soft_iiia": { "name": "Soft IIIA insert", "weight": 0.5, "durability": 400.0, "stop_power": 1.2, "penetration": 30.0,
		"material": "fabric", "color": Color(0.24, 0.24, 0.22), "blunt": 0.2, "reduction": 0.25, "blast": 0.35 },
	&"steel_iii": { "name": "Steel III plate", "weight": 3.6, "durability": 2000.0, "stop_power": 2.6, "penetration": 95.0,
		"material": "metal", "color": Color(0.55, 0.56, 0.58), "blunt": 0.12, "reduction": 0.35, "blast": 0.5 },
	&"ceramic_iv": { "name": "Ceramic IV plate", "weight": 2.6, "durability": 100.0, "stop_power": 3.0, "penetration": 70.0,
		"material": "ceramic", "color": Color(0.86, 0.84, 0.78), "blunt": 0.1, "reduction": 0.4, "blast": 0.5 },
}


## The garment row for `id` (empty for an unknown id or `&""`).
static func garment(id: StringName) -> Dictionary:
	return garments.get(id, {})


## The plate row for `id` (empty for an unknown id or `&""`).
static func plate(id: StringName) -> Dictionary:
	return plates.get(id, {})


## Every outfit slot, garments then plates (the setup window's order).
static func slots() -> Array[String]:
	var out: Array[String] = GARMENT_SLOTS.duplicate()
	out.append_array(PLATE_SLOTS)
	return out


## Whether `slot` may be left empty.
static func may_be_empty(slot: String) -> bool:
	return slot in optional_slots or slot in PLATE_SLOTS


## The ids `slot` may hold, in table order (no `&""`).
static func choices(slot: String) -> Array[StringName]:
	var out: Array[StringName] = []
	if slot in PLATE_SLOTS:
		out.assign(plates.keys())
		return out
	for id: StringName in garments:
		if str(garments[id].get("slot", "")) == slot:
			out.append(id)
	return out


## Whether `id` may be worn in `slot` (`&""` where the slot may be empty).
static func fits(slot: String, id: StringName) -> bool:
	if id == &"":
		return may_be_empty(slot)
	return id in choices(slot)


## The display name of `id` in `slot` ("" for nothing).
static func name_of(slot: String, id: StringName) -> String:
	var row := plate(id) if slot in PLATE_SLOTS else garment(id)
	return str(row.get("name", ""))
