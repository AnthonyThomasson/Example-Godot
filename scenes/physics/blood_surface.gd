class_name BloodSurface

## What the ground feels like to flowing blood. Surfaces (a room's floor) register a world rect plus a
## `groove` Callable `(world_pos, half_width) -> float` (1 = on a groove such as grout or a plank seam,
## 0 = smooth); `resistance` turns that into a flow-cost multiplier for BloodFlow, so blood runs fast
## along grooves and slowly across smooth surface. A `porous` surface (carpet) soaks blood up instead.
## Physics imports nothing: the surface's owner supplies the Callable. Point outside every surface = 1.

## Registered surfaces: id -> { rect: Rect2, groove: Callable, porous: bool }.
static var _surfaces: Dictionary = {}
static var _next_id := 1


## Register a surface covering world `rect`. Returns the id to pass to `unregister`.
static func register(rect: Rect2, groove: Callable, porous: bool = false) -> int:
	var id := _next_id
	_next_id += 1
	_surfaces[id] = { "rect": rect, "groove": groove, "porous": porous }
	return id


## Removes a registered surface by the id `register` returned.
static func unregister(id: int) -> void:
	_surfaces.erase(id)


## Flow-cost multiplier at world `pos` (lower = blood flows more easily).
static func resistance(pos: Vector2) -> float:
	if not BloodConfig.surface_flow:
		return 1.0
	var ids := _surfaces.keys()
	ids.reverse()  # newest first, so a floor laid over another wins
	for id in ids:
		var s: Dictionary = _surfaces[id]
		if not (s["rect"] as Rect2).has_point(pos):
			continue
		if s["porous"]:
			return BloodConfig.porous_resist
		var g: float = clampf((s["groove"] as Callable).call(pos, BloodConfig.groove_half_width), 0.0, 1.0)
		return lerpf(BloodConfig.smooth_resist, BloodConfig.groove_resist, g)
	return 1.0
