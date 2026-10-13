class_name PistolItem extends GunItem

## A pistol held in the right hand: short enough to fire point-blank at a wall, held at arm's length with the
## other hand cupping the grip. Everything a gun does lives in `GunItem`, tuned by the pistol's `GunConfig` row;
## this supplies its look and its hold.

const PistolPainter = preload("res://scenes/items/art/pistol_painter.gd")
const PistolFlatPainter = preload("res://scenes/items/art/pistol_flat_painter.gd")
## The pistol's footprint lying flat on its side (px): its profile across, its length along.
const FLAT_SIZE := Vector2(9.0, 14.0)
## Pistol sprite footprint (px): width across, length from grip to muzzle.
const ART_SIZE := Vector2(5.0, 13.0)
## How far the grip end sits behind the hand's center (px).
const GRIP_BACK := 2.0

## The kind of magazine it takes (`Magazine.gun`) and its `GunConfig` row.
const GUN := &"pistol"


func _init() -> void:
	gun = GUN
	display_name = str(stat("name", "Pistol"))
	reach = 32.0


## The painter for this gun as held.
func painter() -> Script:
	return PistolPainter


## The painter for this gun lying flat once dropped.
func flat_painter() -> Script:
	return PistolFlatPainter


## The held art's footprint (px): width across, length from butt to muzzle.
func art_size() -> Vector2:
	return ART_SIZE


## The flat art's footprint (px): its profile across, its length along.
func flat_size() -> Vector2:
	return FLAT_SIZE


## How far the butt end sits behind the weapon hand's center (px).
func grip_back() -> float:
	return GRIP_BACK
