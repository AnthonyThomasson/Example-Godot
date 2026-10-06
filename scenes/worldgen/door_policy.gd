class_name DoorPolicy

## World-Gen config: which doorways get a physical door. Authored as data so the rule lives in one
## place and is easy to retune — not branched into the placement code. Exterior (front) doorways
## always get a door; an interior doorway gets one only when it borders a "private" room.

## Room types that warrant a door for privacy. An interior doorway gets a door when EITHER room it
## connects is one of these; public connections (living_room, kitchen, kitchen_living, dining_room,
## entry_hall, garage) stay open archways.
const PRIVATE_ROOM_TYPES := {
	"bedroom": true,
	"bathroom": true,
	"kids_room": true,
	"home_office": true,
	"laundry_room": true,
	"studio": true,
}


## Should the doorway bordering rooms of `types` get a door? `is_front` (the exterior entrance)
## always does; an interior door does when any bordering room type is private.
static func wants_door(types: Array, is_front: bool) -> bool:
	if is_front:
		return true
	for t in types:
		if PRIVATE_ROOM_TYPES.has(t):
			return true
	return false
