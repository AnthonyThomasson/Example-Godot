class_name ArrangementDefinitions

## Aggregator over the per-category catalogs in scenes/worldgen/categories/. Merges
## every catalog's ARRANGEMENTS and RECIPES into two cached lookups and exposes the
## lookups RoomFurnisher uses. Shared arrangements/recipes live in
## GeneralCatalog; each room category owns the rest. To add an arrangement, drop it
## in the matching catalog (or GeneralCatalog if used by 2+ categories) and list it
## in a recipe zone.
##
## Authoring conventions for an arrangement:
## An arrangement is authored in a local frame AS IF PLACED AGAINST THE TOP WALL:
##   x runs along the wall (0..footprint.x), y is depth into the room (0..footprint.y).
## Item `pos` is the item's center. `rotated` swaps an item's width/height (90° turn).
## Item `facing` is the way its front faces in this frame (default Vector2.DOWN, into the
## room): a sofa facing a TV on the top wall is UP; a chair facing a table to its right is RIGHT.
## The furnisher rotates the whole frame onto whichever wall it picks, and may mirror it.
##   placement:     "wall" (backed against a wall) or "center" (free-standing).
##   prefer_corner: try the ends of a wall first.
##   tags:          an arrangement is skipped if a room already placed one with a
##                  shared tag (e.g. only one "fridge" per kitchen).
##
##   ground:        a non-solid piece that lies under the furniture (a rug, runner, mat): it never
##                  blocks the floor, avoids only other ground pieces, and is placed dead center first.
##
## A recipe's `zones` are filled in order. Each zone picks `count` (min..max) distinct
## arrangements from `options`; `required` zones warn if nothing could be placed. A recipe may
## also carry `fill: { target, options }`: once the zones are placed it keeps adding random
## `options` until solid footprints cover `target` (a fraction of the interior), bounded and scaled
## by WorldGenConfig. One palette is picked per room and applied to every "wood"/"fabric" object.

static var _arrangements: Dictionary = {}
static var _recipes: Dictionary = {}

## GeneralCatalog holds the shared/combined entries; each other catalog owns its
## category. Keys are unique across catalogs, so the merge never collides.
static func _all_arrangements() -> Dictionary:
	if _arrangements.is_empty():
		for src in [GeneralCatalog.ARRANGEMENTS, LivingRoomCatalog.ARRANGEMENTS,
				KitchenCatalog.ARRANGEMENTS, BedroomCatalog.ARRANGEMENTS, BathroomCatalog.ARRANGEMENTS,
				DiningRoomCatalog.ARRANGEMENTS, HomeOfficeCatalog.ARRANGEMENTS, KidsRoomCatalog.ARRANGEMENTS,
				EntryHallCatalog.ARRANGEMENTS, HallwayCatalog.ARRANGEMENTS, LaundryRoomCatalog.ARRANGEMENTS,
				GarageCatalog.ARRANGEMENTS]:
			_arrangements.merge(src)
	return _arrangements

## Merge every catalog's RECIPES into one cached lookup.
static func _all_recipes() -> Dictionary:
	if _recipes.is_empty():
		for src in [GeneralCatalog.RECIPES, LivingRoomCatalog.RECIPES,
				KitchenCatalog.RECIPES, BedroomCatalog.RECIPES, BathroomCatalog.RECIPES,
				DiningRoomCatalog.RECIPES, HomeOfficeCatalog.RECIPES, KidsRoomCatalog.RECIPES,
				EntryHallCatalog.RECIPES, HallwayCatalog.RECIPES, LaundryRoomCatalog.RECIPES,
				GarageCatalog.RECIPES]:
			_recipes.merge(src)
	return _recipes

## The arrangement for `key`, or {} if unknown.
static func get_arrangement(key: String) -> Dictionary:
	return _all_arrangements().get(key, {})

## The furnishing recipe for a room type, or {} if none.
static func get_recipe(room_type: String) -> Dictionary:
	return _all_recipes().get(room_type, {})
