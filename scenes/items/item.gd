class_name Item extends RefCounted

## Base class for a thing the character can hold and act with. An Item is pure behaviour
## + a little state (e.g. which fist punches next); it owns what the primary (F) and
## secondary (LMB) actions do, how each hand is held, how its weapon is rendered, and what it
## leaves behind when its user dies (drop).
## The character calls into these; an Item talks back only through the small character API
## (facing, weapon_facing(), punch(), kick(), hand_position(), muzzle_origin(), world_root(),
## report_shot()), so Items and the Character are otherwise independent.

## Shown in the HUD.
var display_name := "Item"
## Punch reach (px), read by the hands to size the swing.
var reach := 28.0


## How `hand` (0 = left, 1 = right) is held while this item is out: the name of a stance in
## CharacterConfig.stances — "relaxed" (arm hanging), "guard" (fists up), "aim" (arm out, steady,
## holding a weapon) or "support" (cupping the aiming hand). Default: relaxed.
func hand_stance(_hand: int) -> StringName:
	return &"relaxed"


## Primary action (F). Default: nothing (unarmed).
func primary(_user) -> void:
	pass


## Secondary action (left-click). Default: nothing.
func secondary(_user) -> void:
	pass


## Draw the item's weapon art onto `canvas` (the character's visuals Node2D). Default: none.
func draw_weapon(_canvas: CanvasItem, _user) -> void:
	pass


## Let go of the item into the world (its user has died), flying off at `velocity`; returns the
## dropped node, or null when nothing is left behind (the default).
func drop(_user, _velocity: Vector2) -> Node2D:
	return null


## Draw the item lying loose, centered at `at` on `canvas` and pointing along `angle`, tinted by
## `modulate` (its art, or its shadow). `opts` is how it landed, picked once when dropped
## (`flip`: which side faces up). Default: none.
func draw_dropped(_canvas: CanvasItem, _at: Vector2, _angle: float, _modulate: Color = Color.WHITE,
		_opts: Dictionary = {}) -> void:
	pass
