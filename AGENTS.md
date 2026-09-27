# AGENTS.md — Example_Godot architecture

A small top-down Godot 4.4 demo: a circle you drive with WASD inside a square
room, with two "hands" that aim at the mouse and a punch on **F**. This file
explains the conventions so future changes stay consistent.

## Scene / file layout

Scripts are grouped by entity into folders, and each entity is split into
separate files by **responsibility — control / animate / draw** (see next
section). To have its own `_draw()`, a "draw" file is attached to its own child
`Node2D` (Godot only draws from `CanvasItem` nodes).

- `scenes/main.tscn` — root `Node2D` (`main.gd`). Tree:
  ```
  Main
	Label                                   on-screen hint text
	Room (StaticBody2D, room/room.gd)       CONTROL: segments + colliders
	  RoomVisuals (Node2D, room/room_visuals.gd)   DRAW: wall lines
	Player (CharacterBody2D, player/player.gd)     CONTROL: input, movement, facing
	  CollisionShape2D                      body collider (shape set at runtime)
	  PlayerAnimator (Node2D, player/player_animator.gd)  ANIMATE: punch + fist hits
	  PlayerVisuals  (Node2D, player/player_visuals.gd)   DRAW: body + hands
  ```
- `scenes/player/` — `player.gd`, `player_animator.gd`, `player_visuals.gd`.
- `scenes/room/` — `room.gd`, `room_visuals.gd`.
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
  (layout depends on `size` / `opening_side`, so it must be data-driven).
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

- **Item data:** `player.gd._items` is a dict of item definitions. Each entry has
  properties like `name`, `reach` (punch distance), and `has_attack` (whether F
  triggers an action). Example:
  ```gdscript
  _items[1] = { name="Unarmed", reach=28.0, has_attack=false }
  _items[2] = { name="Pistol", reach=32.0, has_attack=true }
  ```
- **Item 1 (unarmed):** No hands shown, F does nothing.
- **Item 2 (pistol):** Hands visible, a pistol shape drawn in the right hand, F
  triggers a melee punch with extended reach (32px vs. 28px unarmed).
- **Adding items:** Add an entry to `_items` in `player.gd._ready()`, optionally
  add a custom draw function in `player_visuals.gd._draw()`. The animator
  automatically uses the item's `reach` for punch extension. Each item can have a
  different attack reach without needing separate punch logic.

## Running & verifying

- Main scene: `res://scenes/main.tscn`.
- **Movement:** WASD moves; the hands orbit toward the mouse.
- **Item switching:**
  - Press **1** → unarmed (hands disappear, F does nothing).
  - Press **2** → pistol (hands appear, pistol drawn in right hand, F jabs).
  - Press **1** again → back to unarmed.
- **Attacks:** While equipped with an item that has `has_attack=true`, press F to
  jab toward the cursor. Punch into a wall → `Punch (hand N) hit: Room` prints and
  `punched` fires. Unarmed (item 1) has no attack, so F does nothing.
