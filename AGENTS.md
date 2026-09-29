# AGENTS.md — Example_Godot architecture

A small top-down Godot 4.4 demo: a circle you drive with WASD around a procedurally
furnished house, with two "hands" that aim at the mouse, a punch on **F**, and a
pistol that fires on left-click. The code is organized into **seven isolated domains**
so each can be changed on its own. This file explains the domains and the small set of
interfaces that connect them — keep changes inside a domain, and cross a boundary only
through the interfaces listed here.

**After any code edit, follow the `doc-comments` skill** (`.claude/skills/doc-comments/`):
comments must describe the current state (no history), every method and property gets a
short description, and inline comments are reserved for genuinely tricky logic.

## The seven domains (one folder each under `scenes/`)

| Domain | Folder | Owns |
|---|---|---|
| **World Generation** | `worldgen/` | Picking a floorplan and building/furnishing a house. |
| **Objects** | `objects/` | The world's objects (furniture + walls): their data and how they're hit/pushed. |
| **Items** | `items/` | The things the character holds and the actions they perform. |
| **Character** | `character/` | The player character (built so other character types can exist). |
| **Projectile System** | `projectile/` | Shooting: penetration, damage, cover, ricochet. |
| **Physics System** | `physics/` | Physical reactions: forces, knockback, deformation, debris. |
| **General** | `general/` | Everything else: input (Keybinds), despawner, camera, debug HUD. |

`scenes/main.gd` (`main.tscn`) is the **composition root** — the only file that knows
every domain. It asks World-Gen for a house and holds the player. `project.godot`
autoloads only `Keybinds` and `Despawner` (both General).

## The vital interfaces (this is the whole cross-domain surface)

Everything not listed here is private to its domain.

1. **Main → World Generation**
   `WorldGen.generate(seed, force_plan, front_door_world, parent) -> Node2D`
   Seeds one RNG for the whole run (plan pick is its first draw), prints
   `House: <plan>  seed: N`, builds the house. `main.gd` only positions the front door
   and fixes draw order.

2. **World Generation → Objects** (the only way world-gen makes entities)
   - `ObjectFactory.spawn(definition: Dictionary, position, parent, opts) -> Node`
   - `WallFactory.spawn(rect: Rect2, thickness, openings, name, parent) -> Node`
   - `Wall.Side` — enum used when building `openings`.
   World-Gen owns the *catalogue* (which furniture/arrangements/recipes exist); Objects
   owns the *field schema* and turns a plain definition dict into a node. World-Gen never
   touches an object's fields.

3. **Objects ↔ strikers: the "hittable" contract**
   Every world object (furniture **and** walls) implements:
   - `get_surface() -> Dictionary` → `{ coverage, penetration, material, color }`
   - `take_hit(hit: HitInfo) -> void`
   `HitInfo` (`physics/hit_info.gd`) carries `position, normal, direction, damage,
   speed_factor, penetrated, source`. The projectile decides the ballistic outcome, then
   hands the object a HitInfo; the object decides what a hit *does to it* (shove + deform +
   debris). The projectile is the only striker that uses this; a melee punch shoves through
   the "pushable" contract below and does **not** deform.

4. **Objects → Physics** (objects compose physics; Physics is a leaf domain)
   - `Knockback` (Node child): RigidBody2D adapter — configures its parent body (no gravity,
     `mass`, damping, origin-pinned center of mass) and owns `apply_impulse(v, at_world)`,
     which feeds the engine a central or off-center (spinning) impulse.
   - `Deformable` (Node child): `record(hit)`, `impacts`, `damage_total`, `changed` signal.
   - `Deformation` (static): silhouette/collider polygons + drawing.
   - `Physics.impact_impulse(hit) -> Vector2` and `Physics.spawn_debris(world, hit, surface)`.
   Physics imports nothing from other domains.

5. **"Pushable" contract** — anything shoveable exposes `apply_impulse(v)` + `get_mass()`.
   Furniture is a `RigidBody2D`, so its native methods serve the contract (the engine
   integrates motion, collisions, pivoting and settling); the character integrates knockback
   into locomotion. Used by furniture→character contact transfers, bullet impacts, melee
   punches (a range-of-motion-scaled central shove), and the walking character.

6. **Items ↔ Character**
   `Item` (`items/item.gd`): `display_name`, `reach`, `visible_hands()`, `primary(user)`
   (F), `secondary(user)` (LMB), `draw_weapon(canvas, user)`. `ItemRegistry.create(id)` /
   `default_inventory()`. The character API an item may call: `facing`, `punch(hand)`,
   `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`,
   `report_shot(body, dmg)`. The pistol is the one place Items reach into the Projectile
   System (`ProjectileSpawner`/`CasingSpawner`).

7. **Character ↔ Controller** (enables non-player characters)
   The character reads intent from a pluggable **controller child** — any node with
   `control(character, delta)`. `player_controller.gd` is the human one and is the ONLY
   file besides `keybinds.gd` that touches `Keybinds`. Signals: `hit_landed(body, damage,
   hand)` (hand 0/1 = melee punch, hand −1 = shot; `damage` is the amount dealt) and
   `item_changed(item)`. Observers
   (debug HUD, camera) attach by exported node path and read only the public API/signals.

### Dependency graph (arrows = "calls / knows"; no cycles)

```
main ─▶ WorldGen ─▶ ObjectFactory / WallFactory ─▶ Objects ─▶ Physics
main ─▶ Character ◀─ PlayerController ─▶ Keybinds
Character ─▶ Item ─▶ ProjectileSpawner ──(get_surface / take_hit)──▶ Objects
Physics debris / casings ─▶ Despawner
DebugUI / Camera ──(exported path + signals)──▶ Character
```
Physics and World-Gen are leaves (World-Gen's only outward code dep is `Wall.Side` +
the two factories). Tuning is split into three `class_name` static holders:
`BallisticsConfig` (projectile), `PhysicsConfig` (impact + deformation), `CharacterConfig`
(walking push + punch). There is no `Config` autoload.

## Layered structure — control / animate / draw

Within an entity, the three verbs live in separate files, wired via the scene tree
(no `class_name` on scene scripts; cross-file calls resolve through `$` / `get_parent()`).
A "draw" file is attached to its own child `Node2D` (Godot only draws from `CanvasItem`s).

- **Control** (root body node) owns state + physics and orchestrates; it never draws.
  `character.gd` computes `facing`, moves, and forwards intent from its controller.
  `wall.gd` owns the wall-segment math (`wall_segments()`) and colliders.
- **Animate** (`character_hands.gd`, a child `Node2D`) owns hand geometry, the punch
  tween, and punch hit detection (a shape query at the raw fist position); exposes
  `hand_position(i)` and the `punched` signal.
- **Draw** (`*_visuals.gd`) own appearance only. `character_visuals.gd` draws the body,
  the hands the held item wants shown, then `item.draw_weapon()`. `environment_object_visuals`
  / `wall_visuals` read the deformed geometry from their control node.

Ordering: a parent's `_physics_process` runs before its children's, so the hands see the
character's fresh `facing`, and the character pulls its controller's intent at the top of
its own `_physics_process` (lag-free).

## Input architecture

All input flows through the `Keybinds` autoload; gameplay never hard-codes action strings
or `KEY_*`. To add/change an input: add an action constant, add its default to `DEFAULTS`,
and expose a typed helper. Only `player_controller.gd` consumes Keybinds. `rebind()` /
`rebind_mouse()` remap at runtime (basis for a future config UI). `project.godot [input]`
just keeps the editor's Input Map panel in sync.

## Runtime-shape convention

Collision shapes are built **in code in `_ready()`**, not in the scene:
- `wall.gd._build_walls()` — a `RectangleShape2D` per wall segment (layout is data-driven
  from `size`/`openings`). `openings` are `{ side, offset, width }`.
- `environment_object.gd` (a `RigidBody2D`) builds its collider only when `solid`; non-solid
  decor is `freeze`d (no shape) and gets `z_index = -1`.
- `character.gd` builds its body `CircleShape2D`; `character_hands.gd` builds the fist
  query `CircleShape2D`. Physics components (`Knockback`, `Deformable`) are added as child Nodes in
  `environment_object._ready()`.

**Because of this, the editor shows "no shape" warnings on `Player/CollisionShape2D` and
on each `Wall`. Those are expected** — the shapes exist at runtime; don't add scene shapes.

## Character, hands & items

- **Facing:** `character.gd` points `facing` from itself to `aim_point` (the mouse, set by
  the controller) each frame. The node is never rotated, so hand math stays in local space.
- **Hands:** two circles positioned from `facing` + its perpendicular, collision-resolved so
  they rest on walls/objects. Tunable via `character_hands.gd`'s `hand_*` exports.
- **Items:** number keys 1–9 select a slot (`ItemRegistry`). **1** unarmed (no hands, F/LMB
  do nothing) · **2** fists (both hands, F alternates — alternation state lives in the item)
  · **3** pistol (right hand + pistol art; F jabs, LMB fires). Add an item by writing an
  `Item` subclass in `items/` and a case in `ItemRegistry`.
- **Punch hit detection:** during a swing `character_hands.gd` runs a shape query
  (`intersect_shape`) at the fist's *raw* punch position — which extends into what is hit,
  unlike the drawn hand that rests on the surface — and dedupes per swing. Each new hit shoves
  the body via the "pushable" contract (`apply_impulse`) and deals damage, both scaled by the
  swing's range of motion — how fast the fist is moving this frame (1.0 = full-speed extend).
  It emits `punched(hand, body, damage)` → the character re-emits `hit_landed(body, damage,
  hand)`. A punch pushes but never deforms; walls (no `apply_impulse`) take damage without
  moving. Tuned by `CharacterConfig.punch_impulse`/`punch_damage`.

## Projectile impact model

A fired bullet (`projectile.gd`) is a **multi-hit traveler**: each physics frame it sweeps
forward with a raycast and resolves every collider it crosses against that object's
`get_surface()` `coverage`/`penetration` (0–100; a collider with no surface uses
`BallisticsConfig.wall_*`). It flies until `speed < BallisticsConfig.projectile_min_speed`
or it passes `max_distance`. Non-solid decor has no collider, so it's never raycast.

Per hit, with squareness `s = |dir·normal|`, speed factor `v = speed / muzzle_speed`,
coverage `C`, penetration `P`, `_resolve()` picks one outcome in order:
1. **Fly over** — `clamp((1 − C/100) × cover_flyover_scale, 0, 1)`; no damage, excluded, flies on.
2. **Ricochet** (`P ≥ penetration_bounce_min` and `s < bounce_square_max`) — reflects,
   `speed ×= bounce_speed_retention`, deals `damage × s × v × bounce_damage_retention`.
3. **Penetrate** (else, while `speed ≥ penetration_min_speed`) — deals `damage × s × v`,
   bleeds speed, deflects slightly. **Blocked** if too slow: deals the impact and embeds.

On any *damaging* outcome the projectile packages a `HitInfo` and calls `body.take_hit(info)`
(the object then shoves/deforms/sprays via Physics) and re-emits `hit(body, damage)` — which
the pistol forwards to the character's `hit_landed`. Console lines: `Shot flew over / ricocheted
off / penetrated / blocked by …`. All knobs live in `BallisticsConfig`.

## Physics System

Stateless helpers + reusable Node components, sharing no imports with other domains:
- `HitInfo` — the one data packet a striker fills in.
- `Physics.impact_impulse(hit)` / `Physics.spawn_debris(world, hit, surface)`.
- `Knockback` — RigidBody2D adapter: configures its parent furniture body (no gravity, mass,
  `PhysicsConfig.body_*` damping, origin-pinned center of mass, contact reporting) and feeds it
  impulses via `apply_impulse(v, at_world)`. The engine does the sweeping, pivoting and settling;
  the component only hands momentum to the kinematic character on contact (`impact_transfer_scale`).
- `Deformable` — records local impacts (dents / carved "missing pieces") and emits
  `changed`; the owner redraws + rebuilds its collider from the same deformed polygon.
- `Deformation` — the polygon math + drawing (shared by furniture and walls).
- `DebrisSpawner` / `Debris` — material-styled chips (`STYLES` table). `PhysicsConfig` tunes
  it all; the global cap lives on `Despawner`.

## House generation (World Gen pipeline)

`WorldGen.generate` picks one of the `HouseDefinitions` floorplans (12, `studio_flat` …
`luxury_home`) and hands it to `HouseSpawner`:

```
HouseDefinitions (floorplans) ─┐
categories/*  (catalogues)  ───┼─▶ HouseSpawner ─▶ WallFactory (walls, doors cut in)
ObjectDefinitions / ───────────┘                └▶ RoomFurnisher ─▶ ObjectFactory
ArrangementDefinitions
```

- **Floorplans** (`house_definitions.gd`): rooms are house-local `Rect2`s with a `type`;
  doors are points on wall lines. `HouseSpawner` cuts each door into every wall through it,
  keeps door clearances free of furniture, and mirrors the plan L/R 50% of the time.
- **Catalogues** (`worldgen/categories/*.gd`, one `<Name>Catalog` per room type; `general.gd`
  holds shared entries + the `WOOD`/`FABRIC` palettes + combined recipes). Hold `OBJECTS`,
  `ARRANGEMENTS`, `RECIPES`. `ObjectDefinitions` / `ArrangementDefinitions` are thin
  aggregators that merge them and expose `get_definition` / `get_arrangement` / `get_recipe`.
- **Arrangements** are authored against the top wall (`x` along, `y` depth); `placement`
  `"wall"`/`"center"`, `prefer_corner`, `tags` (dedupe). **Recipes** list ordered `zones`
  (each picks `count` from `options`, with optional `required`/`fallback`) + `palettes`.
- **Placement** (`room_furnisher.gd`) fits each arrangement's footprint against a random wall
  without overlap, rotates/mirrors it, then hands each object's definition to `ObjectFactory`.

To add a room type: add a `categories/<type>.gd` catalog with its recipe and use its key as a
room `type`. New `class_name` scripts resolve only after Godot rescans (open the editor or run
`godot --headless --path . --import`).

## Running & verifying

- Main scene `res://scenes/main.tscn`. Use the `godot-debug` skill for a headless check
  (`godot --headless --path . --quit-after 30`, grep for `SCRIPT ERROR|Parse Error|ERROR:`);
  run `--import` first when you add a `class_name`.
- **House:** on start the house is directly ahead of the player, front door beside them; every
  doorway is walkable. `house_seed`/`force_plan` on `Main` pin a layout.
- **Movement/pushing:** WASD moves; heavy furniture slows you and shoves you back.
- **Items:** **1** unarmed · **2** fists (F alternates) · **3** pistol (F jabs, LMB fires).
- **Combat:** punch or shoot furniture/walls → console lines print, debris sprays, objects
  dent + shove, and the debug HUD shows the last hit + damage.
