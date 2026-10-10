class_name PistolItem extends Item

## A pistol held in the right hand. F still jabs with that hand (melee); left-click fires
## a projectile and ejects a casing. This is the one place Items reach into the Projectile
## System — via ProjectileSpawner / CasingSpawner — and it forwards the bullet's `hit`
## back to the character's `report_shot` for the HUD.

const WEAPON_HAND := 1
const PistolPainter = preload("res://scenes/items/pistol_painter.gd")
## Pistol sprite footprint (px): width across, length from grip to muzzle.
const ART_SIZE := Vector2(5.0, 13.0)
## How far the grip end sits behind the hand's center (px).
const GRIP_BACK := 2.0

## Damage added on top of the projectile's own base damage at fire time.
var damage := 15.0
## Pistol art color (the slide's metal).
var color := Color(0.3, 0.3, 0.3)


func _init() -> void:
	display_name = "Pistol"
	reach = 32.0


## Only the weapon hand is shown.
func visible_hands() -> Array:
	return [WEAPON_HAND]


## The weapon hand aims the pistol.
func aiming_hands() -> Array:
	return [WEAPON_HAND]


## F: a melee jab with the weapon hand.
func primary(user) -> void:
	user.punch(WEAPON_HAND)


## LMB: fire a bullet from the muzzle and eject a casing (both live in world space); the gun kicks
## the hand back.
func secondary(user) -> void:
	var proj := ProjectileSpawner.spawn(user.muzzle_origin(WEAPON_HAND), user.facing, user.world_root(), user, damage)
	proj.hit.connect(func(body: Node, dmg: float) -> void: user.report_shot(body, dmg))
	CasingSpawner.spawn(user.hand_world(WEAPON_HAND), user.facing, user.world_root())
	user.kick(WEAPON_HAND)


## Draw the pistol's pixel art at the weapon hand, its grip in the hand and the muzzle along the
## character's weapon_facing() (trailing the aim a touch as it turns): lit for the nearest lighting
## step, drawn rotated to the exact angle.
func draw_weapon(canvas: CanvasItem, user) -> void:
	var hand_pos: Vector2 = user.hand_position(WEAPON_HAND)
	var facing: Vector2 = user.weapon_facing()
	var angle := facing.angle() - PI * 0.5
	var tex := PixelArt.render_turned(PistolPainter, ART_SIZE, color, PixelArt.snap_angle(angle), "metal")
	var centre := hand_pos + facing * (ART_SIZE.y * 0.5 - GRIP_BACK)
	canvas.draw_set_transform(centre, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-ART_SIZE * 0.5, ART_SIZE), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
