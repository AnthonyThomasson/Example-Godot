class_name PistolItem extends Item

## A pistol held in the right hand. F still jabs with that hand (melee); left-click fires
## a projectile and ejects a casing. This is the one place Items reach into the Projectile
## System — via ProjectileSpawner / CasingSpawner — and it forwards the bullet's `hit`
## back to the character's `report_shot` for the HUD.

const WEAPON_HAND := 1
const PistolPainter = preload("res://scenes/items/pistol_painter.gd")
const PistolFlatPainter = preload("res://scenes/items/pistol_flat_painter.gd")
## The pistol's footprint lying flat on its side (px): its profile across, its length along.
const FLAT_SIZE := Vector2(9.0, 14.0)
## Pistol sprite footprint (px): width across, length from grip to muzzle.
const ART_SIZE := Vector2(5.0, 13.0)
## How far the grip end sits behind the hand's center (px).
const GRIP_BACK := 2.0

## The kind of magazine it takes (`Magazine.gun`).
const GUN := &"pistol"

## Damage added on top of the projectile's own base damage at fire time.
var damage := 15.0
## Pistol art color (the slide's metal).
var color := Color(0.3, 0.3, 0.3)
## The magazine it is loaded with (null = unloaded); every shot spends one of its rounds.
var magazine: Magazine


func _init() -> void:
	display_name = "Pistol"
	reach = 32.0


## The weapon hand aims the pistol; the other hand cups its grip, or while reloading drops to the belt
## for the next magazine.
func hand_stance(hand: int) -> StringName:
	if hand == WEAPON_HAND:
		return &"aim"
	return &"reload" if reloading else &"support"


## Rounds left in the loaded magazine (0 when unloaded).
func rounds_loaded() -> int:
	return magazine.rounds if magazine else 0


## Rounds the loaded magazine holds when full (0 when unloaded).
func ammo_capacity() -> int:
	return magazine.capacity if magazine else 0


## `MagazineConfig.reload_time`.
func reload_time() -> float:
	return MagazineConfig.reload_time


## A carried magazine holds more rounds than the one loaded.
func can_reload(user) -> bool:
	var best: Magazine = user.best_magazine(GUN)
	return best != null and best.rounds > rounds_loaded()


## Seat the fullest carried magazine; the one it replaces goes back into the carried store unless it is
## empty (nothing refills a magazine, so an empty one is dropped).
func finish_reload(user) -> void:
	var fresh: Magazine = user.take_magazine(GUN)
	if fresh == null:
		return
	var spent := magazine
	magazine = fresh
	if spent != null and spent.rounds > 0:
		user.stow_magazine(spent)


## F: a melee jab with the weapon hand.
func primary(user) -> void:
	user.punch(WEAPON_HAND)


## LMB: fire a bullet from the muzzle and eject a casing (both live in world space); the gun kicks
## the hand back. Spends a round; an empty (or mid-reload) gun does nothing.
func secondary(user) -> void:
	if reloading or rounds_loaded() <= 0:
		return
	magazine.rounds -= 1
	var proj := ProjectileSpawner.spawn(user.muzzle_origin(WEAPON_HAND), user.facing, user.world_root(), user, damage)
	proj.hit.connect(func(body: Node, dmg: float) -> void: user.report_shot(body, dmg))
	CasingSpawner.spawn(user.hand_world(WEAPON_HAND), user.facing, user.world_root())
	user.kick(WEAPON_HAND)


## Draw the pistol's pixel art at the weapon hand, its grip in the hand and the muzzle along the
## character's weapon_facing() (trailing the aim a touch as it turns): lit for the nearest lighting
## step, drawn rotated to the exact angle.
func draw_weapon(canvas: CanvasItem, user) -> void:
	var facing: Vector2 = user.weapon_facing()
	_draw_art(canvas, user.hand_position(WEAPON_HAND) + facing * (ART_SIZE.y * 0.5 - GRIP_BACK), facing)


## The dead hand lets go: the pistol leaves from where it was drawn and skids off at `velocity`.
func drop(user, velocity: Vector2) -> Node2D:
	var facing: Vector2 = user.weapon_facing()
	var hand: Vector2 = user.hand_world(WEAPON_HAND)
	var at := hand + facing * (ART_SIZE.y * 0.5 - GRIP_BACK)
	return DroppedItem.spawn(self, at, facing.angle(), velocity, user.world_root(), hand)


## The pistol lying flat on its side, centered at `at`, its muzzle along `angle`; `opts.flip` picks
## the side facing up.
func draw_dropped(canvas: CanvasItem, at: Vector2, angle: float, modulate: Color = Color.WHITE,
		opts: Dictionary = {}) -> void:
	var turn := angle - PI * 0.5
	var tex := PixelArt.render_turned(PistolFlatPainter, FLAT_SIZE, color, PixelArt.snap_angle(turn), "metal",
		{ "flip": opts.get("flip", false) })
	canvas.draw_set_transform(at, turn, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-FLAT_SIZE * 0.5, FLAT_SIZE), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The pistol's held art centered at `centre`, muzzle along `facing`: lit for the nearest lighting
## step, drawn rotated to the exact angle.
func _draw_art(canvas: CanvasItem, centre: Vector2, facing: Vector2) -> void:
	var angle := facing.angle() - PI * 0.5
	var tex := PixelArt.render_turned(PistolPainter, ART_SIZE, color, PixelArt.snap_angle(angle), "metal")
	canvas.draw_set_transform(centre, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-ART_SIZE * 0.5, ART_SIZE), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
