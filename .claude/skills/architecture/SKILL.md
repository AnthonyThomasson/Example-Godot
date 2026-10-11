---
name: architecture
description: The architecture map for this Godot project (Example_Godot) — the thirteen isolated domains, the cross-cutting conventions, the whole sanctioned cross-domain interface surface, and the dependency graph. Load this BEFORE planning any change or exploring the codebase, and whenever you need to know where something lives or how two domains are allowed to talk. Points to each domain's `domain-<name>` skill for that domain's deep implementation detail.
---

# Example_Godot architecture

A small top-down Godot 4.4 demo: a circle you drive with WASD around a procedurally
furnished house, with two "hands" that aim at the mouse, a punch on **F**, a pistol that
fires on left-click, and object interactions on **Space** (sit, lie, …). The code is
organized into **thirteen isolated domains** so each can be changed on its own.

This skill is the **map**: the domains, the sanctioned cross-domain surface (the vital
interfaces), and the dependency graph. Keep changes inside a domain, and cross a boundary only
through the interfaces listed here. **When working *inside* a domain, also load its
`domain-<name>` skill** — that is where the deep implementation detail lives.

**Before committing a change, run the `analysis-change-verification` skill**: it checks that domains stay
isolated (cross-domain connections go only through the interfaces below), keeps this skill *and
the domain skills* in sync when the architecture or a domain's internals change, and enforces
concise current-state comments.

## The thirteen domains (one folder each under `scenes/`)

| Domain | Folder | Skill | Owns |
|---|---|---|---|
| **World Generation** | `worldgen/` | `domain-worldgen` | Picking a floorplan and building/furnishing a house. |
| **Objects** | `objects/` | `domain-objects` | The world's objects (furniture, walls, floors): their data, how they're hit/pushed, and their painters (what each piece looks like). |
| **Items** | `items/` | `domain-items` | The things the character holds and the actions they perform. |
| **Character** | `character/` | `domain-character` | The player character (built so other character types can exist). |
| **Interaction** | `interaction/` | `domain-interaction` | Object interactions: finding a reachable object and running one of its actions (sit, lie, …). |
| **Projectile System** | `projectile/` | `domain-projectile` | Shooting: penetration, damage, cover, ricochet. |
| **Physics System** | `physics/` | `domain-physics` | Physical reactions: forces, knockback, deformation, debris. |
| **Art** | `art/` | `domain-art` | The procedural pixel-art engine every painter draws through: the canvas, the cached renderer, the shared light/tone/surface tuning. |
| **Navigation** | `navigation/` | `domain-navigation` | Baking the house into a walkable nav map so characters can path around walls. |
| **General** | `general/` | `domain-general` | Infrastructure: input (Keybinds), saved settings (`Settings`), despawner, camera, dev command server, shared physics-layer ids (`PhysicsLayers`). |
| **UI** | `ui/` | `domain-ui` | All HUDs and menus: debug player panel, match HUD, pre-game setup window, settings page, seed readout, test browser window, test result banner. |
| **AI** | `ai/` | `domain-ai` | Non-player brains: one generic controller that drives every NPC. Internally split into four isolated **sub-domains** under `ai/` — perception (`ai/perception/`), decision (`ai/decision/`), behaviour (`ai/behavior/`), debug (`ai/debug/`) — around a thin orchestrator (`ai/goal_controller.gd`). `domain-ai` is the overview; each sub-domain has a `domain-ai-<name>` skill. |
| **Testing** | `testing/` | `domain-testing` | Game tests: a second composition root that builds a declared world (arena or generated house) with chosen behaviour switches, runs a test's script against it and asserts what happened; the in-game test browser + runner, and the headless CLI runner. Test cases live in `tests/<domain>/*_test.gd`. |

`scenes/main.gd` (`main.tscn`) is the **composition root** — with the Testing domain's runner
(interface 13), the only code that knows every domain. It asks World-Gen for a house and holds the
player; the setup window's **Tests** button sends it to the test browser instead. `project.godot` autoloads only
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
   - `WorldGen.generate(seed, force_plan, front_entrance_world, parent) -> Node2D` — seeds one RNG
	 for the whole run (plan pick is its first draw), prints `House: <plan>  seed: N`, builds
	 the house; every doorway is an open archway.
   - `WorldGen.get_rooms(house) -> Array` — the house's rooms as `{ key, type, rect }` dicts
	 (world-space `rect`), read from the house's `rooms` metadata.
   - Read-only catalogue lookups (used by the Testing domain to place single pieces):
	 `WorldGen.object_definition(key) -> Dictionary` (for `ObjectFactory.spawn`),
	 `WorldGen.floor_definition(key) -> Dictionary` (for `FloorFactory.spawn`) and
	 `WorldGen.wall_style() -> Dictionary` (the house wall `style` for `WallFactory.spawn`).
   `main.gd` positions the front entrance, fixes draw order, builds the nav map from the rooms
   (interface 9), drops the defender NPC into a random room and the invader NPC just outside the
   house (all via `get_rooms`); it never touches
   world-gen internals.

2. **World Generation → Objects** (the only way world-gen makes entities)
   - `ObjectFactory.spawn(definition: Dictionary, position, parent, opts) -> Node`
   - `WallFactory.spawn(rect: Rect2, thickness, openings, name, parent, style = {}) -> Node` —
	 `style` is the cap's look (`art`, `color`, `art_opts`); empty = a flat gray line.
   - `FloorFactory.spawn(rect: Rect2, definition: Dictionary, name, parent) -> Node` — a room's
	 floor (no collider), from a floor definition (`art`, `color`, `material`, `art_opts`).
   - `Wall.Side` — enum used when building `openings`.
   World-Gen owns the *catalogue*; Objects owns the *field schema* and turns a plain definition
   dict into a node. World-Gen never touches an object's fields.

3. **Objects/Character ↔ strikers: the "hittable" contract**
   Every world object (furniture **and** walls), **and the Character domain's `character.gd`**,
   implements:
   - `get_surface() -> Dictionary` → `{ coverage, penetration, material, color }`
   - `take_hit(hit: HitInfo) -> void`
   `HitInfo` (`physics/hit_info.gd`) carries `position, normal, direction, damage,
   speed_factor, penetrated, source`. The projectile decides the ballistic outcome, then hands
   the struck body a HitInfo; the body decides what a hit *does to it* — an object spawns debris
   (interface 4), the character spawns blood instead (`Physics.spawn_blood`, interface 4). The
   projectile is the only striker that uses this; a melee punch shoves through the "pushable"
   contract below and does **not** deform.

4. **Objects/Character → Physics** (objects and the character compose physics; Physics is a leaf domain)
   - `Knockback` (Node child): RigidBody2D adapter — configures its parent body and owns
	 `apply_impulse(v, at_world)`.
   - `Deformable` (Node child): `record(hit, turn = 0.0)`, `impacts`, `damage_total`, `changed`
	 signal (`turn`: the body's drawn turn beyond its node rotation; the character passes its facing).
   - `Deformation` (static): silhouette/collider polygons + drawing (`draw_shape` and
	 `draw_wall` optionally textured — `draw_shape` also turned by `texture_angle`, its hit marks
	 optional for a caller drawing them over later layers with `draw_marks` — so pixel art is drawn
	 through the dented silhouette).
   - `Physics.impact_impulse(hit) -> Vector2`, `Physics.spawn_debris(world, hit, surface)` (objects)
	 and `Physics.spawn_blood(...)` (character, on a hit), `Physics.bleed_out(parent, source, exclude)`
	 (a dead character, once its body comes to rest: one slow, wide pool). A blood source may expose
	 `blood_origin() -> Vector2` (where its blood leaves it, in world space); pools emerge there instead
	 of at its position, so a fallen body bleeds from where it lies. Master switches:
	 `BloodConfig.enabled` off → `spawn_blood` / `bleed_out` spawn nothing and return null;
	 `PhysicsConfig.debris_enabled` off → `spawn_debris` spawns nothing. Blood pools are added with
	 readable names (`BloodPool`, `BloodPool2`, …).
   - `BloodSurface` (static registry): `register(rect, groove: Callable(world, half_width) -> 0..1, porous) -> id` /
	 `unregister(id)` — Objects' `Floor` registers its room so a bleed-out flow runs along grout/seams
	 (`resistance(pos)` is read only by Physics' `BloodFlow`; `BloodConfig.surface_flow` off ignores floors).
   - `Ragdoll` (`RefCounted`, character on death): a generic 3D point-mass body over the floor plane
	 (x/y + height z). Built with `add_point(at, radius, mass)`, `add_bone(a, b)` / `add_rigid(indices)`,
	 `add_frame(origin, up, right, forward_hint)`, `add_swing(frame, joint, child, rest, limits)`
	 (cone limit) and `add_hinge(frame, parent, joint, child, rest, bend, min, max, slack)` (one-way
	 hinge), seeded with `push(i, v)`, stepped with `step(delta, space, origin)` until `asleep`; read
	 with `point(i)` / `point_count()` / `frame_basis(f)`; `exclude` lists colliders its wall sweep
	 ignores. The Character domain owns the humanoid skeleton built on it.
   - `PhysicsConfig` (`class_name` static holder, see below) — the deformation tuning
	 (`deform_depth_per_damage`, `deform_max_depth`, `deform_chunk_damage`, `deform_max_impacts`,
	 `deform_update_collider`) that Objects reads directly when recording damage, and the ragdoll
	 solver's `ragdoll_*` tuning (read only by `Ragdoll` itself).
   Physics imports nothing from other domains.

5. **"Pushable" contract** — anything shoveable exposes `apply_impulse(v)` + `get_mass()`.
   Furniture is a `RigidBody2D`, so its native methods serve the contract; the character
   integrates knockback into locomotion. Used by furniture→character contact transfers, bullet
   impacts, melee punches, and the walking character.

6. **Items ↔ Character**
   `Item` (`items/item.gd`): `display_name`, `reach`, `hand_stance(hand) -> StringName` (how that
   hand is held — the name of a `CharacterConfig.stances` entry: `relaxed`, `guard`, `aim`, `support`;
   the character's pose eases each hand to it and the rig bends the arm to reach it), `primary(user)` (F),
   `secondary(user)` (LMB), `draw_weapon(canvas, user)`, `drop(user, velocity) -> Node2D` (let go
   as its user dies: the pistol leaves a skidding `DroppedItem` in the world, the default leaves
   nothing) and `draw_dropped(canvas, at, angle, modulate, opts)` (how it looks lying loose; `opts.flip`
   is which side landed up). The character
   calls `drop` on death and removes the item from its inventory if a node came back. `ItemRegistry.create(id)` /
   `default_inventory()`. The character API an item may call: `facing`, `punch(hand)`,
   `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)` (`CharacterConfig.muzzle_ahead`
   past the hand), `world_root()`, `report_shot(body, dmg)`, `kick(hand)` (recoil: throws that hand back), `weapon_facing()` (the
   drawn weapon direction, trailing the aim; shots still use `facing`). The pistol is the one
   place Items reach into the Projectile System (`ProjectileSpawner`/`CasingSpawner`).

7. **Character ↔ Controller** (enables non-player characters)
   The character reads intent from a pluggable **controller child** — any node with
   `control(character, delta)`. The controller writes `move_input` / `aim_point` and calls the
   character's action API: `melee()` (F), `shoot()` (LMB), `select_slot(id)`, `try_interact()` /
   `interact_with(object, id)` / `end_interaction()`, and may read `damage_taken()` (accumulated hit
   damage, for injury sensing) and `faction` (allegiance tag, for AI hostility). The AI also reads
   another character's `facing` and `damage_taken()` — but only while it can SEE that character
   (aim and visible wounds are things it perceives).
   `player_controller.gd` is the human one — the gameplay reader of `Keybinds` (`main.gd`, the spectator
   inspector and the dev command server each read an action too; see `domain-general`). Signals:
   `hit_landed(body, damage, hand)` (hand 0/1 = melee punch, hand −1 = shot),
   `died` (with `is_dead` / `health` to read; a dead body
   falls as a ragdoll, leaves layer 1 and draws beneath the living). Observers (debug HUD, match HUD, camera) attach by
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
   - `NavBuilder.rebake(region, house, rooms, agent_radius=14.0)` — re-carves the furniture holes in
	 place at the pieces' **current** positions (driven by the Navigation domain's own `nav_updater.gd`).
   - `NavBuilder.furniture_holes(house) -> Array` — the carved furniture footprints as world-space
	 polygons, which Main snapshots for the `nav_debug.gd` debug overlay (draw-only).
   `main.gd` calls `build` once after `WorldGen.generate` (and builds the `nav_debug.gd` overlay and the
   `nav_updater.gd` re-baker right after). Any `NavigationAgent2D` then pathfinds
   against the global map automatically — the AI's locomotion sets `target_position` and steers at
   `get_next_path_position()`. It does **not** enable RVO avoidance: instead the navmesh is
   **periodically re-baked** (`nav_updater.gd`, only when a piece has moved) so furniture that gets
   shoved around is re-carved as a hole at its new spot and paths route around scattered objects.
   Between re-bakes (and for non-solid decor, never carved) a displaced piece is simply bulldozed by
   the character's push physics.

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

11. **General → Interaction / AI: `PhysicsLayers.SOLID`**
    - `PhysicsLayers` (`general/physics_layers.gd`, a `class_name` static holder) — `SOLID` names
	  the physics layer bit (1) that "walls + solid furniture" live on. Interaction's reach query
	  (`character_interaction.gd`), AI perception's sight/line-of-fire rays (`agent_vision.gd`) and
	  its debug mirror (`ai/debug/vision_debug.gd`) all raycast on this one shared constant instead
	  of each redefining the same magic number — the single point of truth for that layer id.

12. **Objects / Character / Items → Art** (leaf: the pixel-art engine; each domain owns its painters)
    - `PixelArt.render(painter, size, color, facing, material, opts) -> Texture2D` — a painter's art
	  at a cardinal facing (the image is turned); furniture, walls, floors.
    - `PixelArt.render_turned(painter, size, color, angle, material, opts) -> Texture2D` + `PixelArt.snap_angle(angle)`
	  — canonical art lit for a snapped angle, drawn rotated by the caller to the exact one;
	  characters, hands, the pistol.
    - `PixelCanvas` — the surface a painter draws on (`static paint(canvas, base, material, opts)`):
	  shapes (`rounded`/`ellipse`/`disc`/`bowed`), `fill`, `bevel`, `outline`, `surface`, `grain`,
	  `speckle`, `glare`, `cast_shadows`, `tones(base)` …
    - `ArtConfig` (`class_name` static holder) — the shared resolution, light, drop/cast shadow,
	  turn steps, tone ramp and surface-finish tuning.
    Objects' painters + `ObjectArt` registry, Character's body, head, hand, limb and trunk painters and Items' pistol
    painter all render through these; Art imports nothing from other domains.

13. **Testing → every domain** (a second composition root, like `main.gd`)
    `scenes/testing/` builds a test's world and drives it through the interfaces above only:
    WorldGen (1, incl. the catalogue lookups) or an arena from the three factories (2), `NavBuilder`
    + `nav_updater.gd` (9), the character scenes plus the controller contract (7) — a puppet
    `ScriptedController` or `player_controller.gd` on `character/character_base.tscn` (the
    controller-less character) — and `EventBus` / character signals (7, 10) for its event log.
    Behaviour switches set existing exported props and config-holder `static var`s by name
    (duck-typed, like Main's overlay flags); a test can also script the Von answers through the AI
    decision sub-domain's `DecisionStub` statics (`decision_stub.gd`, read by `decision_client.gd`) so AI
    wiring runs without a server. Examples of the knobs: the Physics domain's `BloodConfig.enabled` /
    `PhysicsConfig.debris_enabled` master switches; statics are restored after each test. Main
    reaches it only by changing scene to `testing/test_browser.tscn`; the UI widgets it shows
    (`test_browser_window.gd`, `test_result_hud.gd`) take plain dicts and emit signals. Nothing
    depends on Testing.

14. **Main → General settings, UI settings page** (the composition root wires them; they never meet)
    - `Settings` (`general/settings.gd`, a `class_name` static holder): `load_file()` (Main calls it once in
      `_ready`, after seeding `Settings.debug` from its own export — not `Keybinds._ready`, so tests never
      read a developer's file), the saving mutators `set_debug(on)`, `rebind(action, event) -> bool`,
      `reset(action)`, `reset_all()`, and `binding_rows() -> Array` (plain dicts for the page). It persists
      the Debug switch and the `Keybinds` bindings that differ from the defaults to `user://settings.json`.
    - `SettingsMenu` (`ui/settings_menu.gd`): `open({ debug, rows })`, `set_rows(rows)`; signals
      `debug_changed`, `rebind_requested(action, event)`, `reset_requested`, `reset_all_requested`,
      `back_requested`. It takes plain dicts and knows nothing of `Keybinds`/`Settings`; Main opens it from the
      setup window's `settings_requested`, applies each signal to `Settings` and redraws with `set_rows`.

### Dependency graph (arrows = "calls / knows"; no cycles)

```
main ─▶ WorldGen ─▶ ObjectFactory / WallFactory / FloorFactory ─▶ Objects ─▶ Physics
main ─▶ NavBuilder ──(parses static colliders)──▶ NavigationServer2D
main ─▶ Character ◀─ PlayerController ─▶ Keybinds
main ─▶ Settings ─▶ Keybinds   /   main ─▶ SettingsMenu (UI; signals only, no dependency on Settings)
Character ─▶ Item ─▶ ProjectileSpawner ──(get_surface / take_hit)──▶ Objects
Character ─▶ Interaction ──(get_interactions)──▶ Objects
Objects / Character / Item ──(painters)──▶ PixelArt / PixelCanvas / ArtConfig   (Art, a leaf)
AIController ─▶ NavigationAgent2D ─▶ NavigationServer2D   (writes Character.move_input; tactics query the nav map)
Physics debris / casings ─▶ Despawner
Projectile / Character ──(&"hit" events)──▶ EventBus ──(posted)──▶ AIController / MatchHUD
AIController ──(&"callout" events)──▶ EventBus ──(posted)──▶ allied AIControllers
UI (DebugUI / MatchHUD) / Camera ──(exported path + signals)──▶ Character  (MatchHUD also reads AIController.debug_status)
main ──(Tests button: scene change)──▶ TestBrowser ─▶ TestRunner ─▶ WorldGen / factories / NavBuilder / Character scenes / EventBus
TestBrowser / TestRunner ─▶ UI (TestBrowserWindow / TestResultHUD / OverlayToggles)
```

Physics, Navigation, Art and World-Gen are leaves (World-Gen's only outward code dep is
`Wall.Side` + the three factories; Navigation depends only on Godot's `NavigationServer2D`; Art
only on Godot's `Image`). Tuning is split into six `class_name` static holders: `BallisticsConfig`
(projectile), `PhysicsConfig` (impact + deformation + the ragdoll solver), `CharacterConfig` (walking
push + punch + the character's art, pose and fall), `BloodConfig` (blood pooling), `ArtConfig` (the shared pixel-art light,
shadows, tones and finishes) and `ObjectArtConfig` (Objects' painter proportions/colors, props,
floor/wall tiles). There is no `Config` autoload. A seventh static holder, `PhysicsLayers`
(General, interface 11), is not tuning but a shared physics-layer id, the same role `Wall.Side`
plays for doorway sides.

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

- Main scene `res://scenes/main.tscn`.
- **Verification ladder** — use the cheapest rung that proves the change:
  1. **Loads?** `godot-debug` skill: headless load check (run `--import` first when you add a `class_name`).
  2. **Behaves?** `tools/run_tests.sh [words]` runs `tests/**/*_test.gd` headless and deterministically
     (exit 1 on any failure, or any engine error/warning logged during a test). Useful flags: `--list`,
     `--changed` (only domains with uncommitted changes), `--repeat=N` (flaky check), `--seed=N`,
     `--json`, `--include-von` / `--require-von`. A failure prints actor state and a `bundle:` JSON path.
     Writing tests: `domain-testing` skill; debugging one: `test-debug` skill. In the game, the setup
     window's **Tests** button opens the browser to play one.
  3. **Exploratory / not yet scriptable?** `godot-drive` skill: drive the live game through the dev
     command server (`tools/gcmd.py`).
  4. **Whole-AI outcomes?** `tools/match.py` scores full defender-vs-invader matches.
  A bugfix starts with a failing test on rung 2 (`test-debug` skill).
- Use the **`analysis-change-verification` skill** before committing (domain isolation, doc/skill sync,
  comment hygiene, load check).
- The relevant **`domain-<name>` skill** documents each domain's behaviour to verify (house
  generation, movement/pushing, items, interactions, combat).
