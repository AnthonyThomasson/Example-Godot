class_name SmgItem extends GunItem

## Items domain: a submachine gun: a compact automatic held in both hands with its butt on the right shoulder,
## a longer reach than a pistol but nowhere near a rifle. Everything a gun does lives in `GunItem`, tuned by
## the SMG's `GunConfig` row (fast, light rounds, a wide spread; its look too); this supplies its sizes and its hold. Its
## barrel is too long for a wall: touching one, it points up and cannot fire.

## The SMG's footprint lying flat on its side (px): its profile across, its length along.
const FLAT_SIZE := Vector2(11.0, 22.0)
## SMG sprite footprint (px): width across, length from butt to muzzle.
const ART_SIZE := Vector2(6.0, 28.0)
## How far the butt end sits behind the hand's center (px): the hand grips the pistol grip, the butt is on the
## right shoulder.
const GRIP_BACK := 10.0

## The kind of magazine it takes (`Magazine.gun`) and its `GunConfig` row.
const GUN := &"smg"


func _init() -> void:
	gun = GUN
	display_name = str(stat("name", "SMG"))
	reach = 32.0



## The held art's footprint (px): width across, length from butt to muzzle.
func art_size() -> Vector2:
	return ART_SIZE


## The flat art's footprint (px): its profile across, its length along.
func flat_size() -> Vector2:
	return FLAT_SIZE


## How far the butt end sits behind the weapon hand's center (px).
func grip_back() -> float:
	return GRIP_BACK


## The weapon hand's stance.
func grip_stance() -> StringName:
	return &"smg_grip"


## The other hand's stance.
func fore_stance() -> StringName:
	return &"smg_fore"


## The weapon hand's stance while the gun is raised off a wall or object.
func raised_grip_stance() -> StringName:
	return &"ready_grip"


## The other hand's stance while the gun is raised off a wall or object.
func raised_fore_stance() -> StringName:
	return &"ready_fore"
