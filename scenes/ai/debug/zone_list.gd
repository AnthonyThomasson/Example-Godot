extends RefCounted

## AI DEBUG sub-domain — ZONE LIST. Flattens the option groups of a decision snapshot into the tactical navigation ZONES the
## tactics overlay draws: every candidate position the perception weighed, as a world point with its `label` + `desc` and the
## kind of zone it is. A pure transform of data the orchestrator retains from the last snapshot; it touches no node.

## Non-room go-to options the room/search groups carry: the NPC's starting post, the front entrance,
## and approaching the house. They aren't rooms (and an outside NPC's often sit well outside one), so
## the overlay tags them `waypoint` instead of `room`/`search` rather than letting them read as rooms.
const WAYPOINT_IDS := ["post", "entrance", "approach"]


## The tactical navigation ZONES in a snapshot's `options` — every candidate position the NPC's perception laid out for its
## last decision, flattened to world points (each with its `label`, `desc` and `tags`) tagged by the kind of zone each is
## (`fire` / `flank` / `advance` / `retreat` / `lead` / `search` / `room` / `interaction`, plus `waypoint` for the non-room
## go-to points — your starting post, the front entrance, approaching the house — which the room/search groups carry but
## which aren't rooms and often sit outside one). Empty until the first decision. Options with no world location (a
## point-blank punch, the hostile picks) are skipped.
static func from_options(options: Dictionary) -> Array:
	var out: Array = []
	if options.is_empty():
		return out
	for groups in options.get("per_target", {}).values():
		_collect(out, groups.get("fire_positions", {}), &"fire")
		_collect(out, groups.get("flank_sides", {}), &"flank")
		_collect(out, groups.get("advance_positions", {}), &"advance")
	_collect(out, options.get("retreat_positions", {}), &"retreat")
	_collect(out, options.get("leads", {}), &"lead")
	_collect(out, options.get("shooter", {}), &"lead")
	_collect(out, options.get("search_rooms", {}), &"search")
	_collect(out, options.get("explore", {}), &"search")
	_collect(out, options.get("rooms", {}), &"room")
	_collect(out, options.get("interactions", {}), &"interaction")
	return out


## Append each option in `group` that has a world location to `out`, tagged `category` — except the
## non-room waypoints (WAYPOINT_IDS), re-tagged `waypoint`. Each entry also carries the option's `label`
## and `desc` (the human text Von reads, which spells out the deciding facts: cover, route, range) so an
## inspector can expose a clicked point's details. The location is the option's `point` param, or an
## interactable's current position. Options with neither (a punch, a hostile bind) are skipped.
static func _collect(out: Array, group: Dictionary, category: StringName) -> void:
	for opt in group.get("options", []):
		var params: Dictionary = opt.get("params", {})
		var cat: StringName = &"waypoint" if str(opt.get("id", "")) in WAYPOINT_IDS else category
		var point = null
		if params.has("point"):
			point = params["point"]
		elif params.get("object") is Node2D and is_instance_valid(params["object"]):
			point = (params["object"] as Node2D).global_position
		if point != null:
			out.append({ "point": point, "category": cat,
				"label": opt.get("label", ""), "desc": opt.get("desc", ""), "tags": opt.get("tags", {}) })
