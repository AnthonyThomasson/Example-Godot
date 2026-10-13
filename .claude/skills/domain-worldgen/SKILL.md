---
name: domain-worldgen
description: Deep implementation detail for the World Generation domain (scenes/worldgen/) — picking a floorplan and building/furnishing a house from catalogues, arrangements and recipes. Use when editing scenes/worldgen/ or working on house layouts, floorplans, room types, furniture catalogues, arrangements, recipes, or placement. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# World Generation domain

Owns picking a floorplan and building/furnishing a house. It owns the *catalogue* (which
furniture/arrangements/recipes exist); the Objects domain owns the *field schema* and turns a
plain definition dict into a node — World-Gen never touches an object's fields.

## Pipeline

`WorldGen.generate` picks one of the `HouseDefinitions` floorplans (12, `studio_flat` …
`luxury_home`) and hands it to `HouseSpawner`:

```
HouseDefinitions (floorplans) ─┐        LayoutRules (is the plan logical?) ◀─ HouseSpawner._validate
categories/*  (catalogues)  ───┼─▶ HouseSpawner ─▶ WallFactory (walls, doorway openings cut in)
ObjectDefinitions / ───────────┘                ├▶ RoomFurnisher ─▶ ObjectFactory   (WorldGenConfig: fill knobs)
ArrangementDefinitions                          └▶ FloorFactory (the floor the room's palette names)
```

- **Floorplans** (`house_definitions.gd`): rooms are house-local `Rect2`s with a `type`;
  `openings` are doorway points on wall lines. `HouseSpawner` cuts each opening into every wall
  through it, keeps opening clearances free of furniture, and mirrors the plan L/R 50% of the time.
  Openings are plain archways — there are no physical door objects. Exactly one opening is `front`
  (the house is positioned by it, always on the south wall); a plan may add `"exit": true` openings
  (an exterior back/side/garage door on exactly one room's wall). Houses have an exit; the flats keep
  only the front door. `get_openings` reports `{ pos, width, front, exit, rooms }`.
- **Layout rules** (`layout_rules.gd`, `LayoutRules`): the tunable table of what makes a plan logical.
  `ROOMS[type]` = `front` (may carry the front door: studio, living room, great room, entry hall,
  hallway — never a bedroom, bathroom, dining room …), `exit`, `through` (may be the only route between
  two other rooms; bedrooms/bathrooms/offices may not — only a private dead end such as an en-suite may
  hang off them) and `max_doors` (a bathroom has exactly one door); `LINKS` = the room-type pairs that may
  share an interior door (bathrooms only open onto a hallway, bedroom, living space or studio; a garage
  only onto kitchen/laundry/hallway). `LayoutRules.check(rooms, openings)` returns one string per
  violation; `HouseSpawner._validate` warns with them and `tests/worldgen/house_doorways_connected_test.gd`
  fails on any plan (`layout_rules_test.gd` pins the validator itself against illogical layouts). A new room type needs its `ROOMS`/`LINKS` entries before a plan can use it. Bedrooms
  and bathrooms open off a **hallway** (type `hallway`, ≥120 px deep: `family_home`, `luxury_home`) or a
  living space, never off each other.
- **Catalogues** (`worldgen/categories/*.gd`, one `<Name>Catalog` per room type; `general.gd`
  holds shared entries + the `WOOD`/`FABRIC` palettes + the `FLOORS` and the house `WALL` style +
  combined recipes). Hold `OBJECTS`,
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
- Every definition sets `art` (a painter id) and usually `art_opts` (the painter's variant, e.g.
  `{ "front": "drawers", "count": 3 }`, or `props` dressing a surface); the Objects domain owns
  the painters (see `domain-objects`).

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

## Interface recap (authoritative in the `architecture` skill)

- **Main → World Generation** (interface 1): `WorldGen.generate(seed, force_plan,
  front_entrance_world, parent) -> Node2D` seeds one RNG for the whole run (plan
  pick is its first draw), prints `House: <plan>  seed: N`, builds the house; every doorway is an
  open archway. `WorldGen.annotate_layout(root, rooms, doors)` writes the same `rooms` / `openings` metadata onto a hand-built
  root (the Testing domain's arenas and layouts; `HouseSpawner.room_keys_on` derives the room keys a door joins).
  `WorldGen.get_openings(house) -> Array`
  returns the doorways as `{ pos, width, front, exit, rooms }` (world space; `rooms` = the room keys it joins).
  `WorldGen.get_rooms(house) -> Array`
  returns rooms as `{ key, type, rect }` dicts (world-space `rect`), read from the house's
  `rooms` metadata. `main.gd` positions the front entrance, fixes draw order, builds the nav map, and
  drops the NPC in — all via `get_rooms`; it never touches world-gen internals. Read-only catalogue
  lookups for outside builders (the Testing domain's arenas and placed pieces):
  `WorldGen.object_definition(key)` (`ObjectDefinitions.get_definition`),
  `WorldGen.floor_definition(key)` (`GeneralCatalog.FLOORS`) and `WorldGen.wall_style()`
  (`GeneralCatalog.WALL`).
- **World Generation → Objects** (interface 2, the only way world-gen makes entities):
  `ObjectFactory.spawn(definition, position, parent, opts) -> Node`,
  `WallFactory.spawn(rect, thickness, openings, name, parent, style) -> Node`,
  `FloorFactory.spawn(rect, definition, name, parent) -> Node`; `HouseSpawner` cuts each room's doorways
  with `WallFactory.openings_for(rect, openings)`. World-Gen's only outward code deps are the three
  factories — it is a leaf.
