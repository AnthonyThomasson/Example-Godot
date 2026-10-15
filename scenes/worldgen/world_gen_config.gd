class_name WorldGenConfig

## Tuning for house furnishing (scenes/worldgen/room_furnisher.gd), the run-down dressing, the street and its lamps. A `class_name` holder of `static var`s —
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

## The run-down dressing (room_dresser.gd), each room on RNGs of its own. Where things gather: a corner or a wall's foot
## `dress_reach` px in from the room's walls (`dress_inset` px off a wall's face), or `dress_furniture_gap` px beside a solid
## piece; whatever is placed lies within `dress_near` px of a wall line or a solid piece, clear of `dress_jamb` px round a
## doorway; `dress_tries` spots are tried for each.
static var dress_inset: float = 6.0
static var dress_reach: Vector2 = Vector2(4, 30)
static var dress_furniture_gap: Vector2 = Vector2(3, 14)
static var dress_near: float = 44.0
static var dress_jamb: float = 6.0
static var dress_tries: int = 16
## Clutter a room: none with `clutter_none_chance`, two with `clutter_two_chance`, else one; each its catalogue size scaled
## by a factor in `clutter_scale`.
static var clutter_none_chance: float = 0.35
static var clutter_two_chance: float = 0.2
static var clutter_scale: Vector2 = Vector2(0.75, 1.25)
## Wear clusters a room: none with `wear_bare_chance`, else one, plus one more with `wear_more_chance` for each of
## `wear_more_area` (px²) the room is bigger than (so 0-3).
static var wear_bare_chance: float = 0.3
static var wear_more_area: Array[float] = [100000.0, 200000.0]
static var wear_more_chance: float = 0.5
## The share of rooms with a neon tube along the foot of a wall.
static var neon_tube_chance: float = 0.5
## The street round a house: a sidewalk `street_sidewalk` px deep hugging its outline, then asphalt out to `street_reach`
## px from it (past the outdoor ring the nav map walks).
static var street_sidewalk: float = 44.0
static var street_reach: float = 300.0
## The street lamps along the front sidewalk (HouseSpawner): one about every `streetlight_every` px along it, each up to
## `streetlight_jitter` px either way off its even spot, its post `streetlight_curb` px in from the curb and its arm out over
## the road; every other one is a neon sign. No part of a lamp (its post or its overhang) comes within
## `streetlight_door_clear` px of a front or exit doorway's centre, nor into the strip straight out of one (the doorway's
## width plus `streetlight_door_strip_margin` px each side, `streetlight_door_strip_reach` px out from the wall): a lamp
## that would is dropped, not moved.
static var streetlight_every: float = 260.0
static var streetlight_jitter: float = 50.0
static var streetlight_curb: float = 8.0
static var streetlight_door_clear: float = 140.0
static var streetlight_door_strip_margin: float = 32.0
static var streetlight_door_strip_reach: float = 400.0
