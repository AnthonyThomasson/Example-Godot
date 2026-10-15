class_name StunGrenadeItem extends GrenadeItem

## Items domain: a stun grenade (flash and bang): everything it does lives in `GrenadeItem`, tuned by the stun row of
## `GrenadeConfig`; this supplies its kind and size (its look is the row's).

## The grenade's footprint (px): width across, length from base to fuze cap.
const ART_SIZE := Vector2(6.0, 11.0)

## The kind's id and its `GrenadeConfig` row.
const KIND := &"stun"


func _init() -> void:
	kind = KIND
	display_name = str(stat("name", "Stun grenade"))
	reach = 28.0


## Its art's footprint (`GrenadeItem.art_size`).
func art_size() -> Vector2:
	return ART_SIZE
