class_name FragGrenadeItem extends GrenadeItem

## Items domain: a frag grenade (blast and fragments): everything it does lives in `GrenadeItem`, tuned by
## the frag row of `GrenadeConfig`; this supplies its kind and size (its look is the row's).

## The grenade's footprint (px): width across, length from base to fuze.
const ART_SIZE := Vector2(8.0, 10.0)

## The kind's id and its `GrenadeConfig` row.
const KIND := &"frag"


func _init() -> void:
	kind = KIND
	display_name = str(stat("name", "Frag grenade"))
	reach = 28.0


## Its art's footprint (`GrenadeItem.art_size`).
func art_size() -> Vector2:
	return ART_SIZE
