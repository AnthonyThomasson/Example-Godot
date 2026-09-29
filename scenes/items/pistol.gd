class_name PistolItem extends Item

## A pistol held in the right hand. F still jabs with that hand (melee); left-click fires
## a projectile and ejects a casing. This is the one place Items reach into the Projectile
## System — via ProjectileSpawner / CasingSpawner — and it forwards the bullet's `hit`
## back to the character's `report_shot` for the HUD.

const WEAPON_HAND := 1

## Damage added on top of the projectile's own base damage at fire time.
var damage := 15.0
## Pistol art color.
var color := Color(0.3, 0.3, 0.3)


func _init() -> void:
	display_name = "Pistol"
	reach = 32.0


## Only the weapon hand is shown.
func visible_hands() -> Array:
	return [WEAPON_HAND]


## F: a melee jab with the weapon hand.
func primary(user) -> void:
	user.punch(WEAPON_HAND)


## LMB: fire a bullet from the muzzle and eject a casing (both live in world space).
func secondary(user) -> void:
	var proj := ProjectileSpawner.spawn(user.muzzle_origin(WEAPON_HAND), user.facing, user.world_root(), user, damage)
	proj.hit.connect(func(body: Node, dmg: float) -> void: user.report_shot(body, dmg))
	CasingSpawner.spawn(user.hand_world(WEAPON_HAND), user.facing, user.world_root())


## Draw a simple pistol at the weapon hand, aligned with facing (barrel line + grip).
func draw_weapon(canvas: CanvasItem, user) -> void:
	var hand_pos: Vector2 = user.hand_position(WEAPON_HAND)
	var facing: Vector2 = user.facing
	var barrel_len := 9.0
	var barrel_width := 2.0
	var barrel_offset := 5.0  # How far forward from the hand.
	var barrel_start := hand_pos + facing * barrel_offset
	var barrel_end := barrel_start + facing * barrel_len
	canvas.draw_line(barrel_start, barrel_end, color, barrel_width)
	var grip_radius := 3.0
	canvas.draw_circle(hand_pos, grip_radius, color)
	canvas.draw_arc(hand_pos, grip_radius, 0.0, TAU, 12, Color.WHITE, 1.0, true)
