class_name ObjectDefinitions

## Aggregator over the per-category catalogs in scenes/worldgen/categories/. Merges
## every catalog's OBJECTS into one cached lookup and exposes the lookup RoomFurnisher
## and WorldGen use. Shared objects (used by 2+ categories) live in GeneralCatalog; each
## room category owns the rest. To add an object, drop it in the matching catalog (or
## GeneralCatalog if used by 2+ categories).
##
## Object fields are the Objects domain's schema (object_factory.gd). A "wood" or "fabric"
## `material` also takes the room palette's tone.

## Every catalog's OBJECTS merged by key, filled on the first lookup.
static var _catalog: Dictionary = {}

## Keys are unique across catalogs, so the merge never collides.
static func _all() -> Dictionary:
	if _catalog.is_empty():
		for src in [GeneralCatalog.OBJECTS, LivingRoomCatalog.OBJECTS,
				KitchenCatalog.OBJECTS, BedroomCatalog.OBJECTS, BathroomCatalog.OBJECTS,
				HomeOfficeCatalog.OBJECTS, HallwayCatalog.OBJECTS, LaundryRoomCatalog.OBJECTS,
				GarageCatalog.OBJECTS, NetrunnerDenCatalog.OBJECTS, RipperdocCatalog.OBJECTS,
				SecurityVestibuleCatalog.OBJECTS, KitchenetteCatalog.OBJECTS]:
			_catalog.merge(src)
	return _catalog

## The object definition for `key`, or {} if unknown.
static func get_definition(key: String) -> Dictionary:
	return _all().get(key, {})
