extends RefCounted

## Shared helpers for the tests of NPCs walking into each other (issue #53; not a test itself). It watches a set of
## characters every physics frame and records each time one WALKS INTO another, read only off the character's public
## state: its `global_position`, its `move_input` (what its controller is steering it to do) and `is_dead`, plus the NPC
## brain's public `debug_entry()` / `current_act()` to say what each was doing.
##
## "Walks into", measurably: the walker is steering (`move_input` set) toward the other body, within `INTO_CONE` of the
## line between their centres, while the two bodies touch (centres closer than two body radii plus `CONTACT_TOL`). Two
## 14 px circles touch at 28 px and the colliders never let them overlap much further, so a few px of tolerance catches
## the frames they press together, while a walk that passes alongside (heading off the line between them) does not count.
## The frames of one ordered pair make one bump, and a contact that resumes within `MERGE_GAP` s (a walker that presses,
## is pushed back a pixel, and presses again) is the same bump.
##
## Each bump says whether the body walked into was AT REST (not steering: `move_input` zero; the kind of body the
## steering map carves out) or MOVING (steering a walk of its own) when the contact began, and how far that body was
## SHOVED: its displacement over the bump's frames while it was not steering, which only the walker's push can cause.

## Body radius (px) of every character (`Character.radius`).
const RADIUS := 14.0
## How far past touching (px) still counts as touching.
const CONTACT_TOL := 3.0
## The walker's heading must be within this angle (cos) of the line to the other body's centre.
const INTO_CONE := 0.5
## A `move_input` shorter than this is not steering.
const STEERING := 0.1
## A contact of the same pair that resumes within this many s continues the last bump.
const MERGE_GAP := 0.5
## How many bumps `describe` spells out.
const DESCRIBE_MAX := 12
## Standing pressed against a body: still (slower than `PRESSED_SPEED` px/s) with its centre closer than `PRESSED_GAP` px to
## the other's, which neither a walk round it (passing, moving) nor a walk held short of it (`STOP_GAP` 56 px off) does; a test
## allows a stand of at most `PRESSED_MAX` s (a step that `keep_off` cut for a frame or two).
const PRESSED_GAP := 45.0
const PRESSED_SPEED := 10.0
const PRESSED_MAX := 0.5


## Watch `who` (actor ids, or the character nodes themselves, named by their node name) for up to `duration` s, or
## until `stop` returns true. Returns `{ bumps: Array, closest: float }` (`closest`: the nearest any two came, px). A bump
## is `{ walker, other, at_rest, start, end, shove, where, walker_doing, other_doing }`: names, whether the other was at
## rest, sim times, px shoved, the walker's position when it began, and what each was doing then.
static func watch(t: TestContext, who: Array, duration: float, stop := Callable()) -> Dictionary:
	var bumps: Array = []
	var last_bump := {}   # "walker>other" -> that pair's latest bump
	var last_pos := {}
	var nearest := INF
	var end := t.time + duration
	while t.time < end:
		var live := {}
		for w in who:
			var a: Node = w if w is Node else t.actor(w)
			if a != null and is_instance_valid(a) and not a.is_dead:
				live[StringName(a.name) if w is Node else w] = a
		var closest := INF
		for w in live:
			for o in live:
				if w == o:
					continue
				var walker: Node2D = live[w]
				var other: Node2D = live[o]
				var gap: Vector2 = other.global_position - walker.global_position
				closest = minf(closest, gap.length())
				if gap.length() > RADIUS * 2.0 + CONTACT_TOL or gap.length() < 0.001:
					continue
				var steer: Vector2 = walker.move_input
				if steer.length() < STEERING or steer.normalized().dot(gap.normalized()) < INTO_CONE:
					continue
				var key := "%s>%s" % [w, o]
				var other_still := (other.move_input as Vector2).length() < STEERING
				var bump: Dictionary = last_bump.get(key, {})
				if bump.is_empty() or t.time - float(bump["end"]) > MERGE_GAP:
					bump = { "walker": w, "other": o, "at_rest": other_still, "start": t.time, "end": t.time, "shove": 0.0,
							"where": walker.global_position, "walker_doing": doing(walker), "other_doing": doing(other) }
					bumps.append(bump)
					last_bump[key] = bump
				bump["end"] = t.time
				if other_still and last_pos.has(o):
					bump["shove"] = float(bump["shove"]) + other.global_position.distance_to(last_pos[o])
		for id in live:
			last_pos[id] = live[id].global_position
		if closest < INF:
			t.trace("closest_pair", closest)
			nearest = minf(nearest, closest)
		if stop.is_valid() and stop.call():
			break
		await t.frames(1)
	return { "bumps": bumps, "closest": nearest }


## A clock of `walker` standing pressed against `other` (see `PRESSED_GAP`): call the returned Callable once a physics frame;
## each call samples that frame and returns the longest stand so far (s).
static func pressed_watch(walker: Node2D, other: Node2D) -> Callable:
	var clock := [0.0, 0.0]  # the stand under way, the longest (an Array: a lambda captures floats by value)
	return func() -> float:
		var still: bool = walker.get_real_velocity().length() < PRESSED_SPEED
		if still and walker.global_position.distance_to(other.global_position) < PRESSED_GAP:
			clock[0] += 1.0 / Engine.physics_ticks_per_second
			clock[1] = maxf(clock[1], clock[0])
		else:
			clock[0] = 0.0
		return clock[1]


## What a character's NPC brain is doing, in a few words: its entry phase when it is entering, else its decision path.
static func doing(character: Node) -> String:
	for child in character.get_children():
		if child.has_method("debug_entry"):
			var phase := String(child.debug_entry().get("phase", ""))
			return "entry %s" % phase if phase != "" else String(child.current_act())
	return "puppet"


## The bumps into a body at rest (`at_rest` true) or into a moving one (false).
static func of_kind(bumps: Array, at_rest: bool) -> Array:
	return bumps.filter(func(b): return bool(b["at_rest"]) == at_rest)


## The bumps for a failure message, the first `DESCRIBE_MAX` spelled out.
static func describe(bumps: Array) -> String:
	var lines: Array = []
	for b in bumps.slice(0, DESCRIBE_MAX):
		lines.append("%s (%s) into %s (%s, %s) at %.2f-%.2f s near (%.0f, %.0f), shoved %.1f px" % [b["walker"], b["walker_doing"],
				b["other"], "at rest" if b["at_rest"] else "moving", b["other_doing"], b["start"], b["end"], b["where"].x,
				b["where"].y, b["shove"]])
	if bumps.size() > DESCRIBE_MAX:
		lines.append("and %d more" % (bumps.size() - DESCRIBE_MAX))
	return "; ".join(lines) if not lines.is_empty() else "none"


## How many bumps of each kind, by what the walker was doing: `{ "at rest/entry approach": n, "moving/entry clear": n, ... }`.
static func tally(bumps: Array) -> Dictionary:
	var out := {}
	for b in bumps:
		var key := "%s/%s" % ["at rest" if b["at_rest"] else "moving", String(b["walker_doing"]).get_slice("/", 0) if not String(b["walker_doing"]).begins_with("entry") else b["walker_doing"]]
		out[key] = int(out.get(key, 0)) + 1
	return out


## Totals for the bumps of one kind: `{ count, seconds, shove }` (how many, how long in contact all told, how far the
## bodies were shoved all told, px).
static func totals(bumps: Array) -> Dictionary:
	var out := { "count": bumps.size(), "seconds": 0.0, "shove": 0.0 }
	for b in bumps:
		out["seconds"] = snappedf(float(out["seconds"]) + float(b["end"]) - float(b["start"]), 0.01)
		out["shove"] = snappedf(float(out["shove"]) + float(b["shove"]), 0.1)
	return out


## The bumps into a MOVING body as collisions: two walkers that press into each other head-on make a bump each way (A into
## B and B into A, both steering), which is one collision, and so is a bump of the same pair, either way round, that
## overlaps an earlier one or resumes within `MERGE_GAP` s. Each `{ pair: "A+B", start, end, bumps: Array }`, by start.
static func collisions(bumps: Array) -> Array:
	var moving := of_kind(bumps, false)
	moving.sort_custom(func(a, b): return float(a["start"]) < float(b["start"]))
	var out: Array = []
	var latest := {}   # pair -> its latest collision
	for b in moving:
		var names := [String(b["walker"]), String(b["other"])]
		names.sort()
		var pair := "+".join(names)
		var c: Dictionary = latest.get(pair, {})
		if c.is_empty() or float(b["start"]) - float(c["end"]) > MERGE_GAP:
			c = { "pair": pair, "start": b["start"], "end": b["end"], "bumps": [] }
			out.append(c)
			latest[pair] = c
		c["end"] = maxf(float(c["end"]), float(b["end"]))
		(c["bumps"] as Array).append(b)
	return out


## Collisions for a failure message, the first `DESCRIBE_MAX` spelled out with what each walker was doing.
static func describe_collisions(found: Array) -> String:
	var lines: Array = []
	for c in found.slice(0, DESCRIBE_MAX):
		var first: Dictionary = c["bumps"][0]
		lines.append("%s at %.2f-%.2f s near (%.0f, %.0f) (%s: %s, %s: %s)" % [c["pair"], c["start"], c["end"], first["where"].x,
				first["where"].y, first["walker"], first["walker_doing"], first["other"], first["other_doing"]])
	if found.size() > DESCRIBE_MAX:
		lines.append("and %d more" % (found.size() - DESCRIBE_MAX))
	return "; ".join(lines) if not lines.is_empty() else "none"
