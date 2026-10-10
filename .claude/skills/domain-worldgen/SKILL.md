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
HouseDefinitions (floorplans) ─┐
categories/*  (catalogues)  ───┼─▶ HouseSpawner ─▶ WallFactory (walls, doorway openings cut in)
ObjectDefinitions / ───────────┘                └▶ RoomFurnisher ─▶ ObjectFactory
ArrangementDefinitions
```

- **Floorplans** (`house_definitions.gd`): rooms are house-local `Rect2`s with a `type`;
  `openings` are doorway points on wall lines. `HouseSpawner` cuts each opening into every wall
  through it, keeps opening clearances free of furniture, and mirrors the plan L/R 50% of the time.
  Openings are plain archways — there are no physical door objects.
- **Catalogues** (`worldgen/categories/*.gd`, one `<Name>Catalog` per room type; `general.gd`
  holds shared entries + the `WOOD`/`FABRIC` palettes + combined recipes). Hold `OBJECTS`,
  `ARRANGEMENTS`, `RECIPES`. `ObjectDefinitions` / `ArrangementDefinitions` are thin
  aggregators that merge them and expose `get_definition` / `get_arrangement` / `get_recipe`.
- **Arrangements** are authored against the top wall (`x` along, `y` depth); `placement`
  `"wall"`/`"center"`, `prefer_corner`, `tags` (dedupe). Items take `pos`, optional `rotated`
  (footprint swap) and optional `facing` (which way the piece's front faces in that frame;
  default `Vector2.DOWN`, into the room — a sofa facing the TV is `UP`, a chair facing a table
  to its right is `RIGHT`). **Recipes** list ordered `zones` (each picks `count` from `options`,
  with optional `required`/`fallback`) + `palettes`.
- **Placement** (`room_furnisher.gd`) fits each arrangement's footprint against a random wall
  without overlap, rotates/mirrors it, then hands each object's definition to `ObjectFactory`
  (item `facing` mapped onto the wall by `_map_dir`, the same way positions are, and passed as
  `opts.facing`).
- Definitions may set `art` / `art_opts` to draw a piece as pixel art (the sofa, the tables and
  the chair do); the Objects domain owns the painters.

## To add a room type

Add a `categories/<type>.gd` catalog with its recipe and use its key as a room `type`. New
`class_name` scripts resolve only after Godot rescans (open the editor or run `godot --headless
--path . --import`).

## Interface recap (authoritative in the `architecture` skill)

- **Main → World Generation** (interface 1): `WorldGen.generate(seed, force_plan,
  front_entrance_world, parent) -> Node2D` seeds one RNG for the whole run (plan
  pick is its first draw), prints `House: <plan>  seed: N`, builds the house; every doorway is an
  open archway. `WorldGen.get_rooms(house) -> Array`
  returns rooms as `{ key, type, rect }` dicts (world-space `rect`), read from the house's
  `rooms` metadata. `main.gd` positions the front entrance, fixes draw order, builds the nav map, and
  drops the NPC in — all via `get_rooms`; it never touches world-gen internals.
- **World Generation → Objects** (interface 2, the only way world-gen makes entities):
  `ObjectFactory.spawn(definition, position, parent, opts) -> Node`,
  `WallFactory.spawn(rect, thickness, openings, name, parent) -> Node`, and `Wall.Side` (enum
  used when building `openings`). World-Gen's only outward code deps are `Wall.Side` + the two
  factories — it is a leaf.
