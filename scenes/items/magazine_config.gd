class_name MagazineConfig

## Tuning for magazines and reloading (Items domain). Static vars, like the other config holders, so a
## test or tool can change them (tests restore them with `set_static`).

## Every magazine type, by id: its display `name`, the `gun` it fits and how many rounds it holds
## (`capacity`). Add a row to add a type; a character's `spare_magazine_types` names rows from here.
static var types: Dictionary = {
	&"standard": { "name": "Standard magazine", "gun": &"pistol", "capacity": 12 },
	&"extended": { "name": "Extended magazine", "gun": &"pistol", "capacity": 20 },
}
## The magazine type a freshly built gun starts loaded with.
static var default_loaded: StringName = &"standard"
## How long a reload takes (s): the gun can't fire meanwhile.
static var reload_time: float = 1.5


## The capacity of magazine `type`, or 0 for an unknown type.
static func capacity_of(type: StringName) -> int:
	return int(types.get(type, {}).get("capacity", 0))
