---
name: architecture
description: The architecture map for this Godot project (Example_Godot) — the eleven isolated domains, the cross-cutting conventions, the whole sanctioned cross-domain interface surface, and the dependency graph. Load this BEFORE planning any change or exploring the codebase, and whenever you need to know where something lives or how two domains are allowed to talk. Points to each domain's `domain-<name>` skill for that domain's deep implementation detail.
---

# Example_Godot architecture

A small top-down Godot 4.4 demo: a circle you drive with WASD around a procedurally
furnished house, with two "hands" that aim at the mouse, a punch on **F**, a pistol that
fires on left-click, and object interactions on **Space** (sit, lie, …). The code is
organized into **eleven isolated domains** so each can be changed on its own.

This skill is the **map**: the domains, the sanctioned cross-domain surface (the vital
interfaces), and the dependency graph. Keep changes inside a domain, and cross a boundary only
through the interfaces listed here. **When working *inside* a domain, also load its
`domain-<name>` skill** — that is where the deep implementation detail lives.

**Before committing a change, run the `analysis-change-verification` skill**: it checks that domains stay
isolated (cross-domain connections go only through the interfaces below), keeps this skill *and
the domain skills* in sync when the architecture or a domain's internals change, and enforces
concise current-state comments.

## The eleven domains (one folder each under `scenes/`)

| Domain | Folder | Skill | Owns |
|---|---|---|---|
| **World Generation** | `worldgen/` | `domain-worldgen` | Picking a floorplan and building/furnishing a house. |
| **Objects** | `objects/` | `domain-objects` | The world's objects (furniture + walls): their data and how they're hit/pushed. |
| **Items** | `items/` | `domain-items` | The things the character holds and the actions they perform. |
| **Character** | `character/` | `domain-character` | The player character (built so other character types can exist). |
| **Interaction** | `interaction/` | `domain-interaction` | Object interactions: finding a reachable object and running one of its actions (sit, lie, …). |
| **Projectile System** | `projectile/` | `domain-projectile` | Shooting: penetration, damage, cover, ricochet. |
| **Physics System** | `physics/` | `domain-physics` | Physical reactions: forces, knockback, deformation, debris. |
| **Navigation** | `navigation/` | `domain-navigation` | Baking the house into a walkable nav map so characters can path around walls. |
| **General** | `general/` | `domain-general` | Infrastructure: input (Keybinds), despawner, camera, dev command server. |
| **UI** | `ui/` | `domain-ui` | All HUDs and menus: debug player panel, match HUD, pre-game setup window, seed readout. |
| **AI** | `ai/` | `domain-ai` | Non-player brains: one generic controller that drives every NPC. Internally split into four isolated **sub-domains** under `ai/` — perception (`ai/perception/`), decision (`ai/decision/`), behaviour (`ai/behavior/`), debug (`ai/debug/`) — around a thin orchestrator (`ai/goal_controller.gd`). `domain-ai` is the overview; each sub-domain has a `domain-ai-<name>` skill. |

`scenes/main.gd` (`main.tscn`) is the **composition root** — the only file that knows every
domain. It asks World-Gen for a house and holds the player. `project.godot` autoloads only
`Keybinds`, `Despawner` and `EventBus` (all General).

On a fresh launch Main opens the UI setup window and builds nothing until Start, then **awaits the
AI domain's `DecisionServerLauncher.resolved(live)`** before `_spawn_world()`, so no NPC makes its
first decision against a still-booting Von server. That launcher is a root node of `main.tscn`, so
it begins probing/launching at scene load and usually resolves while the window is still open (no
delay); it always resolves, so a run with no server still starts, with NPCs that hold steady.

## The vital interfaces (this is the whole cross-domain surface)

Everything not listed here is private to its domain. Each domain's skill recaps its own
interface(s) and describes how they're implemented; this list is authoritative for signatures.

1. **Main → World Generation**
   - `WorldGen.generate(seed, force_plan, front_door_world, parent, spawn_doors=true) -> Node2D` — seeds one RNG
	 for the whole run (plan pick is its first draw), prints `House: <plan>  seed: N`, builds
	 the house.
   - `WorldGen.get_rooms(house) -> Array` — the house's rooms as `{ key, type, rect }` dicts
	 (world-space `rect`), read from the house's `rooms` metadata.
   `main.gd` positions the front door, fixes draw order, builds the nav map from the rooms
   (interface 9), drops the defender NPC into a random room and the invader NPC just outside the
   house (all via `get_rooms`); it never touches
   world-gen internals.

2. **World Generation → Objects** (the only way world-gen makes entities)
   - `ObjectFactory.spawn(definition: Dictionary, position, parent, opts) -> Node`
   - `WallFactory.spawn(rect: Rect2, thickness, openings, name, parent) -> Node`
   - `Wall.Side` — enum used when building `openings`.
   World-Gen owns the *catalogue*; Objects owns the *field schema* and turns a plain definition
   dict into a node. World-Gen never touches an object's fields.

3. **Objects ↔ strikers: the "hittable" contract**
   Every world object (furniture **and** walls) implements:
   - `get_surface() -> Dictionary` → `{ coverage, penetration, material, color }`
   - `take_hit(hit: HitInfo) -> void`
   `HitInfo` (`physics/hit_info.gd`) carries `position, normal, direction, damage,
   speed_factor, penetrated, source`. The projectile decides the ballistic outcome, then hands
   the object a HitInfo; the object decides what a hit *does to it*. The projectile is the only
   striker that uses this; a melee punch shoves through the "pushable" contract below and does
   **not** deform.

4. **Objects → Physics** (objects compose physics; Physics is a leaf domain)
   - `Knockback` (Node child): RigidBody2D adapter — configures its parent body and owns
	 `apply_impulse(v, at_world)`.
   - `Deformable` (Node child): `record(hit)`, `impacts`, `damage_total`, `changed` signal.
   - `Deformation` (static): silhouette/collider polygons + drawing.
   - `Physics.impact_impulse(hit) -> Vector2` and `Physics.spawn_debris(world, hit, surface)`.
   Physics imports nothing from other domains.

5. **"Pushable" contract** — anything shoveable exposes `apply_impulse(v)` + `get_mass()`.
   Furniture is a `RigidBody2D`, so its native methods serve the contract; the character
   integrates knockback into locomotion. Used by furniture→character contact transfers, bullet
   impacts, melee punches, and the walking character.

6. **Items ↔ Character**
   `Item` (`items/item.gd`): `display_name`, `reach`, `visible_hands()`, `primary(user)` (F),
   `secondary(user)` (LMB), `draw_weapon(canvas, user)`. `ItemRegistry.create(id)` /
   `default_inventory()`. The character API an item may call: `facing`, `punch(hand)`,
   `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`,
   `report_shot(body, dmg)`. The pistol is the one place Items reach into the Projectile System
   (`ProjectileSpawner`/`CasingSpawner`).

7. **Character ↔ Controller** (enables non-player characters)
   The character reads intent from a pluggable **controller child** — any node with
   `control(character, delta)`. The controller writes `move_input` / `aim_point` and calls the
   character's action API: `melee()` (F), `shoot()` (LMB), `select_slot(id)`, `try_interact()` /
   `interact_with(object, id)` / `end_interaction()`, and may read `damage_taken()` (accumulated hit
   damage, for injury sensing) and `faction` (allegiance tag, for AI hostility). The AI also reads
   another character's `facing` and `damage_taken()` — but only while it can SEE that character
   (aim and visible wounds are things it perceives).
   `player_controller.gd` is the human one and
   is the ONLY file besides `keybinds.gd` that touches `Keybinds`. Signals:
   `hit_landed(body, damage, hand)` (hand 0/1 = melee punch, hand −1 = shot), `item_changed(item)`
   and `interaction_changed(active, label)`. Observers (debug HUD, match HUD, camera) attach by
   exported node path and read only the public API/signals; the controller also exposes
   `current_act()` (its live decision path as ids, e.g. `combat/t_12/flank/side_left`) and
   `debug_status()` (the same path as labels, every level: `COMBAT - Intruder - FLANK - their left
   side (kitchen)`) for those observers to show. Every NPC is the same generic goal-driven agent
   driven by `ai/goal_controller.gd`; the defender (`character/npc_defender.tscn`) and the invader
   (`character/npc_invader.tscn`, an inherited scene) differ only in data authored on the scene —
   a plain-language `goal` plus generic primitives (hostility rules, pursuit, territory) and
   decision-tree config. Main injects only `rooms` (and `entry_point`); the AI finds and categorizes
   the characters it perceives by sight. Von walks a data-driven DECISION TREE ranked against the
   goal — a broad mode (combat / investigate / search / idle), then a tactic (engage / flank / push /
   retreat / locate …), then a concrete option (a place, a firing spot, an object) — one `choice`
   request per level, ending in a behaviour primitive (move / engage / melee / interact / hold) — no
   per-goal or per-NPC-type code. `goal_controller.gd` is only the thin orchestrator; the work is split
   across four isolated AI sub-domains (perception / decision / behaviour / debug). See the `domain-ai`
   overview and its `domain-ai-<name>` sub-skills.

8. **Interaction ↔ Character & Objects** (kept deliberately isolated so it iterates alone)
   The character composes a `CharacterInteraction` component (`interaction/`) and exposes only
   opaque forwards: `try_interact()` (the player's **Space** toggle), `interactions_in_reach()`
   and `interact_with(object, id)` / `end_interaction()` (for a controller/AI), `is_busy()`
   (movement/actions lock) and `interaction_label()` (HUD). It discovers objects through the
   **interactable contract** — every world object implements `get_interactions() -> Array` (plain
   data dicts: `id`, `label`, optional `move_to` / `requires_item`), advertised via the optional
   `interactions` object field. The character never learns what an interaction *means*.

9. **Main / AI → Navigation** (leaf: builds the map, everyone else just pathfinds)
   - `NavBuilder.build(house, rooms, parent, agent_radius=14.0) -> NavigationRegion2D` — bakes
	 one `NavigationRegion2D` whose walkable area is the house footprint plus an outdoor ring minus the house's
	 **static** wall colliders (doorways stay open) **and minus each solid furniture footprint**
	 (baked in as a hole), so paths route around furniture.
   - `NavBuilder.furniture_holes(house) -> Array` — the carved furniture footprints as world-space
	 polygons, which Main snapshots for the `nav_debug.gd` debug overlay (draw-only).
   `main.gd` calls `build` once after `WorldGen.generate` (and builds the `nav_debug.gd` overlay right
   after). Any `NavigationAgent2D` then pathfinds
   against the global map automatically — the AI's locomotion sets `target_position` and steers at
   `get_next_path_position()`. It does **not** enable RVO avoidance: a displaced piece of furniture is
   simply bulldozed by the character's push physics.

10. **Any domain ↔ General (EventBus)** — a generic decoupled notification bus (General autoload).
    - `EventBus.post(topic: StringName, data: Dictionary)` — broadcast an event.
    - `signal posted(topic, data)` — listeners connect and filter by `topic`.
    Two topics are in use:
    - `&"hit"`: the Projectile System posts one per damaging hit and the Character one per landed
      punch (`{ position, victim, source, direction, damage, attacker }`; `attacker` = the striking
      character or null). The AI controller consumes it for combat awareness, hostility ("attacked
      me") and gunfire heard farther off; the match HUD for its combat feed.
    - `&"callout"`: an AI controller posts one when it adopts a combat or investigation decision —
      its team radio (`{ speaker, faction, position, status, path, label, target_id, point }`). Allied
      AI controllers within `callout_range` consume it (which flank an ally holds, whom it fights,
      where to support it).
    Emitters and listeners never reference each other (like `Despawner`).

### Dependency graph (arrows = "calls / knows"; no cycles)

```
main ─▶ WorldGen ─▶ ObjectFactory / WallFactory ─▶ Objects ─▶ Physics
main ─▶ NavBuilder ──(parses static colliders)──▶ NavigationServer2D
main ─▶ Character ◀─ PlayerController ─▶ Keybinds
Character ─▶ Item ─▶ ProjectileSpawner ──(get_surface / take_hit)──▶ Objects
Character ─▶ Interaction ──(get_interactions)──▶ Objects
AIController ─▶ NavigationAgent2D ─▶ NavigationServer2D   (writes Character.move_input; tactics query the nav map)
Physics debris / casings ─▶ Despawner
Projectile / Character ──(&"hit" events)──▶ EventBus ──(posted)──▶ AIController / MatchHUD
AIController ──(&"callout" events)──▶ EventBus ──(posted)──▶ allied AIControllers
UI (DebugUI / MatchHUD) / Camera ──(exported path + signals)──▶ Character  (MatchHUD also reads AIController.debug_status)
```

Physics, Navigation and World-Gen are leaves (World-Gen's only outward code dep is `Wall.Side` +
the two factories; Navigation depends only on Godot's `NavigationServer2D`). Tuning is split into
four `class_name` static holders: `BallisticsConfig` (projectile), `PhysicsConfig` (impact +
deformation), `CharacterConfig` (walking push + punch), and `BloodConfig` (blood pooling). There
is no `Config` autoload.

## Cross-cutting conventions

Two conventions hold across domains; the per-domain specifics live in each domain's skill.

- **Layered control / animate / draw.** Within an entity the three verbs live in separate files,
  wired via the scene tree (no `class_name` on scene scripts; cross-file calls resolve through
  `$` / `get_parent()`). A "draw" file is attached to its own child `Node2D` (Godot only draws
  from `CanvasItem`s). Ordering: a parent's `_physics_process` runs before its children's.
- **Runtime shapes.** Collision shapes are built **in code in `_ready()`**, not in the scene
  (layout is data-driven). Because of this the editor shows "no shape" warnings on
  `Player/CollisionShape2D` and on each `Wall` — **those are expected**; don't add scene shapes.

## Running & verifying

- Main scene `res://scenes/main.tscn`. Use the **`godot-debug` skill** for a headless load check
  (run `--import` first when you add a `class_name`) and the **`godot-drive` skill** for driving the
  running game via the dev command server (`tools/gcmd.py`).
- Use the **`analysis-change-verification` skill** before committing (domain isolation, doc/skill sync,
  comment hygiene, load check).
- The relevant **`domain-<name>` skill** documents each domain's behaviour to verify (house
  generation, movement/pushing, items, interactions, combat).
