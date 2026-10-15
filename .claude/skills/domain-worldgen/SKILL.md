---
name: domain-worldgen
description: Deep implementation detail for the World Generation domain (scenes/worldgen/) — picking a floorplan and building/furnishing a house from catalogues, arrangements and recipes, and placing its run-down dressing (clutter, neon tubes, where wear gathers) and the street ring round it. Use when editing scenes/worldgen/ or working on house layouts, floorplans, room types, furniture catalogues, arrangements, recipes, placement, clutter, wear placement or the street. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# World Generation domain

Owns picking a floorplan and building/furnishing a house. It owns the *catalogue* (which
furniture/arrangements/recipes exist); the Objects domain owns the *field schema* and turns a
plain definition dict into a node — World-Gen never touches an object's fields.

## Pipeline

`WorldGen.generate` picks one of the `HouseDefinitions` floorplans (11: `starter_home`, `open_plan_home`, `studio_flat`,
`one_bed_flat`, `two_bed_flat`, `office_loft`, `bungalow`, `garage_home` and the three run-down cyberpunk flats `railroad_flat`,
`micro_flat`, `corner_flat`) and hands it to `HouseSpawner`:

```
HouseDefinitions (floorplans) ─┐        LayoutRules (is the plan logical?) ◀─ HouseSpawner._validate
categories/*  (catalogues)  ───┼─▶ HouseSpawner ─▶ WallFactory (walls, doorway openings cut in)
ObjectDefinitions / ───────────┘                ├▶ RoomFurnisher ─▶ ObjectFactory   (WorldGenConfig: fill knobs)
ArrangementDefinitions                          ├▶ RoomDresser ─▶ ObjectFactory (clutter, neon) / WearFactory (wear clusters)
                                                ├▶ FloorFactory (the floor the room's palette names)
                                                ├▶ FloorFactory (the street ring: sidewalk + asphalt)
                                                └▶ ObjectFactory (the street lamps along the front)
```

- **Floorplans** (`house_definitions.gd`): rooms are house-local `Rect2`s with a `type`;
  `openings` are doorway points on wall lines. `HouseSpawner` cuts each opening into every wall
  through it (`WallFactory.openings_for`), keeps opening clearances free of furniture, and mirrors the plan L/R 50% of the time.
  Openings are plain archways — there are no physical door objects. Exactly one opening is `front`
  (the house is positioned by it, always on the south wall); a plan may add `"exit": true` openings
  (an exterior back/side/garage door on exactly one room's wall). The houses have an exit; the flats and the
  office loft keep only the front door. `get_openings` reports `{ pos, width, front, exit, rooms }`.
- **Layout rules** (`layout_rules.gd`, `LayoutRules`): the tunable table of what makes a plan logical.
  `ROOMS[type]` = `front` (may carry the front door: studio, living room, great room, security vestibule,
  hallway — never a bedroom, bathroom, netrunner den …), `exit`, `through` (may be the only route between
  two other rooms; bedrooms/bathrooms/offices/netrunner dens may not — only a private dead end such as an en-suite may
  hang off them; a ripperdoc is walked through) and `max_doors` (a bathroom and a netrunner den have exactly one door, a
  kitchenette at most two); `LINKS` = the room-type pairs that may share an interior door (bathrooms only open onto a
  hallway, bedroom, living space or studio; a garage only onto kitchen/laundry/hallway; a netrunner den off a hallway,
  living space, studio or ripperdoc; a kitchenette off a studio, living room or hallway; a security vestibule onto a
  hallway, living space, studio, office or ripperdoc). `LayoutRules.check(rooms, openings)` returns one string per
  violation; `HouseSpawner._validate` warns with them and `tests/worldgen/house_doorways_connected_test.gd`
  fails on any plan (`layout_rules_test.gd` pins the validator itself against illogical layouts). A new room type needs its `ROOMS`/`LINKS` entries before a plan can use it. Bedrooms
  and bathrooms open off a **hallway** (type `hallway`, ≥120 px deep: `corner_flat`'s short inner hallway) or a
  living space; the one bedroom-to-bathroom door is a private en-suite (`LayoutRules.LINKS` allows it).
- **The cyberpunk flats**: `railroad_flat` (four rooms in a row, each opening into the next through
  doorways lined up along their north side: security vestibule on the street, living room, ripperdoc, netrunner den at the
  far end), `micro_flat` (a studio with a tiny bathroom and a kitchenette off it) and `corner_flat` (a security vestibule on the
  street onto a short inner hallway, with the living room, bedroom, bathroom and kitchenette round it). Between them they use
  every cyberpunk room type (`tests/worldgen/new_rooms_and_flats`). The flats have the front door only.
- **Catalogues** (`worldgen/categories/*.gd`, one `<Name>Catalog` per room type: living room, kitchen, bedroom, bathroom,
  home office, hallway, laundry, garage, and the cyberpunk rooms `netrunner_den` (monitor wall, recliner rig, server racks; cable nests
  its clutter), `ripperdoc` (surgical chair, tool carts, cyberware shelves), `security_vestibule` (lockers, scanner arch posts,
  barricade) and `kitchenette` (counter, hotplate, mini fridge), each piece with its own size, cover and penetration and a
  material from the shared set, so its impacts sound like that material's; `general.gd`
  holds shared entries + the `WOOD`/`FABRIC` palettes + the `FLOORS` and the house `WALL` style +
  combined recipes + the `streetlight` / `street_sign` rows). Hold `OBJECTS`,
  `ARRANGEMENTS`, `RECIPES`. `ObjectDefinitions` / `ArrangementDefinitions` are thin
  aggregators that merge them and expose `get_definition` / `get_arrangement` / `get_recipe`.
- **Arrangements** are authored against the top wall (`x` along, `y` depth); `placement`
  `"wall"`/`"center"`, `prefer_corner`, `tags` (dedupe). Items take `pos`, optional `rotated`
  (footprint swap) and optional `facing` (which way the piece's front faces in that frame;
  default `Vector2.DOWN`, into the room — a sofa facing the TV is `UP`, a chair facing a table
  to its right is `RIGHT`). **Recipes** list ordered `zones` (each picks `count` from `options`,
  with optional `required`/`fallback`) + `palettes`; each palette names its `wood` and `fabric`
  tones and a `floor` (a `GeneralCatalog.FLOORS` key, chosen to contrast with the wood).
- **Placement** (`room_furnisher.gd`) fits each arrangement's footprint against a random wall
  without overlap, rotates/mirrors it, then hands each object's definition to `ObjectFactory`
  (item `facing` mapped onto the wall by `_map_dir`, the same way positions are, and passed as
  `opts.facing`). `furnish` returns the palette it picked. `_try_place` is the one place a piece is
  committed (tags, spot search, occupied/walk-grid bookkeeping).
- **Fill pass**: a recipe may carry `fill: { target, options }`. After its zones, `_fill` keeps drawing
  random `options` (through the same placement checks) until the room's solid footprints cover `target`
  of the interior, so big rooms aren't left bare. Each listed option is tried once, hit or miss (list it
  twice to allow two): a miss can't become a hit later (a fuller room never gains a spot), so a full room
  ends the pass quickly. `WorldGenConfig` (`class_name` static holder)
  holds the knobs: `fill_enabled`, `fill_scale` (× every target; 0 = off), `fill_attempts`,
  `fill_max_pieces`. Fill consumes the shared RNG, so a seed is stable but changes if a recipe's fill does.
- **Ground pieces**: an arrangement with `"ground": true` (rugs `rug_center`/`rug_small`/`runner_hall`) is non-solid decor that lies *under* furniture: it avoids only other ground pieces,
  never touches the walk grid, and is tried dead-centre first. The `"rug"` tag keeps it to one rug a room
  (the `tv_wall_*` arrangements carry their own rug and the tag).
- **Walkability** (`room_furnisher.gd`): furnishing is planned before anything spawns (`_plan`), and a
  candidate spot is accepted only if it keeps every doorway of the room reachable from the others on a
  coarse grid (furniture grown by `FURNITURE_CLEAR`, the room edge by `WALL_CLEAR`; a doorway is the free
  cells inside its clearance box) and leaves no dead slot — a gap against a wall or other furniture must be
  just the padding or at least `SLOT_MAX` (a narrower slot is unwalkable and its overlapping nav-hole
  offsets can break the navmesh bake). If a required zone still finds no spot, the layout is re-rolled up to
  `PLAN_ATTEMPTS` times, then warns. Floorplans must give every room space for its required pieces plus the
  door lanes (e.g. no 3-door small bedrooms). `tests/worldgen/house_doorways_connected_test.gd` bakes every
  floorplan over many seeds and checks each room's doorways reach each other, each doorway can be passed
  through and every doorway is reachable from outside the front entrance.
- **Walls + floors**: `HouseSpawner` builds each room's walls in the `GeneralCatalog.WALL` style
  and, after furnishing, its floor — the `FLOORS` entry the room's palette names — over the room
  rect (to the wall centerlines, so the walls cover the seams). The floor rides on the palette
  draw, so it costs no extra RNG and seeds keep their layouts.
- **Run-down dressing** (`room_dresser.gd`, `RoomDresser`): World-Gen places, the Objects domain draws. Where things gather is
  `RoomDresser.anchor`: a corner, along a wall's foot, or just beside a solid piece (the footprints `RoomFurnisher.furnish`
  appends to its `solids` out-array, from the catalogue sizes), and whatever lands there stays within `WorldGenConfig.dress_near`
  of a wall line or a solid piece. Per room, after furnishing: **clutter** (`strew`): 0-2 walk-over pieces from the recipe's
  `clutter` (`[key, weight]` pairs; default `GeneralCatalog.CLUTTER`: `trash`, `cables`, `cable_nest`, `cardboard`, `puddle`, all
  non-solid `decor` catalogue pieces), no key twice, each its own size (`clutter_scale`) and `v` detail variant, off the solid
  furniture and the doorway clearance boxes, the long ones lying along the edge they hug; and in about every other room
  (`neon_tube_chance`) a **neon tube** (`neon_tube`, cyan or magenta) along the foot of a wall, clear of doorways. Once every room
  stands: its **wear** (`wear`): 0-3 clusters (`wear_bare_chance`, one more per `wear_more_area` with `wear_more_chance`), each
  handed with the free stretch of wall it is by (cut short of doorways, `dress_jamb`) to the Objects domain's `WearFactory`,
  which decides and draws the marks (after all walls, so a mark on a shared wall draws over both caps). Every room draws from
  RNGs of its own, `hash([run seed, room key, ...])` (`rng.seed`, never a draw from the shared RNG), so the dressing never
  shifts a seed's furniture layout.
- **The street** (`HouseSpawner._street`): a sidewalk ring `street_sidewalk` px deep hugging the bounds of the rooms and asphalt
  out to `street_reach` px, four strips of each (the top and bottom spanning the corners) through `FloorFactory` from
  `GeneralCatalog.STREET` (`art` `street`, `sound_surface: false`: footsteps out there stay `outdoor`; `light_layer: "street"`: lit only by
  the street lamps, the flashes and the street's sky, `docs/lighting.md` L4), each with its `marks`
  (`{ seed, edges, lane }`: the curb sides of a sidewalk, the gutter side of a road, the lane on the road in front, south) and a
  shared `tile_from`, so the slab joints meet.
- **The street lamps** (`HouseSpawner._streetlights`): along the front sidewalk, one about every `streetlight_every` (260) px,
  each jittered by up to `streetlight_jitter` (50) px, the row centred on the front, each post `streetlight_curb` px in from the
  curb with its arm out over the road (facing south); every other one is a neon sign (`street_sign`, cyan or magenta) and the rest
  `streetlight`s, both solid `anchored` metal posts (14 px circle, coverage 100, penetration 85) with an `overhang` (their arm
  and head), spawned through `ObjectFactory` under a `Street Lamps` node of the house, so the nav bake carves them. The door rule
  (`_door_zones`, `_clear_of_doors`): no part of a lamp (its post's square and its overhang) comes within
  `streetlight_door_clear` (140) px of a front or exit doorway's centre nor into the strip straight out of one (its width plus
  `streetlight_door_strip_margin` (32) px each side, `streetlight_door_strip_reach` (400) px out from the wall of its room); a lamp
  that would is dropped, not moved, so only a doorway's zone opens a wider gap. Its own RNG (`hash([run seed, "streetlights"])`),
  so the furniture layout never shifts (`tests/worldgen/streetlight_placement`).
- The house carries what it placed as metadata, read through interface 1: `rooms`, `openings`, `clutter` (`get_clutter`:
  `{ room, key, node }`), `wear` (`get_wear`: `{ room, pos, layer }`, world space), `street` (`get_street`:
  `{ kind, rect, node }`) and `streetlights` (`get_streetlights`: `{ pos, node }`, world space).
- Every definition sets `art` (a painter id) and usually `art_opts` (the painter's variant, e.g.
  `{ "front": "drawers", "count": 3 }`, or `props` dressing a surface); the Objects domain owns
  the painters (see `domain-objects`), and draws every catalogue colour run down (its palette grade), so catalogue colours stay
  plain (the `WALL` plaster is a nicotine yellow that grades to the dun cap).
- **Outside builders** (the Testing domain's arenas and placed pieces): `WorldGen.annotate_layout` derives the room keys
  each door joins with `HouseSpawner.room_keys_on`; the catalogue lookups read `ObjectDefinitions.get_definition`
  (`object_definition`), `GeneralCatalog.FLOORS` (`floor_definition`) and `GeneralCatalog.WALL` (`wall_style`).

## To add a room type

Add a `categories/<type>.gd` catalog with its recipe (register it in `ObjectDefinitions` and
`ArrangementDefinitions`), give the type its `LayoutRules.ROOMS` / `LINKS` entries and use its key as a
room `type`. Pieces used by 2+ categories (`bench`, `console_wall`, `bookshelf_wall`, the rugs …) live in
`GeneralCatalog`. New `class_name` scripts resolve only after Godot rescans (open the editor or run
`godot --headless --path . --import`).

## To add or change a floorplan

Rooms are rects that share walls; put a doorway on each shared wall you want open and make the graph
satisfy `LayoutRules` (check with `tools/run_tests.sh worldgen`). Mind the room sizes: a room needs space
for its required pieces plus the door lanes (`OPENING_CLEARANCE` each side of every doorway), or the
furnisher warns "no room for required zone" and the doorway test fails.

**Interfaces:** 1 (Main → World Generation, incl. `get_wear` / `get_clutter` / `get_street` / `get_streetlights`), 2 (World Generation → Objects,
incl. `WearFactory`) — signatures in `architecture`.
