extends RefCounted

## AI PERCEPTION sub-domain — SNAPSHOT VOCABULARY. The shared words and tuning of the decision snapshot: the compass and
## flank-side names, every tunable the perception copies in before a decision (ranges, bands, thresholds, caps), the house
## rooms of the decision being built, and the helpers that turn a distance, an age, a route, a bearing or a wound into the
## band Von reads. `agent_snapshot.gd` owns one (`vocab`); the sections and option modules read it, so no tunable is set twice.
## Everything is worded for a classifier (see `agent_snapshot.gd`): bands not numbers, no negations.

## Compass names for an 8-wind direction, indexed clockwise from east (screen +y is south).
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
## How each flank side of a target is named to Von.
const SIDE_WORDS := { "left": "their left side", "right": "their right side", "rear": "behind them", "front": "their front" }

# --- Config fields the perception copies from its own config before each decision. ---
var shoot_range: float = 500.0
var punch_range: float = 48.0
var recency_bands: Vector2 = Vector2(2.0, 8.0)
var route_buckets: Vector2 = Vector2(400.0, 900.0)
var aim_cone: float = 20.0
var still_speed: float = 20.0
var flank_ally_radius: float = 500.0
var investigate_distance: float = 300.0
var extrapolate_cap: float = 3.0
var max_options_per_level: int = 4
var hurt_threshold: float = 15.0
var critical_threshold: float = 35.0
var low_ammo_fraction: float = 0.34
var max_contacts_in_state: int = 4
var search_memory_ttl: float = 60.0

var rooms: Array = []  ## The house rooms for the decision being built (set at the top of `AgentSnapshot.build()`).


## A room type as Von reads it ("kitchen_living" → "kitchen living").
func room_name(kind) -> String:
	return str(kind).replace("_", " ")

## A distance as a combat band, from the NPC's own reach.
func dist_band(d: float) -> String:
	if d <= punch_range * 1.5:
		return "point-blank"
	if d <= shoot_range * 0.5:
		return "close, in pistol range"
	if d <= shoot_range:
		return "in pistol range"
	return "too far to shoot"

## How long ago, as a band.
func recency(age: float) -> String:
	if age <= recency_bands.x:
		return "just now"
	if age <= recency_bands.y:
		return "recently"
	return "a while ago"

## A route length as a band.
func route_band(length: float) -> String:
	if length <= route_buckets.x:
		return "short"
	if length <= route_buckets.y:
		return "medium"
	return "long"

## A route as Von reads it: "short hidden" / "long exposed".
func route_text(length: float, exposed: bool) -> String:
	return "%s %s" % [route_band(length), "exposed" if exposed else "hidden"]

## How a contact is moving, relative to the NPC ("moving west, toward you" / "standing still").
func move_text(c: Dictionary, self_pos: Vector2) -> String:
	var vel: Vector2 = c.get("vel", Vector2.ZERO)
	var prefix := "" if c.get("visible", false) else "was "
	if vel.length() < still_speed:
		return prefix + "standing still"
	var rel := ""
	var a := absf(vel.angle_to(self_pos - (c["pos"] as Vector2)))
	if a < PI * 0.25:
		rel = ", toward you"
	elif a > PI * 0.75:
		rel = ", away from you"
	return "%smoving %s%s" % [prefix, compass(vel), rel]

## Whether contact `c` (seen this tick) is coming toward the NPC, for an ambush.
func coming_text(c: Dictionary, self_pos: Vector2) -> String:
	var vel: Vector2 = c.get("vel", Vector2.ZERO)
	if vel.length() < still_speed:
		return "they are standing still"
	if absf(vel.angle_to(self_pos - (c["pos"] as Vector2))) < PI * 0.25:
		return "they are coming this way"
	return "they are moving elsewhere"

## Who a VISIBLE contact is aiming at — the NPC, or another known character within `aim_cone` of its
## facing — or that it faces away from the NPC. Empty when unknown or unremarkable.
func aim_text(c: Dictionary, self_pos: Vector2, others: Array) -> String:
	var facing: Vector2 = c.get("facing", Vector2.ZERO)
	if not c.get("visible", false) or facing == Vector2.ZERO:
		return ""
	var cone := deg_to_rad(aim_cone)
	var to_me: Vector2 = self_pos - (c["pos"] as Vector2)
	if absf(facing.angle_to(to_me)) <= cone:
		return "aiming at you"
	for o in others:
		if o["id"] != c["id"] and absf(facing.angle_to((o["pos"] as Vector2) - (c["pos"] as Vector2))) <= cone:
			return "aiming at %s" % o["name"]
	if absf(facing.angle_to(to_me)) >= PI * 0.66:
		return "facing away from you"
	return ""

## Where a contact is: "in the kitchen, inside the house" / "outside the house".
func where(c: Dictionary) -> String:
	if not c.get("inside", false):
		return "outside the house"
	var room := room_name(c.get("room_type", ""))
	return ("in the %s" % room) if room != "" else "inside the house"

## Where a point is, in the words of `where`: "in the kitchen" inside a room, "outside the house" otherwise.
func place(p: Vector2) -> String:
	var room := room_at(p, rooms)
	return ("in the %s" % room_name(room["type"])) if not room.is_empty() else "outside the house"

## " (in the kitchen)" for a point inside a room, " (outside)" otherwise.
func room_suffix(p: Vector2) -> String:
	var room := room_at(p, rooms)
	return (" (in the %s)" % room_name(room["type"])) if not room.is_empty() else " (outside)"

## Accumulated damage as a band of how hurt a character is.
func health_band(dmg: float) -> String:
	if dmg >= critical_threshold:
		return "badly wounded"
	if dmg >= hurt_threshold:
		return "hurt"
	return "unhurt"

## A seen character's visible wound band ("looks hurt"), or "" when unharmed.
func wound_band(dmg: float) -> String:
	if dmg >= critical_threshold:
		return "looks badly wounded"
	if dmg >= hurt_threshold:
		return "looks hurt"
	return ""

## The 8-wind compass name for a direction vector (screen space, +y down = south).
func compass(v: Vector2) -> String:
	var idx := int(round(atan2(v.y, v.x) / (TAU / 8.0))) % 8
	return COMPASS[idx + 8 if idx < 0 else idx]

## How the NPC's own posture is worded in its situation: " You are crouching.", and
## nothing for a standing body, so the usual text is unchanged.
func own_posture_text(posture: StringName) -> String:
	match posture:
		&"crouch":
			return " You are crouching."
	return ""

## How a contact seen low is worded: "crouched low", and nothing for one standing.
func contact_posture_text(posture: StringName) -> String:
	match posture:
		&"crouch":
			return "crouched low"
	return ""

## What the NPC calls its gun in the text Von reads: its name in lower case ("pistol", "assault rifle"; an
## acronym like "SMG" stays as written), or "gun" with none.
func gun_noun(character, gun: int) -> String:
	if gun < 0:
		return "gun"
	var name: String = character.item_name(gun)
	return name if name == name.to_upper() else name.to_lower()

## A flank side's status: "route passes X" when getting there walks past a known hostile, "taken by X"
## when an ally holds it, else "free".
func side_status(s: Dictionary) -> String:
	if s["crosses"] != "":
		return "route passes %s" % s["crosses"]
	return ("taken by %s" % s["held_by"]) if s["held_by"] != "" else "free"

## Whether a world point lies inside the house (within any room of the decision being built).
func is_inside(p: Vector2) -> bool:
	return not room_at(p, rooms).is_empty()

## The centre of the bounding box enclosing all rooms — "the house" for an NPC that knows no room.
func house_centre() -> Vector2:
	var bounds := (rooms[0]["rect"] as Rect2)
	for room in rooms:
		bounds = bounds.merge(room["rect"])
	return bounds.get_center()


## The room dict whose rect contains `p`, or empty when `p` is outside every room. Static: the
## perception reads rooms the same way.
static func room_at(p: Vector2, list: Array) -> Dictionary:
	for room in list:
		if (room["rect"] as Rect2).has_point(p):
			return room
	return {}
