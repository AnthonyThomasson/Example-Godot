extends "res://scenes/ai/debug/debug_overlay.gd"

## AI domain, debug: the routes and exposure behind the options the NPC weighed. For each candidate
## fire / flank / advance / retreat point it draws the navigated route there (green = hidden from known
## hostiles, red = exposed) tagged with the route length band, whether the spot has a clear shot / cover,
## and a flank's status ("held by X", "route passes X", "in X's line of fire"). Known hostiles that have a
## last-seen facing get a wedge of the `watch_arc` they are looking along — the cone a spot "watched in
## the open" is rejected for. Reads the controller's `debug_zones()` and `known_contacts_for_display()`;
## the route is fetched from the navigation map (a pure read) and cached, since it only changes per decision.

## Whether to draw the routes overlay.
@export var show_routes: bool = false

const HIDDEN := Color(0.4, 0.9, 0.5)
const EXPOSED := Color(1.0, 0.35, 0.3)
const TAKEN := Color(1.0, 0.6, 0.2)
const WATCH := Color(1.0, 0.3, 0.3)
const CATEGORIES := [&"fire", &"flank", &"advance", &"retreat"]
## Seconds a computed route is reused before it is re-fetched (zones change per decision, ~1 s).
const CACHE_TTL := 0.5
## Reach (px) of a hostile's watch-cone wedge.
const WEDGE_RANGE := 170.0

var _cache: Dictionary = {}  ## point (Vector2) → PackedVector2Array route from the NPC.
var _cache_ms := 0
var _cache_from := Vector2.ZERO


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_routes


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	var map: RID = _character.get_world_2d().get_navigation_map()
	var me := _character.global_position
	var now := Time.get_ticks_msec()
	if now - _cache_ms > CACHE_TTL * 1000.0 or me.distance_to(_cache_from) > 24.0:
		_cache.clear()
		_cache_ms = now
		_cache_from = me
	var half_arc := deg_to_rad(float(_controller.get("watch_arc") if _controller.get("watch_arc") != null else 90.0)) * 0.5
	var contacts: Array = _controller.known_contacts_for_display() if _controller.has_method("known_contacts_for_display") else []
	for c in contacts:
		var facing: Vector2 = c.get("facing", Vector2.ZERO)
		if c["hostile"] and facing != Vector2.ZERO:
			_wedge(c["pos"], facing.angle(), half_arc)
	var zones: Array = _controller.debug_zones() if _controller.has_method("debug_zones") else []
	for z in zones:
		if not z["category"] in CATEGORIES:
			continue
		var tags: Dictionary = z.get("tags", {})
		if not tags.has("route_exposed"):
			continue
		var p: Vector2 = z["point"]
		var exposed: bool = tags["route_exposed"]
		var col := EXPOSED if exposed else HIDDEN
		if not _cache.has(p):
			_cache[p] = _route(map, me, p)
		var path: PackedVector2Array = _cache[p]
		for i in range(1, path.size()):
			_line(path[i - 1], path[i], Color(col, 0.55), 1.5)
		var notes: Array = ["%s route" % ("exposed" if exposed else "hidden")]
		notes.append("clear shot" if tags.get("clear_shot", false) else "line blocked")
		if tags.get("cover", "") != "":
			notes.append("cover: %s" % tags["cover"])
		var edge := col
		if tags.get("held", false):
			notes.append("held by %s" % tags.get("held_by", "ally"))
			edge = TAKEN
		if tags.get("crosses", false):
			notes.append("route passes %s" % tags.get("crosses_name", "a hostile"))
			edge = TAKEN
		if tags.get("ally_lane", "") != "":
			notes.append("in %s's line of fire" % tags["ally_lane"])
		_ring(p, 10.0, edge, 2.0)
		_label(p, " · ".join(notes), edge, Vector2(12, 14))


## The navigated route `from`→`to` (a straight segment while the map isn't ready).
func _route(map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return PackedVector2Array([from, to])
	var path := NavigationServer2D.map_get_path(map, from, to, true)
	return path if path.size() >= 2 else PackedVector2Array([from, to])


## A hostile's watch cone: two edge lines and an arc of `half` radians either side of `front`.
func _wedge(origin: Vector2, front: float, half: float) -> void:
	var col := Color(WATCH, 0.35)
	_line(origin, origin + Vector2.from_angle(front - half) * WEDGE_RANGE, col, 1.0)
	_line(origin, origin + Vector2.from_angle(front + half) * WEDGE_RANGE, col, 1.0)
	draw_arc(to_local(origin), WEDGE_RANGE, front - half, front + half, 16, col, 1.0)
