class_name ArrangementDefinitions

## Aggregator over the per-category catalogs in scenes/builder/categories/. Merges
## every catalog's ARRANGEMENTS and RECIPES into two cached lookups and exposes the
## same API RoomFurnisher already uses. Shared arrangements/recipes live in
## GeneralCatalog; each room category owns the rest. To add an arrangement, drop it
## in the matching catalog (or GeneralCatalog if used by 2+ categories) and list it
## in a recipe zone.
##
## Authoring conventions for an arrangement (unchanged):
## An arrangement is authored in a local frame AS IF PLACED AGAINST THE TOP WALL:
##   x runs along the wall (0..footprint.x), y is depth into the room (0..footprint.y).
## Item `pos` is the item's center. `rotated` swaps an item's width/height (90° turn).
## The furnisher rotates the whole frame onto whichever wall it picks, and may mirror it.
##   placement:     "wall" (backed against a wall) or "center" (free-standing).
##   prefer_corner: try the ends of a wall first.
##   tags:          an arrangement is skipped if a room already placed one with a
##                  shared tag (e.g. only one "fridge" per kitchen).
##
## A recipe's `zones` are filled in order. Each zone picks `count` (min..max) distinct
## arrangements from `options`; `required` zones warn if nothing could be placed. One
## palette is picked per room and applied to every "wood"/"fabric" object.

static var _arrangements: Dictionary = {}
static var _recipes: Dictionary = {}

## GeneralCatalog holds the shared/combined entries; each other catalog owns its
## category. Keys are unique across catalogs, so the merge never collides.
static func _all_arrangements() -> Dictionary:
	if _arrangements.is_empty():
		for src in [GeneralCatalog.ARRANGEMENTS, LivingRoomCatalog.ARRANGEMENTS,
				KitchenCatalog.ARRANGEMENTS, BedroomCatalog.ARRANGEMENTS, BathroomCatalog.ARRANGEMENTS,
				DiningRoomCatalog.ARRANGEMENTS, HomeOfficeCatalog.ARRANGEMENTS, KidsRoomCatalog.ARRANGEMENTS,
				EntryHallCatalog.ARRANGEMENTS, LaundryRoomCatalog.ARRANGEMENTS, GarageCatalog.ARRANGEMENTS]:
			_arrangements.merge(src)
	return _arrangements

static func _all_recipes() -> Dictionary:
	if _recipes.is_empty():
		for src in [GeneralCatalog.RECIPES, LivingRoomCatalog.RECIPES,
				KitchenCatalog.RECIPES, BedroomCatalog.RECIPES, BathroomCatalog.RECIPES,
				DiningRoomCatalog.RECIPES, HomeOfficeCatalog.RECIPES, KidsRoomCatalog.RECIPES,
				EntryHallCatalog.RECIPES, LaundryRoomCatalog.RECIPES, GarageCatalog.RECIPES]:
			_recipes.merge(src)
	return _recipes

static func get_arrangement(key: String) -> Dictionary:
	return _all_arrangements().get(key, {})

static func get_recipe(room_type: String) -> Dictionary:
	return _all_recipes().get(room_type, {})
