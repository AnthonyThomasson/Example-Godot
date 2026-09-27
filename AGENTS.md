# AGENTS.md — Example_Godot architecture

A small top-down Godot 4.4 demo: a circle you drive with WASD inside a square
room, with two "hands" that aim at the mouse and a punch on **F**. This file
explains the conventions so future changes stay consistent.

## Scene / file layout

- `scenes/main.tscn` — root `Node2D` (`main.gd`). Contains:
  - `Room` — `StaticBody2D` (`room.gd`), the square walls.
  - `Player` — `CharacterBody2D` (`player.gd`), with a child `CollisionShape2D`.
  - `Label` — on-screen hint text.
- `scenes/keybinds.gd` — autoloaded as **`Keybinds`** (see `project.godot`
  `[autoload]`). The single source of truth for input.
- `project.godot` — project config; the `[input]` map mirrors `Keybinds`.

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

## Runtime-shape convention

Collision shapes are built **in code in `_ready()`**, not assigned in the scene:

- `room.gd._build_walls()` creates a `RectangleShape2D` collider per wall segment
  (layout depends on `size` / `opening_side`, so it must be data-driven).
- `player.gd` creates its body `CircleShape2D` and the fist `Area2D` hitbox in
  `_ready()`.

**Because of this, the Godot editor shows "no shape" warnings on `Room` and
`Player/CollisionShape2D`. Those warnings are expected** — the shapes exist at
runtime. Don't "fix" them by adding scene shapes; they'd just be overwritten.

## Hands & punch feature (`player.gd`)

- **Facing:** `_facing` is updated each `_physics_process` to point from the
  player to the mouse. The player node is never rotated, so `_draw()` uses
  `_facing` directly in local space and movement/velocity are unaffected.
- **Hands:** two circles positioned via `_hand_position(hand)` from `_facing` and
  its perpendicular — offset forward (past the body edge) and to each side.
  Tunable via the `hand_*` / `punch_reach` `@export` vars.
- **Punch:** `is_punch_just_pressed()` triggers `_start_punch()`, which tweens
  the chosen hand's extension `0 → 1 → 0` (extend, then retract). `_next_hand`
  toggles each press so hands **alternate**.
- **Hit detection:** a runtime `Fist` `Area2D` tracks the punching hand. During
  the forward thrust (`_attack_active`), `_report_hits()` polls
  `get_overlapping_bodies()`, ignores `self`, dedupes per swing, prints the hit,
  and emits `signal punched(hand_index, body)`. Default collision layer 1 means
  it detects the room's static walls out of the box.

## Running & verifying

- Main scene: `res://scenes/main.tscn`.
- Move with WASD; the hands orbit to stay between the player and the cursor.
- Press F to jab (alternating hands) toward the cursor.
- Punch into a wall → a `Punch ... hit:` line prints and `punched` fires.
