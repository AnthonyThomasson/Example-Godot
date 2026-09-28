# AGENTS.md — Example_Godot architecture

A small top-down Godot 4.4 demo: a circle you drive with WASD around a
procedurally furnished house, with two "hands" that aim at the mouse and a punch
on **F**. This file explains the conventions so future changes stay consistent.

## Scene / file layout

Scripts are grouped by entity into folders, and each entity is split into
separate files by **responsibility — control / animate / draw** (see next
section). To have its own `_draw()`, a "draw" file is attached to its own child
`Node2D` (Godot only draws from `CanvasItem` nodes).

- `scenes/main.tscn` — root `Node2D` (`main.gd`). Tree:
  ```
  Main
	MainCamera (Camera2D, world/camera_controller.gd)  follows player, leads toward mouse
	DebugUI (CanvasLayer, world/debug_ui.gd)           screen HUD: state + last hit
	  Label                                 on-screen hint text
	House (Node2D)                          spawned at runtime by main.gd, see below
	  <Room> (StaticBody2D, builder/room/room.gd)   CONTROL: segments + colliders
		RoomVisuals (Node2D, builder/room/room_visuals.gd) DRAW: wall lines
	  <Room> Furniture (Node2D)             environment objects for that room
	Player (CharacterBody2D, player/player.gd)     CONTROL: input, movement, facing
	  CollisionShape2D                      body collider (shape set at runtime)
	  PlayerAnimator (Node2D, player/player_animator.gd)  ANIMATE: punch + fist hits
	  PlayerVisuals  (Node2D, player/player_visuals.gd)   DRAW: body + hands
  ```
- `scenes/player/` — `player.gd`, `player_animator.gd`, `player_visuals.gd`.
- `scenes/objects/` — `environment_object.gd` (+ `_visuals`), the runtime object node.
- `scenes/projectile/` — game logic: the projectile & casing entities (`projectile.gd`,
  `casing.gd`, + `_visuals`) and their runtime spawners (`ProjectileSpawner`,
  `CasingSpawner`).
- `scenes/world/` — general game-logic systems: the `Config` and `Despawner` autoloads
  (see `project.godot`), the camera controller, and the debug HUD.
- `scenes/builder/` — **world creation only**: data (`*_definitions.gd`) and static
  spawners that build rooms, objects and the house at runtime (`class_name`d, see
  "House generation"). Kept isolated from game logic.
- `scenes/builder/room/` — `room.gd` (+ `room_visuals.gd`), the runtime room entity
  (CONTROL + DRAW) that `RoomSpawner` attaches to each spawned room's `StaticBody2D`.
- `scenes/builder/categories/` — the furniture catalogue split one file per room
  category (`living_room.gd`, `kitchen.gd`, …), each `class_name`d `<Name>Catalog`
  and holding that category's `OBJECTS` / `ARRANGEMENTS` / `RECIPES`. `general.gd`
  (`GeneralCatalog`) holds anything used by 2+ categories, the shared `WOOD`/`FABRIC`
  palettes, and the combined room recipes (`kitchen_living`, `studio`).
- `scenes/keybinds.gd` — autoloaded as **`Keybinds`** (see `project.godot`
  `[autoload]`). The single source of truth for input. (Shared, so not in a
  per-entity folder.)
- `project.godot` — project config; the `[input]` map mirrors `Keybinds`.

## Layered structure — control / animate / draw

Each entity separates the three verbs into their own file, wired via the scene
tree (no `class_name`; cross-file calls resolve through `$` / `get_parent()`):

- **Control** (root body node) owns state + input + physics and orchestrates. It
  never draws. `player.gd` computes `facing` from the mouse, moves the body, sets
  its collision shape, and each frame pushes `facing` to the animator and forwards
  punch presses (`_animator.try_punch()`). `room.gd` owns the wall-segment math
  (public `wall_segments()`) and builds colliders.
- **Animate** (`player_animator.gd`, a child `Node2D`) owns hand geometry, the
  per-hand punch tweens, and the runtime `Fist` `Area2D` + hit detection. It reads
  the body `radius` from its parent and exposes `hand_position(i)` + the `punched`
  signal. (The room has no animation layer — its walls are static.)
- **Draw** (`*_visuals.gd`, child `Node2D`s) own appearance only: colors + `_draw()`.
  `player_visuals.gd` reads `radius` from the control parent and hand
  positions/size from the sibling animator; `room_visuals.gd` reads
  `wall_segments()` + `wall_thickness` from its parent.

Ordering note: Godot runs a parent's `_physics_process` before its children's, so
the animator sees the control node's fresh `facing` on the same frame.

## Input architecture — the key pattern

**All input flows through the `Keybinds` autoload. Gameplay scripts never
hard-code action-name strings or `KEY_*` checks.** To add or change an input:

1. Add an action-name constant, e.g. `const PUNCH := "punch"`.
2. Add its default key to the `DEFAULTS` dict, e.g. `PUNCH: KEY_F`.
3. Expose a typed helper next to `get_move_vector()` /
   `is_punch_just_pressed()` so callers stay declarative.

`Keybinds._ready()` registers every action in `DEFAULTS` into the `InputMap` and
binds it to its default key, so `DEFAULTS` is the runtime source of truth even if
`project.godot` drifts. `rebind(action, keycode)` remaps any action at runtime
(the basis for a future key-config UI) — because F is a normal action, it is
rebindable exactly like the movement keys. The matching entries in
`project.godot [input]` exist only to keep the editor's Input Map panel in sync.

Consumers today:
- `player.gd` movement → `Keybinds.get_move_vector()`
- `player.gd` punch → `Keybinds.is_punch_just_pressed()`
- `player.gd` item selection → `Keybinds.get_selected_item()` (keys 1-9)

## Runtime-shape convention

Collision shapes are built **in code in `_ready()`**, not assigned in the scene:

- `room.gd._build_walls()` creates a `RectangleShape2D` collider per wall segment
  (layout depends on `size` (Vector2) / `openings`, so it must be data-driven).
  `openings` is an array of `{ side, offset, width }`; `offset` is the gap center
  along the wall from its start corner (top/bottom from the left, left/right from
  the top). `room_visuals.gd` draws the segments extended exactly like the colliders.
- `environment_object.gd` builds its collider only when `solid` is true; non-solid
  decor (rugs, mats) gets `z_index = -1` so it draws under furniture and the player.
- `player.gd` creates its body `CircleShape2D`; `player_animator.gd` creates the
  fist `Area2D` hitbox — both in `_ready()`.

**Because of this, the Godot editor shows "no shape" warnings on `Room` and
`Player/CollisionShape2D`. Those warnings are expected** — the shapes exist at
runtime. Don't "fix" them by adding scene shapes; they'd just be overwritten.

## Hands & punch feature

- **Facing:** `player.gd` updates `facing` each `_physics_process` to point from
  the player to the mouse, and sets `_animator.facing`. The player node is never
  rotated, so hand math stays in local space and movement/velocity are unaffected.
- **Hands:** two circles positioned via `player_animator.hand_position(hand)` from
  `facing` and its perpendicular — offset forward (past the body edge) and to each
  side. Tunable via the animator's `hand_*` / `punch_reach` `@export` vars;
  `player_visuals.gd` draws them with `hand_color`.
- **Punch:** `Keybinds.is_punch_just_pressed()` (in `player.gd`) calls
  `_animator.try_punch()`, which tweens the chosen hand's extension `0 → 1 → 0`
  (extend, then retract). `_next_hand` toggles each press so hands **alternate**.
- **Hit detection:** a runtime `Fist` `Area2D` (in the animator) tracks the
  punching hand. During the forward thrust (`_attack_active`), `_report_hits()`
  polls `get_overlapping_bodies()`, ignores the player body, dedupes per swing,
  prints the hit, and emits `signal punched(hand_index, body)`. Default collision
  layer 1 means it detects the room's static walls out of the box.

## Item system

Items are selectable via number keys (1–9) and define what the player can do.

- **Item data:** `player.gd._items` is a dict of item definitions:
  ```gdscript
  _items[1] = { name="Unarmed", reach=28.0, has_attack=false }
  _items[2] = { name="Fists", reach=28.0, has_attack=true, punch_hand=[0, 1] }
  _items[3] = { name="Pistol", reach=32.0, has_attack=true, punch_hand=1, weapon_hand=1, fires=true, damage=15.0 }
  ```
  - `has_attack` — whether F does anything.
  - `punch_hand` — an array alternates between those hands; an int always uses that
	hand. Read by `player_animator.try_punch()`.
  - `weapon_hand` — draw only that hand plus the item's weapon
	(`player_visuals._draw_weapon_for_item()`); without it, an item with an array
	`punch_hand` draws both hands, and anything else draws no hands.
  - `fires` — left-click fires a projectile (`player_animator.try_fire()`).
  - `damage` — the item's damage, added on top of the projectile's own base `damage`
	at fire time (`ProjectileSpawner.spawn`). The value dealt on each impact is that
	total scaled by how square the hit was (`|direction · surface_normal|`) **and** how
	fast the bullet was travelling (`speed / Config.projectile_speed`), so a fast
	head-on shot deals full damage while a glancing or slowed one deals less (a
	ricochet less still). A bullet is a multi-hit traveler (see "Projectile impact
	model"), so it may deal damage several times before it stops. Each damaging
	interaction is
	reported in a `Shot …` console line, the projectile's `hit` / animator's `shot`
	signals, and the debug HUD Hit log (which shows the latest).
- **Adding items:** Add an entry to `_items` in `player.gd._ready()`, and a draw
  case in `player_visuals._draw_weapon_for_item()` if it has a weapon.

## Projectile impact model

A fired bullet (`scenes/projectile/projectile.gd`) is **not** a stop-on-first-hit
pellet: it's a **multi-hit traveler** that sweeps forward each physics frame and
resolves every collider it crosses against that object's `coverage` / `penetration`
(0–100, from `environment_object.gd`; a collider without them — a room wall — falls
back to `Config.wall_coverage` / `wall_penetration`). It keeps flying until its
`speed` drops below `Config.projectile_min_speed` or it passes `max_distance`.
Non-solid decor (rugs) has no collider, so it's never even raycast.

Per hit, with squareness `s = |direction · normal|` (1 = head-on), speed factor
`v = speed / Config.projectile_speed` (incoming speed relative to the muzzle top
speed, so a fast shot hits harder), coverage `C` and penetration `P`, `_resolve()`
picks one outcome in order:

1. **Fly over** (coverage) — `flyover_chance = clamp((1 − C/100) × Config.cover_flyover_scale, 0, 1)`.
   On success: no damage, no deflection; the collider is excluded from further sweeps
   and the bullet flies on. Walls (C=100) are never flown over; low cover usually is.
2. **Ricochet** (hard + glancing) — when `P ≥ Config.penetration_bounce_min` **and**
   `s < Config.bounce_square_max`: deal `damage × s × v × Config.bounce_damage_retention`,
   reflect `direction` off the normal, `speed ×= Config.bounce_speed_retention`. The
   collider is **not** excluded (a bounced bullet may strike it again).
3. **Penetrate** (everything else) — only while `speed ≥ Config.penetration_min_speed`;
   deal `damage × s × v`, bleed speed by
   `loss = clamp((P/100) × Config.penetrate_loss_scale × (2 − s), 0, 1)` (more when
   glancing or when the material is hard) and deflect randomly up to
   `±Config.penetrate_deflect_max_deg × P/100`. The collider is excluded and the
   bullet flies on. Head-on hits on hard material collapse speed past the floor in a
   hit or two, so walls naturally stop bullets.
   - **Blocked** — if the bullet reaches the penetrate case but is moving slower than
     `Config.penetration_min_speed`, it can't punch through: it deals the impact
     `damage × s × v` and then stops (speed zeroed → the loop frees it). This is why the
     muzzle speed is set to double the penetration floor — penetration only happens in
     the upper half of the speed range, and a slowed bullet embeds instead of passing
     through.

Console logs stay in the `Shot …` family: `flew over`, `ricocheted off … for N
damage (M% square)`, `penetrated … for N damage (M% square)`, `blocked by … for N
damage (M% square)`. All the tuning knobs
above live in the `Config` autoload (`scenes/world/config.gd`); the `hit(body, damage)`
signal contract is unchanged — the projectile just emits it once per damaging
interaction now, so downstream (`player_animator`, `debug_ui`) needs no change.

## House generation

At startup `main.gd` picks one of the `HouseDefinitions` floorplans at random
(`HouseDefinitions.get_all()`) and spawns it so its front door sits `door_distance` px
straight above the player. There are 12 plans ranging from a `studio_flat` up to an
8-room `luxury_home` (`starter_home`, `open_plan_home`, `studio_flat`, `one_bed_flat`,
`two_bed_flat`, `family_home`, `office_loft`, `dining_house`, `bungalow`,
`garage_home`, `cottage`, `luxury_home`). The chosen plan and seed are printed
(`House: <plan>  seed: N`); set `house_seed` on `Main` to reproduce a layout, or
`force_plan` to pin a specific floorplan. All randomness flows through that one
`RandomNumberGenerator` (the plan pick is its first draw), so a seed reproduces the
whole run.

Pipeline (all in `scenes/builder/`, static `class_name` helpers, data kept separate):

```
HouseDefinitions (floorplans) ─┐
ArrangementDefinitions ────────┼─> HouseSpawner ─> RoomSpawner.spawn_from (walls)
ObjectDefinitions (catalogue) ─┘                └> RoomFurnisher ─> ObjectSpawner
```

`ObjectDefinitions` and `ArrangementDefinitions` are now thin **aggregators**: they
merge the per-category catalogs in `scenes/builder/categories/` (see file layout)
into cached lookups and expose the same `get_definition` / `get_arrangement` /
`get_recipe` API, so callers are unchanged. The actual object/arrangement/recipe data
lives in the category files, with cross-category entries in `GeneralCatalog`.

- **Floorplans** (`house_definitions.gd`): rooms are house-local `Rect2`s with a
  `type`; doors are points on wall lines. `HouseSpawner` cuts each door into every
  room wall passing through it (so shared walls get the gap on both sides), keeps a
  clearance box around each doorway free of furniture, and mirrors the plan
  left/right 50% of the time. Exactly one door must be `front`. `HouseSpawner._validate`
  `push_warning`s (author aid, warnings only) on overlapping rooms, a door not on a
  shared wall, and any room unreachable from the front door.
- **Arrangements** (`ARRANGEMENTS` const in each `categories/*.gd`): pre-designed
  furniture groups (TV wall, dining set, bed + nightstands…). Author each **as if
  against the top wall**: `x` along the wall, `y` depth into the room, item `pos` =
  item center, `rotated` = 90° turn. `placement` is `"wall"` or `"center"`;
  `prefer_corner` tries wall ends first; `tags` stop duplicates (e.g. one `"fridge"`
  per room). An arrangement used by 2+ categories lives in `GeneralCatalog`.
- **Recipes** (`RECIPES` const in each `categories/*.gd`): one per room type — `living_room`,
  `kitchen`, `bedroom`, `bathroom`, `kitchen_living` (combined great room), plus
  `dining_room`, `home_office`, `kids_room`, `entry_hall`, `laundry_room`, `garage`,
  and `studio` (a self-contained flat: lounge + kitchenette + bed). Each is ordered
  `zones`, every zone picking `count` arrangements from `options`, plus a list of
  `palettes` (colors drawn from `GeneralCatalog.WOOD` / `.FABRIC`). One palette is
  picked per room and recolors every `"wood"` / `"fabric"` object, so zones in a room
  match while rooms and runs differ. The combined `kitchen_living` and `studio`
  recipes live in `GeneralCatalog`; each single-category recipe lives in its own
  catalog file. A zone may set
  `"required": true` (warns if nothing fits) and `"fallback": "<arrangement>"` — a
  guaranteed-small arrangement placed only when none of the normal (larger) options
  fit, so essentials still appear in tight rooms.
- **Placement** (`room_furnisher.gd`): each arrangement's footprint is fitted
  against a random wall at a random offset (or free-standing for `"center"`),
  rotated onto that wall and randomly mirrored, without overlapping other
  arrangements or door clearances. A required zone that places nothing tries its
  `fallback`, then `push_warning`s if that also fails.
- **Objects** (`OBJECTS` const in each `categories/*.gd`): `material` and `solid` are
  optional. Label color is picked automatically for contrast. An object used by 2+
  categories lives in `GeneralCatalog`.

To add an arrangement or object, add it to the matching `categories/*.gd` catalog
(or `general.gd` if 2+ categories use it) and list arrangements in a recipe zone. To
add a room type, add a `categories/<type>.gd` catalog with its recipe (or add the
recipe to an existing catalog) and use its key as a room `type` in a floorplan. New
`class_name` scripts only resolve after Godot rescans the project (open the editor,
or run `godot --headless --path . --import`).

## Running & verifying

- Main scene: `res://scenes/main.tscn`. Use the `godot-debug` skill
  (`.claude/skills/godot-debug/`) for a headless error check.
- **House:** on start the house is directly ahead (up) of the player with the front
  door beside them; every doorway is walkable. Relaunch for a different layout.
- **Movement:** WASD moves; the hands orbit toward the mouse.
- **Item switching:** **1** unarmed (no hands, F does nothing) · **2** fists (both
  hands, F alternates) · **3** pistol (right hand + pistol, F jabs with that hand).
- **Attacks:** punch a wall or piece of furniture → `Punch (hand N) hit: <name>`
  prints, `punched` fires and the debug HUD shows the hit.
