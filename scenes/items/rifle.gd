class_name RifleItem extends GunItem

## Items domain: an assault rifle: a long automatic shouldered with the butt against the shoulder, the trigger
## hand at the grip and the other hand out on the foregrip, both lying along the barrel. Everything a gun does
## lives in `GunItem`, tuned by the rifle's `GunConfig` row (heavy, fast, penetrating rounds; its look too); this supplies its
## sizes and its hold. Its barrel is too long for a wall: touching one, it comes up off the aim, pointing up with
## the butt still on the shoulder, and cannot fire.

## The rifle's footprint lying flat on its side (px): its profile across, its length along.
const FLAT_SIZE := Vector2(12.0, 38.0)
## Rifle sprite footprint (px): width across, length from butt to muzzle.
const ART_SIZE := Vector2(7.0, 36.0)
## How far the butt end sits behind the hand's center (px): the hand grips the pistol grip, the butt is on the
## shoulder.
const GRIP_BACK := 13.0

## The kind of magazine it takes (`Magazine.gun`) and its `GunConfig` row.
const GUN := &"rifle"


func _init() -> void:
	gun = GUN
	display_name = str(stat("name", "Assault rifle"))
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
	return &"rifle_grip"


## The other hand's stance.
func fore_stance() -> StringName:
	return &"rifle_fore"


## The weapon hand's stance while the gun is raised off a wall or object.
func raised_grip_stance() -> StringName:
	return &"ready_grip"


## The other hand's stance while the gun is raised off a wall or object.
func raised_fore_stance() -> StringName:
	return &"ready_fore"
