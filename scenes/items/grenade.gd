class_name GrenadeItem extends Item

## Items domain: a throwable held in the right hand: the logic the stun and the frag grenade share, driven by its
## row in `GrenadeConfig` (docs/grenades.md G1 to G6). It is a *count* carried in its slot (`uses_left()`), spent
## one per throw: left-click (`secondary`) starts a throw, the arm is drawn back in the `throw` stance for `windup`
## seconds (counted in `tick`), and then the grenade leaves the hand as a `ThrownGrenade` flying to the character's
## `aim_target()`. The fuse starts on release; there is no cooking. A character that dies, or puts the grenade away,
## during the wind-up throws nothing. When the last one is thrown the character empties the slot (`Character`).
## It is drawn in its weapon style (`Item.style`) by the row's look (`GrenadeConfig.look`: the painter and colours), and a thrown
## one keeps it. A subclass supplies only the kind id and the art's size (`StunGrenadeItem`, `FragGrenadeItem`).

## The kind's id: its `GrenadeConfig` row. Set by the subclass.
var kind: StringName = &""
## Grenades left in this slot.
var count := 1

var _windup_left := -1.0  ## Seconds until the grenade leaves the hand; negative = no throw under way.
var _user: Node  ## Who is winding up.


# --- What a subclass supplies: size ---------------------------------------------------------

## The art's footprint (px): width across, length along.
func art_size() -> Vector2:
	return Vector2(6.0, 9.0)


# --- Stats (read live from GrenadeConfig, so tuning it takes effect at once) --------------------

## A value from this kind's `GrenadeConfig` row (`fallback` when the row has none).
func stat(key: String, fallback: Variant = null) -> Variant:
	return GrenadeConfig.row(kind).get(key, fallback)


## How it is drawn: its row's look in its weapon style (`GrenadeConfig.look`: `painter`, colours, `finish`).
func look() -> Dictionary:
	return GrenadeConfig.look(kind, style)


# --- Item contract --------------------------------------------------------------------------

## The grenades left in this slot (`Item.uses_left`; -1 is unlimited, for every other item).
func uses_left() -> int:
	return count


## A grenade is thrown (`Item.is_throwable`).
func is_throwable() -> bool:
	return true


## What a holder may know of this grenade before it is thrown: `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }` (`GrenadeConfig.stats_of`).
func throw_stats() -> Dictionary:
	return GrenadeConfig.stats_of(kind, GrenadeConfig.row(kind))


## The weapon hand cocks back in the `throw` stance for the wind-up and otherwise holds the grenade at the chest; the
## other hand hangs.
func hand_stance(hand: int) -> StringName:
	if hand != weapon_hand():
		return &"relaxed"
	return &"throw" if is_winding_up() else &"guard"


## True from the click to the moment the grenade leaves the hand.
func is_winding_up() -> bool:
	return _windup_left >= 0.0


## LMB: start a throw. Nothing with none left or while one is already under way. True when a throw began.
func secondary(user) -> bool:
	if count <= 0 or is_winding_up():
		return false
	_user = user
	_windup_left = float(stat("windup", 0.3))
	return true


## Count the wind-up down and let the grenade go at the end of it. The throw is dropped if the thrower died or no
## longer holds this grenade (a dead character is not ticked, so this is the switch-away case).
func tick(delta: float) -> void:
	if not is_winding_up():
		return
	if not is_instance_valid(_user) or _user.is_dead or _user.current_item() != self:
		_windup_left = -1.0
		return
	_windup_left -= delta
	if _windup_left <= 0.0:
		_release()


## The grenade leaves the hand toward the aim, in this one's weapon style: one is spent, the throw is announced (the Audio
## domain voices it) and the spoon pops off.
func _release() -> void:
	var user := _user
	_windup_left = -1.0
	_user = null
	var from: Vector2 = user.hand_world(weapon_hand())
	var world: Node = user.world_root()
	count -= 1
	ThrownGrenade.spawn(kind, from, user.aim_target(), user, world, style)
	GrenadeSpoon.pop(from, (user.aim_target() - from).angle(), world)
	EventBus.post(&"throw", { "position": from, "kind": kind, "attacker": user })


## Draw the grenade in the hand, the lever still held down (in the look's lever colour): lit for the nearest lighting step,
## drawn rotated to the exact angle of the character's `weapon_facing()`.
func draw_weapon(canvas: CanvasItem, user) -> void:
	var facing: Vector2 = user.weapon_facing()
	var size := art_size()
	var angle := facing.angle() - PI * 0.5
	var tex := _texture(PixelArt.snap_angle(angle), true)
	canvas.draw_set_transform(user.hand_position(weapon_hand()) + facing * 2.0, angle, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The grenade in the air or on the floor (the lever gone), centered at `at` and pointing along `angle`.
func draw_dropped(canvas: CanvasItem, at: Vector2, angle: float, modulate: Color = Color.WHITE,
		_opts: Dictionary = {}) -> void:
	var turn := angle - PI * 0.5
	var size := art_size()
	var tex := _texture(PixelArt.snap_angle(turn), false)
	canvas.draw_set_transform(at, turn, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The grenade's art in its look, lit for the lighting step `angle`, with the lever held down (`spoon`) or gone.
func _texture(angle: float, spoon: bool) -> Texture2D:
	var drawn := look()
	var tex := PixelArt.render_turned(drawn["painter"], art_size(), drawn["shell"], angle, drawn["finish"],
		{ "kind": kind, "look": _look_handle(drawn), "spoon": spoon })
	_note_drawn(tex)
	return tex
