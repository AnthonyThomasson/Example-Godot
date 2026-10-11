class_name WorldGenConfig

## Tuning for house furnishing (scenes/worldgen/room_furnisher.gd). A `class_name` holder of `static var`s —
## read as `WorldGenConfig.<name>`; there is no instance and no autoload.
##
## After a room's required zones are placed, its recipe's optional `fill` ({ target, options }) keeps adding
## arrangements until the room's solid footprints cover `target` (a fraction of the interior area), so big
## rooms are not left mostly bare. These knobs scale or cap that pass; the walkability checks that guard every
## placement are not tunable here.

## Master switch for the fill pass: off = rooms get only their recipe's zones.
static var fill_enabled: bool = true
## Multiplies every recipe's fill `target` (1 = as authored, 0 = no fill, 2 = twice as full).
static var fill_scale: float = 1.0
## Placement tries the fill pass makes per room, hits and misses alike (each listed option is tried once, so
## this only caps a very long option list).
static var fill_attempts: int = 24
## Most pieces the fill pass adds to one room.
static var fill_max_pieces: int = 14
