extends RefCounted

## AI BEHAVIOUR sub-domain — COMBAT. Everything a fight does with the character's hands: taking a shot, throwing a punch,
## keeping an automatic gun's trigger down for a burst, stepping back when a barrel is against a wall, the reload reflex,
## and the peek-and-cover cycle (step out, shoot, duck) with its committed firing / cover spot, and throwing a grenade
## (`docs/grenades.md` G17: take it in hand, aim at the spot, throw, put the gun back). Owns the fire cooldown, that cycle's
## phase and timers and the throw's stage. `Behavior` decides WHICH fight is on (it holds the engaged contact and the hold-ground
## flag) and passes the target in each call; this class never chooses a target and reads the world only through the
## perception (`has_line_to`, `combat_spots`, `note_engaged`) and the character's public contract. It knows no gun from
## another: the gun it fights with is `Character.gun_slot()`.

## The gun is empty: the shot was not taken (a click is not a shot), so the caller should re-decide.
signal dry

## Facing error (radians) within which a shot is taken — aim settles a frame after it is set.
const AIM_TOLERANCE := 0.15
## Seconds a throw may take to start (the grenade in hand, the facing settled, the hand free) before it is given up, and to
## leave the hand once started.
const THROW_START_CAP := 2.0
const THROW_RELEASE_CAP := 1.5
## How far (px) inside a grenade's throw range the thrower stands when it lets go, so that one a step past it closes in and the grenade comes
## down on the spot and not short at the cap.
const THROW_RANGE_SLACK := 15.0

# --- Config fields `Behavior.apply_config()` copies in. ---
var shoot_range: float = 500.0  ## Copy of GoalController.shoot_range.
var punch_range: float = 48.0  ## Copy of GoalController.punch_range.
var ring_radius: float = 80.0  ## Radius of the ring of candidate firing / cover spots around the target.
var ring_count: int = 12       ## Candidate spots on that ring.
var cover_time: float = 1.2  ## Copy of GoalController.cover_time.
var fire_cooldown: float = 0.5  ## Copy of GoalController.fire_cooldown.
## Rounds an automatic gun fires per trigger pull (paced by the gun's own fire rate); a single-shot gun fires one.
var fire_burst: int = 3
## Seconds spent stepping back when the gun's barrel is against a wall or object and cannot fire.
var back_off_time: float = 0.45
var reposition_interval: float = 0.5  ## Copy of GoalController.reposition_interval.
var auto_reload: bool = true   ## An empty gun with a spare magazine is reloaded on its own while holding or ducked in cover.

var phase := "peek"            ## Peek-and-cover phase: "peek" (seek a shot) or "cover" (duck).
var cover_timer := 0.0         ## Seconds left ducking behind cover before peeking again.
var fire_timer := 0.0          ## Seconds left before the next shot/punch may be thrown.
var dest := Vector2.ZERO       ## Committed fire/cover position the NPC is steering toward.
var dest_timer := 0.0          ## Seconds left before a new combat position may be chosen.
## The throw in hand (`begin_throw`): "" none, "aim" taking the grenade and turning to the spot, "windup" the hand drawn back,
## "away" it has left the hand (or never will).
var throw_stage := ""

var _throw_slot := -1          ## The inventory slot of the grenade being thrown.
var _throw_spot := Vector2.ZERO  ## Where it is thrown to.
var _throw_range := 0.0        ## How far (px) that grenade first comes down.
var _throw_before := 0         ## How many of that grenade were carried when the throw started.
var _throw_clock := 0.0        ## Seconds in the current stage of the throw.
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


## Whether `target` (a known-contact dict) can be shot at now: a loaded gun not mid-reload, and `has_line_of_fire`. The cooldown, the
## facing and a run are not counted: they pass in a moment, this says the NPC is in a position to fire.
func can_fire_at(character, target: Dictionary) -> bool:
	var gun: int = character.gun_slot()
	if gun < 0 or character.ammo(gun) == 0 or character.is_reloading() or target.is_empty():
		return false
	return has_line_of_fire(character, target)


## Whether `target` (a known-contact dict) stands within range on a clear line to where it is known to be: a shot at it is possible
## from here whatever the gun's state (the entry reads it as "engaged from outside", docs/tactical-entry.md E14).
func has_line_of_fire(character, target: Dictionary) -> bool:
	if target.is_empty():
		return false
	var pos: Vector2 = target["pos"]
	return character.global_position.distance_to(pos) <= shoot_range and _perception.has_line_to(target["node"], pos)


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
			and _perception.has_line_to(node, pos) and fire_timer <= 0.0 and _faces(character, pos):
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
		_loco.move_to(dest)
		reload_if_dry(character)
		if cover_timer <= 0.0:
			phase = "peek"
			dest_timer = 0.0  # Re-pick a firing spot immediately on peeking out.
		return
	# PEEK: take the shot if a clear line to the known position is in range, else reposition to get one.
	if dist <= shoot_range and _perception.has_line_to(node, pos):
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
	_loco.move_to(dest)


## Start a throw of the grenade in `slot` (it comes down `max_range` px away at most) at world point `spot` (the GRENADE tactic's `throw`
## primitive).
func begin_throw(slot: int, spot: Vector2, max_range: float) -> void:
	throw_stage = "aim"
	_throw_slot = slot
	_throw_spot = spot
	_throw_range = max_range
	_throw_clock = 0.0


## How far (px) from its spot a thrower stands to let go a grenade that first comes down `max_range` px away at most.
func throw_reach(max_range: float) -> float:
	return max_range - THROW_RANGE_SLACK


## Forget a throw (a new order replaced it).
func end_throw() -> void:
	throw_stage = ""


## Carry the throw out one tick, standing still: take the grenade in hand, aim at the spot and, once the facing has settled,
## click the trigger (`Character.shoot()`: the wind-up starts, the grenade leaves the hand `windup` seconds later). A thrower that
## stands past `THROW_RANGE_SLACK` short of the grenade's range (it moved on since the spot was offered) walks the last few px toward the
## spot first, within the same `THROW_START_CAP`. Returns `&"failed"` when it never could (none left, the hand busy, the wind-up cut
## short), else `&""`.
func throw_step(character, delta: float) -> StringName:
	_throw_clock += delta
	character.move_input = Vector2.ZERO
	match throw_stage:
		"aim":
			if character.item_count(_throw_slot) <= 0 or _throw_clock > THROW_START_CAP:
				throw_stage = "away"
				return &"failed"
			character.select_slot(_throw_slot)
			character.aim_point = _throw_spot
			if character.global_position.distance_to(_throw_spot) > throw_reach(_throw_range):
				_loco.move_to(_throw_spot)
				return &""
			if character.current_slot() == _throw_slot and _faces(character, _throw_spot):
				_throw_before = character.item_count(_throw_slot)
				if character.shoot():
					throw_stage = "windup"
					_throw_clock = 0.0
		"windup":
			character.aim_point = _throw_spot
			if _throw_clock > THROW_RELEASE_CAP:
				throw_stage = "away"
				return &"failed"  # The wind-up was cut short (it died, or put the grenade away).
	return &""


## Whether the grenade being thrown has left the hand since the last call (true once): the end of the wind-up. The gun is taken
## back in hand then (a last grenade empties its slot by itself).
func throw_released(character) -> bool:
	if throw_stage != "windup" or character.item_count(_throw_slot) >= _throw_before:
		return false
	throw_stage = "away"
	character.select_slot(character.gun_slot())
	return true


## Melee at the known position `pos`: close to punch range and strike on the fire cooldown (no cover cycle for fists).
## While holding ground it won't chase a contact out of the house — it only swings if one is already in reach.
func melee(character, pos: Vector2, hold_ground: bool) -> void:
	if character.global_position.distance_to(pos) > punch_range:
		if not hold_ground:
			_loco.move_to(pos)
		else:
			character.move_input = Vector2.ZERO
		return
	character.move_input = Vector2.ZERO
	if fire_timer <= 0.0:
		strike(character)


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


## Land a blow, refreshing the combat engagement: a standing NPC with a gun in hand keeps it and kicks; otherwise (a
## crouched NPC cannot kick) it equips the fists and punches.
func strike(character) -> void:
	if character.ammo_capacity() >= 0 and character.posture() == &"stand":
		kick(character)
	else:
		punch(character)


## Kick with a leg, keeping whatever is held.
func kick(character) -> void:
	_perception.note_engaged()
	fire_timer = fire_cooldown
	character.leg_kick()


## Equip the fists and throw a punch, refreshing the combat engagement.
func punch(character) -> void:
	_perception.note_engaged()
	fire_timer = fire_cooldown
	character.select_slot(ItemRegistry.FISTS_SLOT)
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
	_loco.keep_off()  # Never back into a body it knows of.
	character.run_input = false


## Reflex: swap in a fresh magazine when the gun is empty and one is carried (`auto_reload`). It
## equips the gun first, since a reload works on the held item.
func reload_if_dry(character) -> void:
	if not reload_due(character):
		return
	character.select_slot(character.gun_slot())
	character.reload()


## A tactical reload (docs/tactical-entry.md E11): swap a part-spent magazine for a full one in a lull, the way a stack tops its
## gun off before it crosses. Starts the reload when the held gun is short of full with a magazine to add; true while it is
## under way or wanted, so a caller that must not move on armed waits for false. The caller stands still (a run cancels it).
func top_off(character) -> bool:
	var gun: int = character.gun_slot()
	if gun < 0:
		return false
	if character.is_reloading():
		return true
	if character.ammo(gun) >= character.ammo_capacity(gun) or not character.can_reload(gun):
		return false
	character.select_slot(gun)
	character.reload()
	return true


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
	var spots: Dictionary = _perception.combat_spots(node, pos, ring_radius, ring_count)
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
