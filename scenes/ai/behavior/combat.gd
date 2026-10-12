extends RefCounted

## AI BEHAVIOUR sub-domain — COMBAT. Everything a fight does with the character's hands: taking a shot, throwing a punch,
## keeping an automatic gun's trigger down for a burst, stepping back when a barrel is against a wall, the reload reflex,
## and the peek-and-cover cycle (step out, shoot, duck) with its committed firing / cover spot. Owns the fire cooldown
## and that cycle's phase and timers. `Behavior` decides WHICH fight is on (it holds the engaged contact and the hold-ground
## flag) and passes the target in each call; this class never chooses a target and reads the world only through the
## perception (`has_line_to`, `combat_spots`, `note_engaged`) and the character's public contract. It knows no gun from
## another: the gun it fights with is `Character.gun_slot()`.

## The gun is empty: the shot was not taken (a click is not a shot), so the caller should re-decide.
signal dry

## Inventory slot of the fists (ItemRegistry id). The gun it shoots is whatever the character fights with.
const FISTS_SLOT := 2
## Facing error (radians) within which a shot is taken — aim settles a frame after it is set.
const AIM_TOLERANCE := 0.15

# --- Config fields `Behavior.apply_config()` copies in. ---
var shoot_range: float = 500.0
var punch_range: float = 48.0
var ring_radius: float = 80.0  ## Radius of the ring of candidate firing / cover spots around the target.
var ring_count: int = 12       ## Candidate spots on that ring.
var cover_time: float = 1.2
var fire_cooldown: float = 0.5
## Rounds an automatic gun fires per trigger pull (paced by the gun's own fire rate); a single-shot gun fires one.
var fire_burst: int = 3
## Seconds spent stepping back when the gun's barrel is against a wall or object and cannot fire.
var back_off_time: float = 0.45
var reposition_interval: float = 0.5
var auto_reload: bool = true   ## An empty gun with a spare magazine is reloaded on its own while holding or ducked in cover.

var phase := "peek"            ## Peek-and-cover phase: "peek" (seek a shot) or "cover" (duck).
var cover_timer := 0.0         ## Seconds left ducking behind cover before peeking again.
var fire_timer := 0.0          ## Seconds left before the next shot/punch may be thrown.
var dest := Vector2.ZERO       ## Committed fire/cover position the NPC is steering toward.
var dest_timer := 0.0          ## Seconds left before a new combat position may be chosen.

var _burst_left := 0           ## Rounds still to fire in the automatic gun's current burst.
var _back_off_timer := 0.0     ## Seconds left stepping back from whatever the gun's barrel is against.
var _loco: Node                ## The Locomotion child (pathing, rooms).
var _perception: Node          ## The perception sub-domain (line of fire, candidate spots, engagement memory).


## Capture the locomotion and the perception. Called once by `Behavior.setup()`.
func setup(loco: Node, perception: Node) -> void:
	_loco = loco
	_perception = perception


## A fight begins: the cycle starts in its peek phase and a firing spot is picked at once.
func begin_fight() -> void:
	phase = "peek"
	dest_timer = 0.0


## Advance the fire cooldown by `delta`.
func tick(delta: float) -> void:
	fire_timer -= delta


## Whether `target` (a known-contact dict) can be shot at now: a loaded gun not mid-reload, the target within range, and a clear
## line to where it is known to be. The cooldown, the facing and a run are not counted: they pass in a moment, this says
## the NPC is in a position to fire.
func can_fire_at(character, target: Dictionary) -> bool:
	var gun: int = character.gun_slot()
	if gun < 0 or character.ammo(gun) == 0 or character.is_reloading() or target.is_empty():
		return false
	var pos: Vector2 = target["pos"]
	return character.global_position.distance_to(pos) <= shoot_range and _perception.has_line_to(character, target["node"], pos)


## Shoot `target` (a known-contact dict) when it can be shot at (`can_fire_at`), once the facing has settled on it; aims at it
## meanwhile. No-op otherwise.
func fire_at_will(character, target: Dictionary) -> void:
	if not can_fire_at(character, target):
		return
	var pos: Vector2 = target["pos"]
	character.aim_point = pos
	if fire_timer <= 0.0 and _faces(character, pos):
		shoot(character)


## Ambush: hold the covered spot and fire the moment a line to the known position opens.
func ambush(character, node, pos: Vector2) -> void:
	character.move_input = Vector2.ZERO
	if character.global_position.distance_to(pos) <= shoot_range \
			and _perception.has_line_to(character, node, pos) and fire_timer <= 0.0 and _faces(character, pos):
		shoot(character)


## Peek-and-cover shooting at the known contact (`node` at `pos`): in the PEEK phase, move to a spot with a clear shot and
## fire, then duck; in the COVER phase, hold behind a shielding object for `cover_time` before peeking again. The
## fire/cover destination is committed for `reposition_interval` rather than re-picked every frame, so the NPC steers
## smoothly instead of vibrating between near-equal candidates. `hold_ground` keeps the chosen spots inside the house.
func peek_cover(character, delta: float, node, pos: Vector2, hold_ground: bool) -> void:
	var dist: float = character.global_position.distance_to(pos)
	dest_timer -= delta
	if phase == "cover":
		cover_timer -= delta
		if dest_timer <= 0.0:
			dest = _choose_dest(character, "cover", node, pos, hold_ground)
			dest_timer = reposition_interval
		_loco.move_to(character, dest)
		reload_if_dry(character)
		if cover_timer <= 0.0:
			phase = "peek"
			dest_timer = 0.0  # Re-pick a firing spot immediately on peeking out.
		return
	# PEEK: take the shot if a clear line to the known position is in range, else reposition to get one.
	if dist <= shoot_range and _perception.has_line_to(character, node, pos):
		character.move_input = Vector2.ZERO
		# Shoot only once the facing has settled on it. A refused shot (a barrel against a wall stepping back, a reload under
		# way) keeps the NPC peeking until it fires, rather than ducking without having fired; a click on an empty gun
		# ducks, where the cover phase reloads it.
		if fire_timer <= 0.0 and _faces(character, pos):
			var fired := shoot(character)
			if fired or character.ammo(character.gun_slot()) == 0:
				phase = "cover"
				cover_timer = cover_time
				dest_timer = 0.0  # Pick a cover spot immediately after shooting.
		return
	if dest_timer <= 0.0:
		dest = _choose_dest(character, "peek", node, pos, hold_ground)
		dest_timer = reposition_interval
	_loco.move_to(character, dest)


## Melee at the known position `pos`: close to punch range and swing on the fire cooldown (no cover cycle for fists).
## While holding ground it won't chase a contact out of the house — it only swings if one is already in reach.
func melee(character, pos: Vector2, hold_ground: bool) -> void:
	if character.global_position.distance_to(pos) > punch_range:
		if not hold_ground:
			_loco.move_to(character, pos)
		else:
			character.move_input = Vector2.ZERO
		return
	character.move_input = Vector2.ZERO
	if fire_timer <= 0.0:
		punch(character)


## Equip the character's gun and fire it, refreshing the combat engagement so an active fight stays
## committed; true when a round left the barrel. Nothing here is specific to a gun:
##   - at a run or mid-reload it holds fire and keeps the cooldown for when that stops;
##   - dry, a click is not a shot, so it neither commits the fight nor needs a hand free to reload — it
##     emits `dry` (the empty gun is in the snapshot now), at most once per cooldown;
##   - with the barrel against a wall or object (`weapon_blocked()`) it cannot fire, so it steps back until
##     it can, keeping the cooldown;
##   - an automatic gun's pull is a burst (`fire_burst` rounds, `continue_burst`), the rest at the gun's own rate.
func shoot(character) -> bool:
	if character.is_running() or character.is_reloading():
		return false
	var gun: int = character.gun_slot()
	if gun < 0:
		return false
	if character.ammo(gun) == 0:
		fire_timer = fire_cooldown
		dry.emit()
		return false
	character.select_slot(gun)
	if character.weapon_blocked():
		_back_off_timer = back_off_time
		return false
	if not character.shoot():
		return false
	_perception.note_engaged()
	fire_timer = fire_cooldown
	_burst_left = maxi(fire_burst - 1, 0) if character.is_automatic() else 0
	return true


## Equip the fists and throw a punch, refreshing the combat engagement.
func punch(character) -> void:
	_perception.note_engaged()
	fire_timer = fire_cooldown
	character.select_slot(FISTS_SLOT)
	character.melee()


## Keep the trigger down for the rest of an automatic gun's burst: one more round each time the gun's own fire
## rate allows, until the burst is spent or something stops it (a run, a reload, a swap, a wall, running dry).
func continue_burst(character) -> void:
	if _burst_left <= 0:
		return
	if not character.is_automatic() or character.is_running() or character.is_reloading() \
			or character.weapon_blocked() or character.ammo() <= 0:
		_burst_left = 0
		return
	if character.shoot():
		_burst_left -= 1


## Step back from whatever the gun's barrel is against (`shoot` set the timer): away from where it points,
## walking, until the barrel is clear or the time is up. Applied after the primitive has steered, so it wins.
func apply_back_off(character, delta: float) -> void:
	if _back_off_timer <= 0.0:
		return
	_back_off_timer -= delta
	character.move_input = -character.facing
	character.run_input = false


## Reflex: swap in a fresh magazine when the gun is empty and one is carried (`auto_reload`). It
## equips the gun first, since a reload works on the held item.
func reload_if_dry(character) -> void:
	if not reload_due(character):
		return
	character.select_slot(character.gun_slot())
	character.reload()


## Whether the reload reflex is due: `auto_reload` is on and the gun is empty with a spare magazine to put in it. (A reload runs
## only while standing, so a run is dropped for it.)
func reload_due(character) -> bool:
	var gun: int = character.gun_slot()
	return auto_reload and gun >= 0 and not character.is_reloading() and character.ammo(gun) == 0 and character.can_reload(gun)


## Whether the facing has settled on world point `pos` (within `AIM_TOLERANCE`).
func _faces(character, pos: Vector2) -> bool:
	return absf(character.facing.angle_to(pos - character.global_position)) <= AIM_TOLERANCE


## The committed destination for the current phase `kind`: the nearest spot with a clear shot ("peek") or the nearest
## shielded spot ("cover") around the known contact; falls back to closing on the contact (peek) or holding (cover)
## when no suitable spot exists this sample. While holding ground, spots are restricted to inside the house and the
## peek fallback holds position instead of advancing out.
func _choose_dest(character, kind: String, node, pos: Vector2, hold_ground: bool) -> Vector2:
	var spots: Dictionary = _perception.combat_spots(character, node, pos, ring_radius, ring_count)
	var fire: Array = spots["fire"]
	var cover: Array = spots["cover"]
	if hold_ground:
		fire = fire.filter(func(p): return _loco.inside_house(p))
		cover = cover.filter(func(p): return _loco.inside_house(p))
	if kind == "cover":
		return cover[0] if not cover.is_empty() else character.global_position
	if not fire.is_empty():
		return fire[0]
	return character.global_position if hold_ground else pos
