class_name ObjectDefinitions

## Aggregator over the per-category catalogs in scenes/builder/categories/. Merges
## every catalog's OBJECTS into one cached lookup and exposes the same API that
## ObjectSpawner / RoomFurnisher already use. Shared objects (used by 2+ categories)
## live in GeneralCatalog; each room category owns the rest. To add an object, drop
## it in the matching catalog (or GeneralCatalog if used by 2+ categories).
##
## Object fields: name, shape ("circle"|"square"|"rect"), size, color (required);
##   material (descriptive tag — "wood"/"fabric" also take the room palette's tone,
##     others like "metal"/"glass"/"ceramic" are descriptive only);
##   coverage (0–100 height/cover proxy); penetration (0–100 shoot-through resistance);
##   solid (optional, default true; false = walk-over decor drawn under everything).

static var _catalog: Dictionary = {}

## Keys are unique across catalogs, so the merge never collides.
static func _all() -> Dictionary:
	if _catalog.is_empty():
		for src in [GeneralCatalog.OBJECTS, LivingRoomCatalog.OBJECTS,
				KitchenCatalog.OBJECTS, BedroomCatalog.OBJECTS, BathroomCatalog.OBJECTS,
				DiningRoomCatalog.OBJECTS, HomeOfficeCatalog.OBJECTS, KidsRoomCatalog.OBJECTS,
				EntryHallCatalog.OBJECTS, LaundryRoomCatalog.OBJECTS, GarageCatalog.OBJECTS]:
			_catalog.merge(src)
	return _catalog

static func get_definition(key: String) -> Dictionary:
	return _all().get(key, {})
