class_name Item extends RefCounted

## Base class for a thing the character can hold and act with. An Item is pure behaviour
## + a little state (e.g. which fist punches next); it owns what the primary (F) and
## secondary (LMB) actions do, which hands are drawn, how its weapon is rendered, and what it
## leaves behind when its user dies (drop).
## The character calls into these; an Item talks back only through the small character API
## (facing, weapon_facing(), punch(), kick(), hand_position(), muzzle_origin(), world_root(),
## report_shot()), so Items and the Character are otherwise independent.

## Shown in the HUD.
var display_name := "Item"
## Punch reach (px), read by the hands to size the swing.
var reach := 28.0


## Hands to draw for this item: [] none, [1] right only, [0, 1] both.
func visible_hands() -> Array:
	return []


## Hands that aim a held weapon: the character keeps them steady and quick to the aim instead of
## swinging them with the walk. Default: none.
func aiming_hands() -> Array:
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
