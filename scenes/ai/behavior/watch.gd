extends RefCounted

## AI BEHAVIOUR sub-domain — WATCH. Where an NPC looks when no primitive has a reason to look anywhere in particular, and
## which threat takes its eyes and its gun whatever it is doing (docs/gaze-and-fire.md). The rule is one sentence: an NPC is
## always either looking at (and, when it can, shooting) a threat, or watching its doors; never a wall, and never with its
## back to a known threat. Owns the pick of the threat and the rotating look at a room's doorways, and nothing else: `Behavior`
## runs the stage each tick and does the aiming, `Combat` the shooting, `Locomotion` the walk it looks down.

# --- Config fields `Behavior.apply_config()` copies in. ---
## How far (px) down its path a walking NPC looks.
var look_ahead: float = 150.0
## Seconds a resting NPC looks at one doorway before turning to the next.
var door_dwell: float = 2.5
## Seconds a hostile that is no longer seen still holds the NPC's eyes (while it has a clear line to where it was last seen).
var lost_gaze: float = 2.0
## Gaze turn speed (rad/s) while it looks from one doorway to the next.
var look_rate: float = 2.5

## Doorways nearer than this (px) are not worth watching: the NPC stands in them.
const DOOR_MIN_DISTANCE := 60.0
## Spacing (px) of the points along the path tried for a clear line when a walking NPC picks where to look.
const PATH_STEP := 30.0

var _loco: Node                   ## The Locomotion child (which room the NPC stands in).
var _perception: Node             ## The perception sub-domain (the room's doorways, the clear-line test).
var _room := ""                   ## The room whose doorways are being watched.
var _doors: Array = []            ## That room's doorway points worth watching, in a turn around the room.
var _door := 0                    ## Which of them is being looked at.
var _dwell := 0.0                 ## Seconds left looking at it.


## Capture the locomotion and the perception. Called once by `Behavior.setup()`.
func setup(loco: Node, perception: Node) -> void:
	_loco = loco
	_perception = perception


## The contact that takes the NPC's eyes from `hostiles` (the known hostile contacts, hostile first and nearest first): the
## one it is fighting if it can see it, else the nearest it can see, else the one it is fighting as last seen, else the nearest
## it saw within `lost_gaze` seconds. {} with none. Seen or not, a contact stays a threat only as far as `Behavior` finds a line
## to it: a hostile remembered behind a wall is not worth staring at the wall for.
func threat(hostiles: Array, engaged_id: int) -> Dictionary:
	var seen := {}
	var engaged := {}
	var recent := {}
	for c in hostiles:
		if c["visible"]:
			if c["id"] == engaged_id:
				return c
			if seen.is_empty():
				seen = c
		elif c["id"] == engaged_id:
			engaged = c
		elif recent.is_empty() and float(c["age"]) <= lost_gaze:
			recent = c
	if not seen.is_empty():
		return seen
	return engaged if not engaged.is_empty() else recent


## Where a walking NPC looks: the farthest point, up to `look_ahead` px down the walk the nav agent was just given, that it has
## a clear line to. Along a straight walk that is well ahead; at a doorway it is through the door as soon as it can see
## through, and the wall beside it never (the immediate waypoint hugs the jamb, and facing it looks at the jamb).
## Vector2.INF with no walk or no clear point (the caller then looks where it steers).
func travel_point(character) -> Vector2:
	var walk: Dictionary = _loco.path_ahead()
	if walk.is_empty():
		return Vector2.INF
	var path: PackedVector2Array = walk["path"]
	var from: Vector2 = character.global_position
	var best := Vector2.INF
	var prev := from
	var walked := 0.0
	for i in range(int(walk["index"]), path.size()):
		var seg := prev.distance_to(path[i])
		var d := 0.0
		while d < seg:
			d = minf(d + PATH_STEP, seg)
			if walked + d > look_ahead:
				return best
			var p := prev.lerp(path[i], d / seg)
			if not _perception.has_line_to(character, null, p):
				return best
			best = p
		walked += seg
		prev = path[i]
	return best


## Resting with nothing to look at: turn to each doorway of the room in turn, `door_dwell` s apiece, easing between them. Does
## nothing outdoors or in a room with no doorway in line (the gaze it has stays). A fresh NPC that was never given an aim looks
## where its body points, not at the world's origin.
func idle_gaze(character, delta: float) -> void:
	var here: Vector2 = character.global_position
	if character.aim_point == Vector2.ZERO:
		character.aim_point = here + (character.facing as Vector2) * 100.0
	var room: String = _loco.room_key_at(here)
	if room != _room or _dwell <= 0.0:
		_pick_door(character, room)
	_dwell -= delta
	if _doors.is_empty():
		return
	var desired: float = ((_doors[_door] as Vector2) - here).angle()
	var angle := rotate_toward((character.facing as Vector2).angle(), desired, look_rate * delta)
	character.aim_point = here + Vector2.from_angle(angle) * 100.0


## Forget the doorway being watched (a new order is taken): the next resting NPC starts again from the nearest.
func reset() -> void:
	_room = ""
	_doors = []
	_dwell = 0.0


## Choose the next doorway to watch. On entering a room (or the first time) the nearest in line; afterwards the next one
## round the NPC, so it sweeps all of them.
func _pick_door(character, room: String) -> void:
	var here: Vector2 = character.global_position
	var fresh := room != _room or _doors.is_empty()
	if fresh:
		_room = room
		_doors = _doors_of(character, room)
		_door = _nearest(_doors, here)
	elif not _doors.is_empty():
		_door = (_door + 1) % _doors.size()
	_dwell = door_dwell


## The room's doorways worth watching from where the NPC stands, ordered by the angle they lie at round it: those with a clear
## line to them and not right under its feet.
func _doors_of(character, room: String) -> Array:
	var here: Vector2 = character.global_position
	var points: Array = []
	if room == "":
		return points
	for d in _perception.room_doorways(room):
		var p: Vector2 = d["pos"]
		if here.distance_to(p) >= DOOR_MIN_DISTANCE and _perception.has_line_to(character, null, p):
			points.append(p)
	points.sort_custom(func(a, b): return (a - here).angle() < (b - here).angle())
	return points


## Index in `points` of the one nearest `from` (0 with none).
func _nearest(points: Array, from: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d: float = from.distance_squared_to(points[i])
		if d < best_d:
			best_d = d
			best = i
	return best
