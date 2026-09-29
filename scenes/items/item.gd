class_name Item extends RefCounted

## Base class for a thing the character can hold and act with. An Item is pure behaviour
## + a little state (e.g. which fist punches next); it owns what the primary (F) and
## secondary (LMB) actions do, which hands are drawn, and how its weapon is rendered.
## The character calls into these; an Item talks back only through the small character API
## (facing, punch(), hand_position(), muzzle_origin(), world_root(), report_shot()), so
## Items and the Character are otherwise independent.

## Shown in the HUD.
var display_name := "Item"
## Punch reach (px), read by the hands to size the swing.
var reach := 28.0


## Hands to draw for this item: [] none, [1] right only, [0, 1] both.
func visible_hands() -> Array:
	return []


## Primary action (F). Default: nothing (unarmed).
func primary(_user) -> void:
	pass


## Secondary action (left-click). Default: nothing.
func secondary(_user) -> void:
	pass


## Draw the item's weapon art onto `canvas` (the character's visuals Node2D). Default: none.
func draw_weapon(_canvas: CanvasItem, _user) -> void:
	pass
