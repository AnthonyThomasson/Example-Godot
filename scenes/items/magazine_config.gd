class_name MagazineConfig

## Tuning for magazines and reloading (Items domain). Static vars, like the other config holders, so a
## test or tool can change them (tests restore them with `set_static`).

## Every magazine type, by id: its display `name`, the `gun` it fits (`GunConfig.guns` id), how many rounds
## it holds (`capacity`) and, optionally, its own `reload_time` (s; absent = `reload_time` below). Add a row to
## add a type; a character's `spare_magazine_types` names rows from here, and a gun's `GunConfig` row names the
## type it is built loaded with.
static var types: Dictionary = {
	&"standard": { "name": "Standard magazine", "gun": &"pistol", "capacity": 12 },
	&"extended": { "name": "Extended magazine", "gun": &"pistol", "capacity": 20 },
	&"smg_standard": { "name": "SMG magazine", "gun": &"smg", "capacity": 32, "reload_time": 1.8 },
	&"smg_extended": { "name": "Extended SMG magazine", "gun": &"smg", "capacity": 50, "reload_time": 2.2 },
	&"rifle_standard": { "name": "Rifle magazine", "gun": &"rifle", "capacity": 24, "reload_time": 2.4 },
	&"rifle_extended": { "name": "Extended rifle magazine", "gun": &"rifle", "capacity": 40, "reload_time": 2.9 },
}
## How long a reload takes (s) for a magazine type with no `reload_time` of its own: the gun can't fire meanwhile.
static var reload_time: float = 1.5


## The capacity of magazine `type`, or 0 for an unknown type.
static func capacity_of(type: StringName) -> int:
	return int(types.get(type, {}).get("capacity", 0))


## The seconds a reload with magazine `type` takes: its own `reload_time`, else the shared one.
static func reload_time_of(type: StringName) -> float:
	return float(types.get(type, {}).get("reload_time", reload_time))
