class_name Item extends RefCounted

## Base class for a thing the character can hold and act with. An Item is pure behaviour
## + a little state (e.g. which fist punches next); it owns what the primary (F) and
## secondary (LMB) actions do, how each hand is held, how its weapon is rendered, and what it
## leaves behind when its user dies (drop).
## The character calls into these; an Item talks back only through the small character API
## (facing, weapon_facing(), weapon_raise(), punch(), kick(), hand_position(), muzzle_origin(), world_root(),
## report_shot(), and for reloading best_magazine() / take_magazine() / stow_magazine()), so Items and
## the Character are otherwise independent.

## Shown in the HUD.
var display_name := "Item"
## Punch reach (px), read by the hands to size the swing.
var reach := 28.0
## True while the character is reloading this item (the character sets and clears it).
var reloading := false


## How `hand` (0 = left, 1 = right) is held while this item is out: the name of a stance in
## CharacterConfig.stances — "relaxed" (arm hanging), "guard" (fists up), "aim" (arm out, steady,
## holding a weapon) or "support" (cupping the aiming hand). Default: relaxed.
func hand_stance(_hand: int) -> StringName:
	return &"relaxed"


## Primary action (F). Default: nothing (unarmed).
func primary(_user) -> void:
	pass


## Secondary action (left-click); true when it did something (a gun: a round left the barrel). Default: nothing.
func secondary(_user) -> bool:
	return false


## Advance the item's own clocks (a gun's time between rounds) by `delta` seconds. The character ticks every
## item it carries once per physics frame, held or not. Default: nothing.
func tick(_delta: float) -> void:
	pass


## Whether holding the trigger keeps repeating the secondary action (a controller re-presses it every frame)
## instead of needing a fresh press each time. Default: no.
func is_automatic() -> bool:
	return false


## The hand that holds this item's weapon (the muzzle and the recoil are that hand's). Default: the right.
func weapon_hand() -> int:
	return 1


## How far past the weapon hand the muzzle is (px): bullets leave there, and a long gun reaches further.
## Default: negative, meaning the character's own default reach.
func muzzle_ahead() -> float:
	return -1.0


## Whether the weapon is too long to use against a wall: while its barrel touches a wall or object it is held
## pointing up and cannot shoot. Default: no.
func raises_at_contact() -> bool:
	return false


## How `hand` is held while the weapon is raised off a wall or object (a `CharacterConfig.stances` name).
## Default: held as usual.
func raised_stance(hand: int) -> StringName:
	return hand_stance(hand)


## Rounds loaded right now, or -1 for an item with no ammo (the default).
func rounds_loaded() -> int:
	return -1


## Rounds a full load holds, or -1 for an item with no ammo (the default).
func ammo_capacity() -> int:
	return -1


## Seconds a reload of this item takes. Default: 0 (instant).
func reload_time() -> float:
	return 0.0


## Whether reloading would change anything: a carried magazine fuller than what is loaded. Default: no.
func can_reload(_user) -> bool:
	return false


## The reload time is up: swap the loaded magazine for a carried one (through the character's
## best_magazine / take_magazine / stow_magazine). Default: nothing.
func finish_reload(_user) -> void:
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
