class_name GunItem extends Item

## Items domain: a gun held in the right hand: the logic every firearm shares, driven by its row in `GunConfig`
## (damage, fire rate, penetration, muzzle speed, spread, recoil, whether it is automatic and whether its
## barrel is too long to use against a wall). F still jabs with the weapon hand (melee); left-click fires a
## projectile and ejects a casing. It is drawn in its weapon style (`Item.style`) by the row's look (`GunConfig.look`: the
## painter and colours). A subclass supplies only its sizes and how it is held (`PistolItem`, `SmgItem`, `RifleItem`): the gun
## id, the art's footprints, where the hand grips it and the stances.
## Items reach into the Projectile System in two places: here, via ProjectileSpawner / CasingSpawner (a
## shot's `hit` is forwarded back to the character's `report_shot` for the HUD), and ThrownGrenade, via
## `Explosion.frag` / `Explosion.stun`.

## How far the pulled-up barrel shortens at full raise (fraction of its length): pointed up, a top-down view
## sees it foreshortened. The art is re-rendered at `RAISE_STEPS` lengths between full and this, so it stays crisp
## and cached.
const RAISED_LENGTH := 0.42
const RAISE_STEPS := 5
## How far (px) along a long gun's barrel from the weapon hand the support hand grips through a butt strike: toward the
## butt, so the other arm does not reach across the weapon hand.
const SUPPORT_GAP := -8.0
## How far (rad) a long gun turns in a butt strike: nearly across the body (105 degrees), the butt a little ahead of the muzzle.
const STRIKE_TURN := 1.833
## How far (px) short of a fist's reach a long gun's blow lands.
const STRIKE_SHORT := 5.0

## The gun's id: its `GunConfig` row and the kind of magazine it takes (`Magazine.gun`). Set by the subclass.
var gun: StringName = &""
## The magazine it is loaded with (null = unloaded); every shot spends one of its rounds.
var magazine: Magazine

## Seconds until the next round may leave. Counts down in `tick`; firing adds the fire interval, so an
## overshoot carries into the next round and the rate holds even when it is not a whole number of frames.
var _cooldown := 0.0


# --- What a subclass supplies: sizes and hold --------------------------------------------------

## The held art's footprint (px): width across, length from butt to muzzle.
func art_size() -> Vector2:
	return Vector2(5.0, 13.0)


## The flat art's footprint (px): its profile across, its length along.
func flat_size() -> Vector2:
	return Vector2(9.0, 14.0)


## How far the butt end sits behind the weapon hand's center (px).
func grip_back() -> float:
	return 2.0


## The weapon hand's stance, held normally.
func grip_stance() -> StringName:
	return &"aim"


## The other hand's stance, held normally.
func fore_stance() -> StringName:
	return &"support"


## The weapon hand's stance while the weapon is raised off a wall or object.
func raised_grip_stance() -> StringName:
	return grip_stance()


## The other hand's stance while the weapon is raised off a wall or object.
func raised_fore_stance() -> StringName:
	return fore_stance()


# --- Stats (read live from GunConfig, so tuning it takes effect at once) ---------------------

## A value from this gun's `GunConfig` row (`fallback` when the row has none).
func stat(key: String, fallback: Variant = null) -> Variant:
	return GunConfig.row(gun).get(key, fallback)


## Damage added on top of the projectile's own base damage at fire time.
func damage() -> float:
	return float(stat("damage", 0.0))


## Seconds between rounds.
func fire_interval() -> float:
	return float(stat("fire_interval", 0.0))


## How it is drawn: its row's look in its weapon style (`GunConfig.look`: `painter`, colours, `finish`).
func look() -> Dictionary:
	return GunConfig.look(gun, style)


# --- Item contract --------------------------------------------------------------------------

## The gun's id.
func gun_id() -> StringName:
	return gun


## The penetration power of its rounds (the row's `penetration`).
func round_power() -> float:
	return float(stat("penetration", 1.0))


## The weapon hand aims the gun and holds its grip; the other hand holds it forward, or while reloading drops to
## the belt for the next magazine.
func hand_stance(hand: int) -> StringName:
	if hand == weapon_hand():
		return grip_stance()
	return &"reload" if reloading else fore_stance()


## How `hand` is held while the weapon is raised: the weapon hand's raised stance; the other hand's, or the belt while reloading.
func raised_stance(hand: int) -> StringName:
	if hand == weapon_hand():
		return raised_grip_stance()
	return &"reload" if reloading else raised_fore_stance()


## Whether holding the trigger keeps firing (the row's `automatic`).
func is_automatic() -> bool:
	return bool(stat("automatic", false))


## Whether the barrel is too long to use against a wall (the row's `raises_at_contact`).
func raises_at_contact() -> bool:
	return bool(stat("raises_at_contact", false))


## Past the hand: the art's length less the butt behind it.
func muzzle_ahead() -> float:
	return art_size().y - grip_back()


## Count the time between rounds down. The credit for an overshoot is capped at one frame, so a gun left idle
## fires its next round at once but never a burst to catch up.
func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, -delta)


## Rounds left in the loaded magazine (0 when unloaded).
func rounds_loaded() -> int:
	return magazine.rounds if magazine else 0


## Rounds the loaded magazine holds when full (0 when unloaded).
func ammo_capacity() -> int:
	return magazine.capacity if magazine else 0


## How long a reload takes: the loaded magazine's type decides (`MagazineConfig.reload_time_of`).
func reload_time() -> float:
	var type: StringName = magazine.type if magazine else StringName(stat("magazine", &"standard"))
	return MagazineConfig.reload_time_of(type)


## A carried magazine holds more rounds than the one loaded.
func can_reload(user) -> bool:
	var best: Magazine = user.best_magazine(gun)
	return best != null and best.rounds > rounds_loaded()


## Seat the fullest carried magazine; the one it replaces goes back into the carried store unless it is
## empty (nothing refills a magazine, so an empty one is dropped).
func finish_reload(user) -> void:
	var fresh: Magazine = user.take_magazine(gun)
	if fresh == null:
		return
	var spent := magazine
	magazine = fresh
	if spent != null and spent.rounds > 0:
		user.stow_magazine(spent)


## A long gun (the kind too long for a wall) strikes with its butt: its length behind the grip.
func strike_ahead() -> float:
	return grip_back() if raises_at_contact() else 0.0


## How far (px) the other hand grips ahead of the weapon hand along the barrel: it holds the gun through a butt strike.
func strike_support_gap() -> float:
	return SUPPORT_GAP if raises_at_contact() else 0.0


## A long gun swung in both hands lands a little short of a fist's reach, which keeps the support arm from overstretching.
func strike_short() -> float:
	return STRIKE_SHORT if raises_at_contact() else 0.0


## A long gun turns nearly across the body in a butt strike.
func strike_turn() -> float:
	return STRIKE_TURN if raises_at_contact() else 0.0


## A long gun is swung twice as slowly as a fist is thrown.
func strike_tempo() -> float:
	return 2.0 if raises_at_contact() else 1.0


## F: a melee jab with the weapon hand; a long gun swings round and leads with its butt.
func primary(user) -> void:
	user.punch(weapon_hand())


## LMB: fire a bullet from the muzzle and eject a casing (both live in world space); the gun kicks
## the hand back. Spends a round; an empty, mid-reload or still-cycling gun does nothing. The round leaves
## within the gun's spread of the aim. True when a round left the barrel.
func secondary(user) -> bool:
	if reloading or rounds_loaded() <= 0 or _cooldown > 0.0:
		return false
	magazine.rounds -= 1
	_cooldown += fire_interval()
	var hand := weapon_hand()
	var muzzle: Vector2 = user.muzzle_origin(hand)
	# Zeroed: the round crosses the aim line `zero_range` ahead of the body, so a gun held off the line (the
	# butt on the right shoulder) still shoots where the character points.
	var direction: Vector2 = (user.global_position + user.facing * GunConfig.zero_range - muzzle).normalized()
	direction = direction.rotated(user.aim_sway())  # A stunned character's aim wanders off the line.
	var spread := deg_to_rad(float(stat("spread_deg", 0.0)))
	if spread > 0.0:
		direction = direction.rotated(randf_range(-spread, spread))
	var power := round_power()
	var proj := ProjectileSpawner.spawn(muzzle, direction, user.world_root(), user, damage(),
		float(stat("muzzle_speed", -1.0)), power)
	proj.hit.connect(func(body: Node, dmg: float) -> void: user.report_shot(body, dmg))
	CasingSpawner.spawn(user.hand_world(hand), user.facing, user.world_root())
	user.kick(hand, float(stat("recoil", 1.0)))
	# The report of the shot, for whoever listens (the Audio domain); the round itself is already on its way.
	EventBus.post(&"shot", { "position": muzzle, "gun": gun, "attacker": user, "power": power })
	return true


## Draw the gun's pixel art at the weapon hand, its butt behind the hand and the muzzle along the
## character's weapon_facing() (trailing the aim a touch as it turns): lit for the nearest lighting
## step, drawn rotated to the exact angle. Raised off a wall, the barrel foreshortens about the hand.
func draw_weapon(canvas: CanvasItem, user) -> void:
	var facing: Vector2 = user.weapon_facing()
	# A punch turns a long gun about its grip until the butt leads.
	facing = strike_direction(facing, user.punch_amount(weapon_hand()))
	var step := clampi(roundi(float(user.weapon_raise()) * RAISE_STEPS), 0, RAISE_STEPS)
	var shrink := lerpf(1.0, RAISED_LENGTH, float(step) / RAISE_STEPS)
	var size := Vector2(art_size().x, maxf(roundf(art_size().y * shrink), 4.0))
	var centre: Vector2 = user.hand_position(weapon_hand()) + facing * (size.y * 0.5 - grip_back() * shrink)
	_draw_art(canvas, centre, facing, size)


## The dead hand lets go: the gun leaves from where it was drawn and skids off at `velocity`.
func drop(user, velocity: Vector2) -> Node2D:
	var facing: Vector2 = user.weapon_facing()
	var hand: Vector2 = user.hand_world(weapon_hand())
	var at := hand + facing * (art_size().y * 0.5 - grip_back())
	return DroppedItem.spawn(self, at, facing.angle(), velocity, user.world_root(), hand)


## The gun lying flat on its side, centered at `at`, its muzzle along `angle`, in its look's painter lying (`flat`); `opts.flip`
## picks the side facing up.
func draw_dropped(canvas: CanvasItem, at: Vector2, angle: float, modulate: Color = Color.WHITE,
		opts: Dictionary = {}) -> void:
	var turn := angle - PI * 0.5
	var size := flat_size()
	var flip: bool = opts.get("flip", false)
	var drawn := look()
	var tex := PixelArt.render_turned(drawn["painter"], size, drawn["body"], PixelArt.snap_angle(turn), drawn["finish"],
		{ "gun": gun, "look": _look_handle(drawn), "flat": true, "flip": flip })
	_note_drawn(tex)
	canvas.draw_set_transform(at, turn, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The held art of `size` centered at `centre`, muzzle along `facing`, in its look's painter: lit for the nearest lighting
## step, drawn rotated to the exact angle.
func _draw_art(canvas: CanvasItem, centre: Vector2, facing: Vector2, size: Vector2) -> void:
	var angle := facing.angle() - PI * 0.5
	var drawn := look()
	var tex := PixelArt.render_turned(drawn["painter"], size, drawn["body"], PixelArt.snap_angle(angle), drawn["finish"],
		{ "gun": gun, "look": _look_handle(drawn) })
	_note_drawn(tex)
	canvas.draw_set_transform(centre, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
