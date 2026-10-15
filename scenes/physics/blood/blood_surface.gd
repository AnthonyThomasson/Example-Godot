class_name BloodSurface

## What the ground feels like to flowing blood. Surfaces (a room's floor) register a world rect plus a
## `groove` Callable `(world_pos, half_width) -> float` (1 = on a groove such as grout or a plank seam,
## 0 = smooth); `resistance` turns that into a flow-cost multiplier for BloodFlow, so blood runs fast
## along grooves and slowly across smooth surface. A `porous` surface (carpet, a rug) flows slowly and
## soaks the blood in (BloodFlow, `is_porous`), leaving a stain.
## Physics imports nothing: the surface's owner supplies the Callable. Point outside every surface = 1.

## Registered surfaces: id -> { rect: Rect2, groove: Callable, porous: bool }.
static var _surfaces: Dictionary = {}
static var _next_id := 1  ## The id the next `register` hands out.
## How many registered surfaces are porous, so `is_porous` costs nothing in a world with none.
static var _porous_count := 0


## Register a surface covering world `rect`. Returns the id to pass to `unregister`.
static func register(rect: Rect2, groove: Callable, porous: bool = false) -> int:
	var id := _next_id
	_next_id += 1
	_surfaces[id] = { "rect": rect, "groove": groove, "porous": porous }
	if porous:
		_porous_count += 1
	return id


## Removes a registered surface by the id `register` returned.
static func unregister(id: int) -> void:
	var s: Dictionary = _surfaces.get(id, {})
	if s.get("porous", false):
		_porous_count -= 1
	_surfaces.erase(id)


## Whether any porous surface (carpet, a rug) lies at world `pos`: blood there sinks in. Any porous surface
## counts, so a rug over a tiled floor soaks whichever was registered first.
static func is_porous(pos: Vector2) -> bool:
	if _porous_count == 0 or not BloodConfig.surface_flow:
		return false
	for s: Dictionary in _surfaces.values():
		if s["porous"] and (s["rect"] as Rect2).has_point(pos):
			return true
	return false


## Flow-cost multiplier at world `pos` (lower = blood flows more easily).
static func resistance(pos: Vector2) -> float:
	if not BloodConfig.surface_flow:
		return 1.0
	if is_porous(pos):
		return BloodConfig.porous_resist
	var ids := _surfaces.keys()
	ids.reverse()  # newest first, so a floor laid over another wins
	for id in ids:
		var s: Dictionary = _surfaces[id]
		if not (s["rect"] as Rect2).has_point(pos):
			continue
		var g: float = clampf((s["groove"] as Callable).call(pos, BloodConfig.groove_half_width), 0.0, 1.0)
		return lerpf(BloodConfig.smooth_resist, BloodConfig.groove_resist, g)
	return 1.0
