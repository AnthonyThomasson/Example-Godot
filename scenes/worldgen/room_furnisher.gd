class_name RoomFurnisher

## Fills a room's interior with arrangements from its recipe (ArrangementDefinitions).
## Arrangements are placed as whole blocks: each one's footprint is fitted against a
## wall (or free-standing for "center" placement) without overlapping other placed
## blocks or any blocked area (doorway-opening clearances), then its items are spawned.

## Which wall an arrangement's local "top wall" frame is mapped onto.
enum Orient { TOP, BOTTOM, LEFT, RIGHT }

const PADDING := 8.0       ## Minimum gap between arrangements (and doorway-opening clearances).
const STEP := 10.0         ## Spacing of candidate offsets along a wall.
const CENTER_TRIES := 40   ## Random spots tried for free-standing arrangements.


## `interior` and `blocked` rects are in `parent`'s coordinate space.
static func furnish(room_type: String, interior: Rect2, blocked: Array, rng: RandomNumberGenerator, parent: Node) -> void:
	var recipe := ArrangementDefinitions.get_recipe(room_type)
	if recipe.is_empty():
		push_error("No furnishing recipe for room type: ", room_type)
		return

	var palettes: Array = recipe["palettes"]
	var palette: Dictionary = palettes[rng.randi_range(0, palettes.size() - 1)]
	var occupied: Array = blocked.duplicate()
	var used_tags := {}

	for zone in recipe["zones"]:
		var count_range: Vector2i = zone["count"]
		var wanted := rng.randi_range(count_range.x, count_range.y)
		var placed := 0
		for key in _shuffled(zone["options"], rng):
			if placed >= wanted:
				break
			var arrangement := ArrangementDefinitions.get_arrangement(key)
			var tags: Array = arrangement.get("tags", [])
			if tags.any(func(t: String) -> bool: return used_tags.has(t)):
				continue
			var spot := _find_spot(arrangement, interior, occupied, rng)
			if spot.is_empty():
				continue
			occupied.append(spot["rect"])
			for tag in tags:
				used_tags[tag] = true
			_spawn_items(arrangement, spot, palette, parent)
			placed += 1
		# A required zone that couldn't place any of its (large) options falls back to a
		# guaranteed-small arrangement, so essentials always appear even in tight rooms.
		if placed == 0 and wanted > 0 and zone.has("fallback"):
			var fb := ArrangementDefinitions.get_arrangement(zone["fallback"])
			var fb_spot := _find_spot(fb, interior, occupied, rng)
			if not fb_spot.is_empty():
				occupied.append(fb_spot["rect"])
				_spawn_items(fb, fb_spot, palette, parent)
				placed = 1
		if zone.get("required", false) and placed == 0 and wanted > 0:
			push_warning("RoomFurnisher: no room for required zone %s in %s" % [zone["options"], room_type])


## Returns { rect, orient, mirror } for a free spot, or {} if none fits.
static func _find_spot(arrangement: Dictionary, interior: Rect2, occupied: Array, rng: RandomNumberGenerator) -> Dictionary:
	var fp: Vector2 = arrangement["footprint"]
	var mirror := rng.randf() < 0.5

	if arrangement.get("placement", "wall") == "center":
		for i in range(CENTER_TRIES):
			var orient: int = rng.randi_range(Orient.TOP, Orient.RIGHT)
			var size := _oriented_size(fp, orient)
			var slack := interior.size - size
			if slack.x < 0.0 or slack.y < 0.0:
				continue
			# First try dead center, then random spots.
			var t := Vector2(0.5, 0.5) if i == 0 else Vector2(rng.randf(), rng.randf())
			var rect := Rect2(interior.position + slack * t, size)
			if _fits(rect, interior, occupied):
				return { "rect": rect, "orient": orient, "mirror": mirror }
		return {}

	for orient in _shuffled([Orient.TOP, Orient.BOTTOM, Orient.LEFT, Orient.RIGHT], rng):
		var wall_length := interior.size.x if orient in [Orient.TOP, Orient.BOTTOM] else interior.size.y
		var max_offset := wall_length - fp.x
		if max_offset < 0.0:
			continue
		for offset in _offsets(max_offset, arrangement.get("prefer_corner", false), rng):
			var rect := _wall_rect(orient, offset, fp, interior)
			if _fits(rect, interior, occupied):
				return { "rect": rect, "orient": orient, "mirror": mirror }
	return {}


## Candidate offsets along a wall; corners first when preferred, otherwise shuffled.
static func _offsets(max_offset: float, prefer_corner: bool, rng: RandomNumberGenerator) -> Array:
	var offsets: Array = []
	var offset := 0.0
	while offset < max_offset:
		offsets.append(offset)
		offset += STEP
	offsets.append(max_offset)
	offsets = _shuffled(offsets, rng)
	if prefer_corner:
		offsets = _shuffled([0.0, max_offset], rng) + offsets
	return offsets


## World rect of a footprint backed against `orient`'s wall at `offset` along it.
static func _wall_rect(orient: int, offset: float, fp: Vector2, interior: Rect2) -> Rect2:
	var p := interior.position
	var e := interior.end
	match orient:
		Orient.TOP:
			return Rect2(p.x + offset, p.y, fp.x, fp.y)
		Orient.BOTTOM:
			return Rect2(p.x + offset, e.y - fp.y, fp.x, fp.y)
		Orient.LEFT:
			return Rect2(p.x, p.y + offset, fp.y, fp.x)
		_:
			return Rect2(e.x - fp.y, p.y + offset, fp.y, fp.x)


## A footprint's size once mapped onto the given wall orientation.
static func _oriented_size(fp: Vector2, orient: int) -> Vector2:
	return fp if orient in [Orient.TOP, Orient.BOTTOM] else Vector2(fp.y, fp.x)


## True if `rect` fits inside the interior and clears every occupied rect (with padding).
static func _fits(rect: Rect2, interior: Rect2, occupied: Array) -> bool:
	if not interior.encloses(rect):
		return false
	var padded := rect.grow(PADDING)
	for other in occupied:
		if padded.intersects(other):
			return false
	return true


## Map each item from the arrangement's top-wall frame into the chosen spot and spawn it.
static func _spawn_items(arrangement: Dictionary, spot: Dictionary, palette: Dictionary, parent: Node) -> void:
	var fp: Vector2 = arrangement["footprint"]
	var rect: Rect2 = spot["rect"]
	var orient: int = spot["orient"]
	var mirror: bool = spot["mirror"]
	var sideways := orient == Orient.LEFT or orient == Orient.RIGHT

	for item in arrangement["items"]:
		var key: String = item["key"]
		var local: Vector2 = item["pos"]
		if mirror:
			local.x = fp.x - local.x
		var mapped: Vector2
		match orient:
			Orient.TOP:
				mapped = local
			Orient.BOTTOM:
				mapped = Vector2(local.x, fp.y - local.y)
			Orient.LEFT:
				mapped = Vector2(local.y, local.x)
			_:
				mapped = Vector2(fp.y - local.y, local.x)

		# World-Gen owns the catalogue: look the definition up here and hand the plain
		# dict to the Objects factory (which never knows about ObjectDefinitions).
		var definition := ObjectDefinitions.get_definition(key)
		if definition.is_empty():
			push_error("Unknown object type: ", key)
			continue
		var opts := {
			"rotated": item.get("rotated", false) != sideways, "name": key,
			"facing": _map_dir(item.get("facing", Vector2.DOWN), orient, mirror),
		}
		var material: String = definition.get("material", "")
		if palette.has(material):
			opts["color"] = palette[material]
		ObjectFactory.spawn(definition, rect.position + mapped, parent, opts)


## Map a direction from the arrangement's top-wall frame onto the chosen wall, the same way
## _spawn_items maps item positions (mirror flips x; LEFT/RIGHT swap the axes).
static func _map_dir(dir: Vector2, orient: int, mirror: bool) -> Vector2:
	if mirror:
		dir.x = -dir.x
	match orient:
		Orient.TOP:
			return dir
		Orient.BOTTOM:
			return Vector2(dir.x, -dir.y)
		Orient.LEFT:
			return Vector2(dir.y, dir.x)
		_:
			return Vector2(-dir.y, dir.x)


## Fisher–Yates shuffle driven by `rng`, so a seed reproduces the whole house.
static func _shuffled(items: Array, rng: RandomNumberGenerator) -> Array:
	var result := items.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result
