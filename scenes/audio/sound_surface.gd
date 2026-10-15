class_name SoundSurface

## Audio domain: what the ground sounds like underfoot. Floors (the Objects domain) register their world rect with
## the material and pattern of their tile; `at` answers which kind of surface a world point is on, which is how a
## footstep picks its sound. Like BloodSurface, Audio imports nothing: the floor's owner hands over plain strings.
## A point on no floor is outdoors.

## Surfaces a sound set exists for (see SoundBank): wood, tile, stone, concrete, carpet and the open ground.
const OUTDOOR := &"outdoor"

## Registered floors, oldest first: [{ id: int, rect: Rect2, surface: StringName }].
static var _floors: Array = []
static var _next_id := 1  ## The id the next registered floor gets.


## Register a floor covering world `rect`, tiled in `material` with the painter's `pattern`. Returns the id
## to pass to `unregister`.
static func register(rect: Rect2, material: String, pattern: String = "") -> int:
	var id := _next_id
	_next_id += 1
	_floors.append({ "id": id, "rect": rect, "surface": surface_for(material, pattern) })
	return id


## Removes a registered floor by the id `register` returned.
static func unregister(id: int) -> void:
	for i in _floors.size():
		if _floors[i]["id"] == id:
			_floors.remove_at(i)
			return


## The surface at world `pos`: the newest registered floor covering it (a floor laid over another wins),
## or `OUTDOOR`.
static func at(pos: Vector2) -> StringName:
	for i in range(_floors.size() - 1, -1, -1):
		if (_floors[i]["rect"] as Rect2).has_point(pos):
			return _floors[i]["surface"]
	return OUTDOOR


## The surface a floor tiled in `material` / `pattern` is: planks and parquet are wood, ceramic is tile,
## slate is stone, poured concrete is concrete, fabric is carpet; anything unrecognised reads as wood.
static func surface_for(material: String, pattern: String = "") -> StringName:
	match material:
		"ceramic":
			return &"tile"
		"stone":
			return &"concrete" if pattern == "concrete" else &"stone"
		"fabric":
			return &"carpet"
	return &"wood"


## How many floors are registered (for tests).
static func count() -> int:
	return _floors.size()
