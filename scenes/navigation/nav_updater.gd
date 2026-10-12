extends Node

## Navigation domain: keeps the baked navigation map in step with furniture that has been shoved
## around. The holes `NavBuilder.build` carves are a snapshot of where the furniture stood at bake
## time; as pieces are bulldozed off their spots those holes go stale and paths route around empty
## floor. This node re-bakes the map on an interval (`NavBuilder.rebake`) so the holes follow the
## furniture's CURRENT positions and paths route around scattered objects. The living characters are
## holes in the STEERING region (`NavBuilder.rebake_steering`), so it follows them as they walk, appear
## and die. It only re-bakes when a piece or a character has actually moved past `move_threshold`, so an
## at-rest scene costs a cheap per-tick compare and no bake. The planning region only re-bakes for
## furniture. Bulldozing is still the behaviour BETWEEN re-bakes (and
## for non-solid decor, which is never carved). A script-only node Main builds once after the initial
## bake; imports nothing from other domains — it is handed plain Nodes.

## Whether the periodic re-bake runs at all. Off = the map stays the static bake-time snapshot.
@export var enabled: bool = true
## Seconds between move checks. Each check is cheap (furniture transforms only); a re-bake runs only
## on a check that finds movement, so this caps how often the (heavier) re-bake can happen.
@export var interval: float = 0.75
## How far (px) any furniture footprint point must shift since the last bake before the map is
## re-baked, so micro-jitter from settling physics bodies doesn't trigger constant re-bakes.
@export var move_threshold: float = 4.0

## The baked region to re-bake in place, the house whose furniture is tracked, and the rooms +
## agent radius the bake needs — all handed in by `setup`.
var _region: NavigationRegion2D
var _house: Node2D
var _rooms: Array = []
var _agent_radius: float = 14.0
## Optional furniture-hole debug overlay (nav_debug.gd), re-snapshotted after each re-bake so it
## keeps matching the live navmesh. Null when no overlay is wired.
var _nav_debug: Node = null
## The furniture footprints (NavBuilder.furniture_holes) and the character footprints
## (NavBuilder.character_holes) as of the last bake of each, compared each tick to detect movement.
var _baseline: Array = []
var _character_baseline: Array = []
## Whether the planning region's re-bake is running on the server's worker thread; a furniture move meanwhile waits for
## the first tick after the bake lands (the baseline is set from what that bake carved, so it is caught then).
var _baking := false


## Wire the updater to the baked map and start the interval. `region` is NavBuilder.build's result,
## `house`/`rooms`/`agent_radius` are what a re-bake needs, `nav_debug` is the optional overlay to
## refresh. Captures the current furniture layout as the baseline and starts a repeating Timer.
func setup(region: NavigationRegion2D, house: Node2D, rooms: Array, nav_debug: Node = null, agent_radius: float = 14.0) -> void:
	_region = region
	_house = house
	_rooms = rooms
	_agent_radius = agent_radius
	_nav_debug = nav_debug
	_baseline = NavBuilder.furniture_holes(house)
	_character_baseline = NavBuilder.character_holes(house.get_parent())
	var timer := Timer.new()
	timer.name = "RebakeTimer"
	timer.wait_time = max(interval, 0.05)
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)


## One interval tick: if furniture has moved since the last bake, re-carve the planning region's holes at the live
## positions on the server's worker thread (`NavBuilder.rebake_async`; a furniture move while one is in flight waits for
## the next tick) and the steering region's in place; if only a character has, re-carve the steering region. Refreshes
## the overlay after either. Skips the bake entirely when nothing has moved.
func _on_tick() -> void:
	if not enabled or _region == null or not is_instance_valid(_house):
		return
	var furniture := NavBuilder.furniture_holes(_house)
	var characters := NavBuilder.character_holes(_house.get_parent())
	var furniture_moved := _moved(_baseline, furniture)
	if not furniture_moved and not _moved(_character_baseline, characters):
		return
	if furniture_moved and not _baking:
		_baking = true
		NavBuilder.rebake_async(_region, _house, _rooms, _agent_radius, func() -> void:
			_baking = false
			_baseline = furniture
			_refresh_overlay())
	NavBuilder.rebake_steering(_region, _house, _rooms, _agent_radius)
	_character_baseline = characters
	_refresh_overlay()


## Re-snapshot the overlay so it matches the re-baked holes.
func _refresh_overlay() -> void:
	if _nav_debug != null and is_instance_valid(_nav_debug) and _nav_debug.has_method("setup") and is_instance_valid(_house):
		_nav_debug.setup(_house)


## Whether the footprints `b` differ from `a` enough to warrant a re-bake: a different piece
## count, or any footprint point shifted more than `move_threshold`. Both come from
## the same function, so points line up one-to-one when the piece count is unchanged.
func _moved(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return true
	for i in a.size():
		var pa: PackedVector2Array = a[i]
		var pb: PackedVector2Array = b[i]
		if pa.size() != pb.size():
			return true
		for j in pa.size():
			if pa[j].distance_to(pb[j]) > move_threshold:
				return true
	return false
