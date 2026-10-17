class_name Item extends RefCounted

## Items domain: base class for a thing the character can hold and act with. An Item is pure
## behaviour + a little state (e.g. which fist punches next); it owns what the primary (F) and
## secondary (LMB) actions do, how each hand is held, how its weapon is rendered, and what it leaves
## behind when its user dies (drop).
## The character calls into these; an Item talks back only through the small character API
## (facing, weapon_facing(), weapon_raise(), punch(), punch_amount(), kick(), hand_position(), hand_world(), muzzle_origin(),
## world_root(), report_shot(), aim_target(), aim_sway(), current_item(), and for reloading best_magazine() /
## take_magazine() / stow_magazine()), so Items and the Character are otherwise independent.

const WeaponArt = preload("res://scenes/items/art/weapon_art.gd")

## Shown in the HUD.
var display_name := "Item"
## Punch reach (px), read by the hands to size the swing.
var reach := 28.0
## True while the character is reloading this item (the character sets and clears it).
var reloading := false
## The weapon style it is drawn in, its wielder's (`police` issue for the invaders, `scrap` or `pipe` for a defender): stamped
## on every item a loadout makes (`ItemRegistry.inventory_for`, from `LoadoutConfig.apply`). An item never given one is `police`.
## A gun or grenade draws its config row's look for it (`GunConfig.look` / `GrenadeConfig.look`); a dropped gun and a thrown
## grenade keep it. Looks only: nothing it does depends on it.
var style: StringName = &"police"

var _art: Array[Texture2D] = []  ## The textures the last frame's draws of the item painted, in order (`drawn_art`).
var _art_frame := -1             ## The process frame `_art` was painted in.
var _look_row := {}              ## The look last drawn (a config `looks` row) and its painters' handle, so it is hashed once.
var _look_id := 0                ## The painters' handle of `_look_row`.


## How `hand` (0 = right as drawn, 1 = left) is held while this item is out: the name of a stance in
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


## The hand that holds this item's weapon (the muzzle and the recoil are that hand's). Default: the right (hand 0).
func weapon_hand() -> int:
	return 0


## How far past the weapon hand the muzzle is (px): bullets leave there, and a long gun reaches further.
## Default: negative, meaning the character's own default reach.
func muzzle_ahead() -> float:
	return -1.0


## How far (px) behind the weapon hand this item's striking end sits when held, which a melee blow swings round to lead
## with (a long gun's butt). 0 = the fist leads.
func strike_ahead() -> float:
	return 0.0


## How far (rad) the weapon turns about the weapon hand, outward from the body, by the end of a blow: short of a half
## turn, so it ends nearly across the body with the striking end a little ahead of the far end.
func strike_turn() -> float:
	return 0.0


## How far round the weapon has swung, 0 (held as usual) .. 1 (at `strike_turn`), at a punch `amount` (0 resting ..
## 1 fully thrown).
func strike_swing(amount: float) -> float:
	return smoothstep(0.0, 0.6, amount) if strike_ahead() > 0.0 else 0.0


## The way the weapon points at a punch `amount` when held along `aim`.
func strike_direction(aim: Vector2, amount: float) -> Vector2:
	return aim.rotated(strike_turn() * strike_swing(amount) * (1.0 if weapon_hand() == 0 else -1.0))


## Where the striking end is, relative to the weapon hand, when the weapon is held along `aim` at a punch `amount`.
func strike_end(aim: Vector2, amount: float) -> Vector2:
	return -strike_direction(aim, amount) * strike_ahead()


## How far (px) ahead of the weapon hand the striking end ends up at a full blow: the hands shorten the punch's
## extension by it, so a blow lands as far out as ever.
func strike_forward() -> float:
	return strike_ahead() * maxf(-cos(strike_turn()), 0.0)


## How much (px) shorter than a fist's the blow reaches: a weapon held in both hands cannot be thrown as far.
func strike_short() -> float:
	return 0.0


## How far (px) along the weapon from the weapon hand the other hand grips (negative: toward the striking end). It holds
## on as the weapon turns. 0 = it does not follow.
func strike_support_gap() -> float:
	return 0.0


## How many times slower than a fist the weapon's blow is thrown (a heavy weapon swings, it does not jab).
func strike_tempo() -> float:
	return 1.0


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


## The id of the gun this item is (a `GunConfig` row), or &"" for an item that is not a gun (the default).
func gun_id() -> StringName:
	return &""


## The penetration power of the rounds it fires (1 = a pistol round); 1 for an item that fires none (the default).
func round_power() -> float:
	return 1.0


## How many uses are left: a grenade's count, spent one per throw. -1 for an item that is never used up (the default).
func uses_left() -> int:
	return -1


## Whether the item is thrown rather than fired or swung (a grenade). Default: no.
func is_throwable() -> bool:
	return false


## What a holder may know of a throwable before throwing it, `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }` (a grenade's
## numbers: how far a throw first comes down, how far its burst reaches, the seconds to it, how near furniture must be to shield from a flash).
## Default: nothing ({}), as for every item that is not thrown.
func throw_stats() -> Dictionary:
	return {}


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


## The textures the item's last draw (`draw_weapon` or `draw_dropped`, every call in the frame it was last drawn: a lying item's
## shadow and art) painted, in order. Pixel art is cached by what it depicts, so the same drawing gives the same textures and a
## changed look new ones. Empty for an item never drawn or that draws nothing.
func drawn_art() -> Array:
	return _art.duplicate()


## Record `tex` as painted by this frame's draw of the item (`drawn_art`).
func _note_drawn(tex: Texture2D) -> void:
	var frame := Engine.get_process_frames()
	if frame != _art_frame:
		_art_frame = frame
		_art.clear()
	if not _art.has(tex):
		_art.append(tex)


## The painters' handle of `look` (a gun's or grenade's config `looks` row, weapon_art.gd), registered again only when the row
## drawn is another one (a new style, or a config row replaced).
func _look_handle(look: Dictionary) -> int:
	if not is_same(look, _look_row):
		_look_row = look
		_look_id = WeaponArt.register(look)
	return _look_id


## Paint ahead of time the art this item can be drawn with, so no first paint lands mid-fight (`ItemRegistry` asks every item
## it makes). Only fills PixelArt's cache with the textures the draws would paint: what is drawn never changes. Default: none.
func prepaint() -> void:
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
