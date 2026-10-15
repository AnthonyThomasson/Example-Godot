---
name: architecture
description: The architecture map for this Godot project (Forced-Entry) — the sixteen isolated domains, the cross-cutting conventions, the whole sanctioned cross-domain interface surface, and the dependency graph. Load this BEFORE planning any change or exploring the codebase, and whenever you need to know where something lives or how two domains are allowed to talk. Points to each domain's `domain-<name>` skill for that domain's deep implementation detail.
---

# Forced-Entry architecture

A small top-down Godot 4.4 demo: a pixel-art character you walk with WASD (run on **Shift**, crouch on **C**) around a
procedurally furnished house, aiming at the mouse, with a punch on **F**, a kick on **V**, a gun (pistol, SMG or assault rifle)
that fires on left-click and reloads on **R**, stun and frag grenades thrown on left-click, items picked on **1**–**9**, object
interactions on **Space** (sit, lie, …) and, in the sandbox, a car or van to get into on **E**. The code is
organized into **sixteen isolated domains** so each can be changed on its own. The world is lit at dusk with real 2D
lights and shadows (the Lighting domain).

This skill is the **map**: the domains, the sanctioned cross-domain surface (the vital
interfaces), and the dependency graph. Keep changes inside a domain, and cross a boundary only
through the interfaces listed here. **When working *inside* a domain, also load its
`domain-<name>` skill** — that is where the deep implementation detail lives. A domain that has been split into
sub-domains keeps a short overview skill and one `domain-<domain>-<sub>` skill per sub-domain (listed in the table below); the
composition root is `domain-main`.

## The sixteen domains (one folder each under `scenes/`)

| Domain | Folder | Skill | Owns |
|---|---|---|---|
| **World Generation** | `worldgen/` | `domain-worldgen` | Picking a logical floorplan (front door, exits, hallways) and building/furnishing a house, and placing its run-down dressing (clutter, neon, where wear gathers) and the street round it with its street lamps. |
| **Objects** | `objects/` | `domain-objects` | The world's objects (furniture, walls, floors, the street), their wear and decals: their data, how they're hit/pushed, and their painters (what each piece looks like, in the run-down style). |
| **Items** | `items/` | `domain-items` | The things the character holds and the actions they perform, and what it wears (outfits: garments, armour plates). |
| **Character** | `character/` | `domain-character` (+ `domain-character-body` for `character/body/`) | The player character (built so other character types can exist). |
| **Interaction** | `interaction/` | `domain-interaction` | Object interactions: finding a reachable object and running one of its actions (sit, lie, …). |
| **Projectile System** | `projectile/` | `domain-projectile` | Shooting: penetration (the target's and the bullet's own power), a character's armour stopping a round, damage, cover, ricochet; and a grenade's burst (`Explosion`: the frag's blast and fragments, the stun's flash and bang). |
| **Physics System** | `physics/` | `domain-physics` (+ `domain-physics-blood` for `physics/blood/`) | Physical reactions: forces, knockback, deformation, debris and hit particles, a grenade burst's look (flash, fireball, smoke, scorch: `Physics.spawn_explosion`), ragdoll, and blood (its own sub-folder, `physics/blood/`). |
| **Art** | `art/` | `domain-art` | The procedural pixel-art engine every painter draws through: the canvas, the cached renderer, the shared light/tone/surface tuning. |
| **Audio** | `audio/` | `domain-audio` | The procedural sound system: every sound is synthesized in code, picked by event (gunshots per gun, bullet impacts per surface / outcome / round weight, footsteps per floor and gait, reloads, a grenade's throw, bounce, burst, a vehicle's ignition, doors, crashes, engine and skid loops) and played by the `Sound` autoload through a capped pool of positional voices; a deafened `Sound.focus` (the human) gets a muffle and a tinnitus whine. |
| **Lighting** | `lighting/` | `domain-lighting` | The world's dusk lighting, a leaf like Audio (`docs/lighting.md`): the ambient and the sky, a light per light-giving piece (declared by the piece) and per room fixture within a per-floor budget, their seeded rhythms, the shot and explosion flashes, and who stands in a light. |
| **Navigation** | `navigation/` | `domain-navigation` | Baking the house into a walkable nav map so characters can path around walls. |
| **General** | `general/` | `domain-general` | Infrastructure: input (Keybinds), saved settings (`Settings`), the event bus (`EventBus`), the log (`GameLog`), despawner, camera, dev command server, shared physics-layer ids (`PhysicsLayers`), the draw-order ladder (`DrawLayers`) and the light masks (`LightMasks`). |
| **UI** | `ui/` | `domain-ui` (+ `domain-ui-menus`, `-hud`, `-overlays`, `-testing` for `ui/<folder>/`) | All HUDs and menus, one sub-domain per folder: menus (pre-game setup window, settings page), hud (debug player panel, match HUD, seed readout, spectator inspector and its contact markers, stun screen, stack markers), overlays (overlay registry, toggle bar, performance overlay) and testing (test browser window, test result banner). |
| **AI** | `ai/` | `domain-ai` (+ `domain-ai-perception`, `-snapshot`, `-decision`, `-behavior`, `-combat`, `-coverage`, `-watch`, `-entry`, `-debug`) | Non-player brains: one generic controller that drives every NPC. Plus `ai/team/`, the human's side of the entry radio (`PlayerStack`, interface 17). Internally split into four isolated **sub-domains** under `ai/` — perception (`ai/perception/`), decision (`ai/decision/`), behaviour (`ai/behavior/`), debug (`ai/debug/`) — around a thin orchestrator (`ai/goal_controller.gd`). `domain-ai` is the overview; each sub-domain has a `domain-ai-<name>` skill. |
| **Vehicles** | `vehicle/` | `domain-vehicle` | Drivable vehicles (a car and a van, only in the sandbox): the rigid body and its driving model, doors and seats, getting in and out (the character's `CharacterVehicleUse` component and the ride), collisions and the harm to a character struck, the dents, the vehicle art and its events. |
| **Testing** | `testing/` | `domain-testing` | Game tests: a second composition root that builds a declared world (arena, hand-laid room layout or generated house) with chosen behaviour switches, runs a test's script against it and asserts what happened; the in-game test browser + runner, and the headless CLI runner. Test cases live in `tests/<domain>/*_test.gd`, or one folder deeper by topic (`tests/ai/entry/`); sandboxes to play by hand (`GameTest` scripts with no assertions) live outside `scenes/` in `sandboxes/*_sandbox.gd`. |

`scenes/main.gd` (`main.tscn`) is the **composition root** — with the Testing domain's runner
(interface 13), the only code that knows every domain. It asks World-Gen for a house, places the NPCs (`scenes/match_spawner.gd`),
arms and styles every character for its side (its loadout; the match's police unit or a defender's crew style and weapon style, read off
`CharacterConfig.styles`) and wires the HUDs, overlays and settings page; the setup window's **Tests** button
sends it to the test browser instead. It lights the match (`WorldLighting.light`, interface 20) right after the nav bake. Match lifecycle (Start / Watch / Endless, teardown, the Von-server wait), the placement rules and
the exports are the **`domain-main`** skill. `project.godot` autoloads only `Keybinds`, `Despawner` and `EventBus` (all General) and
`Sound` (Audio).

## The vital interfaces (this is the whole cross-domain surface)

Everything not listed here is private to its domain. The signatures live only here: a domain's skill names the
interfaces it takes part in (by number) and describes how they're implemented.

1. **Main → World Generation**
   - `WorldGen.generate(seed, force_plan, front_entrance_world, parent) -> Node2D` — seeds one RNG
	 for the whole run (plan pick is its first draw), prints `House: <plan>  seed: N`, builds
	 the house; every doorway is an open archway.
   - `WorldGen.get_rooms(house) -> Array` — the house's rooms as `{ key, type, rect }` dicts
	 (world-space `rect`), read from the house's `rooms` metadata.
   - `WorldGen.get_openings(house) -> Array` — the house's doorways as `{ pos, width, front, exit, rooms }` dicts
	 (world-space `pos`, `rooms` = keys of the rooms it joins; `front` = the one front entrance, on the south
	 wall, `exit` = a back/side/garage door, each with one room), read from the house's `openings` metadata.
   - The run-down dressing a generated house carries, read from its `wear`, `clutter` and `street` metadata the same way (empty
	 for a hand-laid layout): `WorldGen.get_wear(house) -> Array` — `{ room, pos, layer }` per wear cluster (0-3 a room, by a wall,
	 a corner or furniture; `pos` its world-space centre, `layer` the CanvasItem drawing that room's wear, one per room);
	 `WorldGen.get_clutter(house) -> Array` — `{ room, key, node }` per walk-over clutter piece (0-2 a room, no `key` twice; a
	 non-solid catalogue piece, never carved into the nav map); `WorldGen.get_street(house) -> Array` — `{ kind, rect, node }` per
	 piece of the street ring round the house (`kind` `street` or `sidewalk`, world-space `rect`, `node` the floor drawing it;
	 none registers a `SoundSurface`, interface 16, so footsteps out there stay `outdoor`); `WorldGen.get_streetlights(house) -> Array`
	 (its `streetlights` metadata) — `{ pos, node }` per street lamp along the front sidewalk (`pos` its world-space centre, `node` the
	 placed piece under the house: a solid, anchored metal post, carved into the nav map, its arm and head an overhang; about
	 `WorldGenConfig.streetlight_every` px apart, none within `streetlight_door_clear` px of a front or exit doorway's centre nor in the
	 strip straight out of one: a lamp that would be is dropped).
   - Read-only catalogue lookups (used by the Testing domain to place single pieces):
	 `WorldGen.object_definition(key) -> Dictionary` (for `ObjectFactory.spawn`),
	 `WorldGen.floor_definition(key) -> Dictionary` (for `FloorFactory.spawn`) and
	 `WorldGen.wall_style() -> Dictionary` (the house wall `style` for `WallFactory.spawn`).
   - `WorldGen.annotate_layout(root, rooms, doors = [])` — for the Testing domain's hand-built arenas and layouts: stores the
	 same `rooms` / `openings` metadata a generated house carries (a door on one room's wall only is the front entrance), so
	 `get_rooms`, `get_openings` and `NavBuilder` read them unchanged. No other caller writes those keys.
   `main.gd` positions the front entrance, fixes draw order and builds the nav map from the rooms (interface 9); its
   `match_spawner.gd` drops each defender at a clear spot in a random room (its centre unless solid furniture is within `spawn_clearance` or another
   combatant within twice that — read off `NavBuilder.furniture_holes` — else a random clear point) and each invader
   just outside the house (all via `get_rooms`), and hands every NPC the house's `get_openings` (for tactical
   entry); it never touches world-gen internals.

2. **World Generation → Objects** (the only way world-gen makes entities)
   - `ObjectFactory.spawn(definition: Dictionary, position, parent, opts) -> Node` — `opts`: `name`, `rotated`, `color`, `facing`,
	 and `neon` (`"cyan"` / `"magenta"` / `""`: the piece's neon trim or screen; omitted, Objects picks it per piece for a share of
	 the light-giving pieces, from where it stands). Two definition fields shape a piece beyond its look: `anchored` (true: a solid
	 piece that never moves, frozen static: no push, kick, round or blast shoves or turns it, it is still struck, dented and throws
	 debris) and `overhang` (`{ size, reach }`: an overhead part drawn beyond the footprint by the piece's painter with
	 `part: "overhang"`, `size` across x out, centred `reach` px out along its facing; a child CanvasItem named `Overhang` with
	 `get_rect() -> Rect2` (the area it draws, in its own frame), at `DrawLayers.OVERHEAD` above the characters, with no collider).
   - `WallFactory.spawn(rect: Rect2, thickness, openings, name, parent, style = {}) -> Node` —
	 `style` is the cap's look (`art`, `color`, `art_opts`); empty = a flat gray line.
   - `FloorFactory.spawn(rect: Rect2, definition: Dictionary, name, parent) -> Node` — a room's
	 floor or a piece of the street (no collider), from a floor definition (`art`, `color`, `material`, `art_opts`, and optionally
	 `sound_surface` (false: registers no `SoundSurface`, the street), `marks` (`{ seed, lane, edges }`: the street's world-placed
	 marks, curb and gutter litter, laid by Objects over the piece), `tile_from` (the point in `parent`'s space its repeating
	 tile is laid from, so neighbouring pieces share one grid) and `light_layer` (`"street"`: the piece and its canvas items on
	 `LightMasks.STREET`, interface 20)).
   - `WearFactory.spawn(rect: Rect2, floor_definition: Dictionary, wall_thickness, clusters: Array, name, parent) -> Node2D` — a
	 room's wear: World-Gen places the clusters (`{ pos, wall, seed }`: centre, the free stretch of wall `[a, b]` it is by or `[]`,
	 the seed of its marks, in `parent`'s space); Objects decides each cluster's marks (on the floor, following its pattern, and
	 often on that wall) and draws them. Built after the house's floors and walls; one node per room.
   - `WallFactory.openings_for(rect: Rect2, doors: Array) -> Array` — the `{ pos, width }` doorways that lie
	 on `rect`'s walls, as the `openings` `spawn` takes (World-Gen and the Testing domain's layouts use it).
   - `Wall.Side` — the enum inside those `openings` (callers get them from `openings_for`).
   World-Gen owns the *catalogue*; Objects owns the *field schema* and turns a plain definition
   dict into a node. World-Gen never touches an object's fields.

3. **Objects/Character/Vehicles ↔ strikers: the "hittable" contract**
   Every world object (furniture **and** walls), **the Character domain's `character.gd`** and **the Vehicles domain's `vehicle.gd`**,
   implements:
   - `get_surface() -> Dictionary` → `{ coverage, penetration, material, color }` — `coverage` is a height on a 0–100 scale: a bullet
     flies at one height and strikes what stands above it (a character's is its posture's; `docs/cover-and-stance.md`)
   - `take_hit(hit: HitInfo) -> void`
   - optionally `get_surface_at(height, direction) -> Dictionary` (the character: where its armour lies, `docs/outfits.md`): the surface a
     round flying at that height along that direction meets — `get_surface()`, or over armour that surface with the armour's `penetration`,
     `material` and `color` plus `stop_power` (round-power units: a round whose power × speed factor is below it is stopped) and
     `inner_material` (what a round that beats it strikes: flesh). The projectile asks it before `get_surface()` when it exists.
   `HitInfo` (`physics/hit_info.gd`) carries `position, normal, direction, damage,
   speed_factor, penetrated, source`, plus `has_exit` / `exit_position` / `exit_normal` (where a penetrating
   bullet left the body), `blood` (0..1, blood a bullet carries out of a character onto the next
   surface) and `height` (the 0..100 height the striker flew at, which picks a character's hit zone; −1 = none: a blast strikes the
   whole body). The projectile decides the ballistic outcome, then hands
   the struck body a HitInfo; the body decides what a hit *does to it* — an object spawns debris
   (interface 4), the character bleeds instead (its `BloodWound` component, interface 4), a vehicle is dented
   (`Deformable`), throws debris and is shoved at the hit (`Physics.impact_impulse`) and is never destroyed. A round that meets a `stop_power` and does not
   beat it is blocked; one that beats it always penetrates, so an armoured body reads `penetrated == false` as "stopped by the armour" (it
   then takes only the armour's blunt share, no wound). The
   projectile and the grenade's `Explosion` (Projectile System: the frag's blast, `Explosion.frag`) are the strikers that call `take_hit`
   (a blast hit carries `speed_factor` 0 and `height` −1: its shove is the grenade's own `blast_impulse`, applied through the pushable contract below, a
   character's through `blast_push`); a melee punch shoves through the "pushable"
   contract below, deals its damage through `take_damage(amount)` (the character's plain damage entry, no HitInfo;
   tests wound a character with it too) and does **not** deform, and reads `get_surface()` only for the struck
   `material` it posts. `Explosion` finds the characters under the world by the group `characters` (interface 7), reads their `is_dead`, `facing`, `get_surface()`, and calls
   `take_stun` / `take_damage` / `blast_push` / `take_hit` on them, and `apply_impulse` on a pushable (capped by `get_mass()`): the sanctioned surface. Its
   cover rule (G7, `docs/grenades.md`) is published as two read-only line queries the AI's perception asks of a grenade, so the AI keeps no copy:
   `Explosion.shields(space, burst, p, height, exclude, cover_reach := INF) -> bool` (whether a wall, or a piece of furniture whose `coverage` is
   above `height`, stands between a burst and a body `height` tall at `p`; with a finite `cover_reach`, a stun's flash, a piece only when `p` is
   within that many px of it) and `Explosion.first_stop(space, a, b, height, exclude) -> Dictionary` (the first wall or piece on the line that
   stops it for that height, as its ray hit, or `{}`). An object also carries `object_name` (its display name), which the AI's wording reads.

4. **Objects/Character/Vehicles → Physics** (objects, the character and a vehicle compose physics; Physics is a leaf domain)
   - `Knockback` (Node child): RigidBody2D adapter — configures its parent body and owns
	 `apply_impulse(v, at_world)`.
   - `Deformable` (Node child): `record(hit, turn = 0.0)`, `impacts`, `damage_total`, `changed`
	 signal (`turn`: the body's drawn turn beyond its node rotation; the character passes its facing). A vehicle composes one
	 (no `Knockback`: it is its own `RigidBody2D`) with chunks off and does not rebuild its collider from the dents.
   - `Deformation` (static): silhouette/collider polygons + drawing (`draw_shape` and
	 `draw_wall` optionally textured — `draw_shape` also turned by `texture_angle`, its hit marks
	 optional for a caller drawing them over later layers with `draw_marks` — so pixel art is drawn
	 through the dented silhouette). The polygons are `base_ring(shape, size)` (a primitive's undented ring),
	 `shape_polygon(shape, size, impacts)` (a piece's or the character's dented silhouette, cached), `wall_polygon(a, b, thickness, impacts)`
	 (a dented wall segment), `is_valid_polygon(poly)` (callers skip a self-touching one that frame) and `convex_shapes(polygon)` (the
	 convex pieces a dented collider is rebuilt from); `NO_COLOR` is the sentinel a caller passes to take a drawing call's default colour.
   - `Physics.impact_impulse(hit) -> Vector2`, `Physics.spawn_debris(world, hit, surface)` (objects and a vehicle)
	 `BloodWound` (Node child, character: `record(hit)` on a hit throws a splatter spray and owes drips, one
	 `BloodSplat` every `BloodConfig.drip_interval_min..max` s from the body's blood origin; `stop()` on death)
	 and `Physics.bleed_out(parent, source, exclude)`
	 (a dead character, once its body comes to rest: one slow, wide pool). A blood source may expose
	 `blood_origin() -> Vector2` (where its blood leaves it, in world space); pools emerge there instead
	 of at its position, so a fallen body bleeds from where it lies. Master switches:
	 `BloodConfig.enabled` off → `BloodWound.record` / `bleed_out` spawn nothing (`bleed_out` returns null);
	 `PhysicsConfig.debris_enabled` off → `spawn_debris` spawns nothing. Splatters and bleed-out
	 pools are added with readable names (`BloodSplat`, `BloodSplat2`, … / `BloodPool`, …).
   - `BloodField` (static registry, Physics-internal: `BloodSplat`/`BloodPool` register themselves) /
	 `BloodDecals` (a batched layer under a world node, `BloodDecals.layer(parent)`) /
	 `BloodFootprints` (Node child, character: `step(foot, at, direction, length, width, inner, speed)` on
	 each footfall prints a sole if the foot is carrying wet blood) / `BloodSmear` (Node child, objects:
	 `set_footprint(local_polygon)`, then drags blood out of a puddle as feathered, wandering ribbons while the body slides).
	 Both need `BloodConfig.enabled` and their own switch (`footprints_enabled` / `smear_enabled`).
   - `BloodSurface` (static registry): `register(rect, groove: Callable(world, half_width) -> 0..1, porous) -> id` /
	 `unregister(id)` — Objects' `Floor` registers its room so a bleed-out flow runs along grout/seams, and rugs register as porous
	 (blood sinks into carpet and rugs, `is_porous(pos)`)
	 (`resistance(pos)` is read only by Physics' `BloodFlow`; `BloodConfig.surface_flow` off ignores floors).
   - `Ragdoll` (`RefCounted`, character on death): a generic 3D point-mass body over the floor plane
	 (x/y + height z). Built with `add_point(at, radius, mass)`, `add_bone(a, b)` / `add_rigid(indices)`,
	 `add_frame(origin, up, right, forward_hint)`, `add_swing(frame, joint, child, rest, limits)`
	 (cone limit) and `add_hinge(frame, parent, joint, child, rest, bend, min, max, slack)` (one-way
	 hinge), seeded with `push(i, v)`, stepped with `step(delta, space, origin)` until `asleep`; read
	 with `point(i)` / `point_count()` / `frame_basis(f)`; `exclude` lists colliders its wall sweep
	 ignores. The Character domain owns the humanoid skeleton built on it.
   - `Physics.spawn_explosion(world, at, kind)` (`kind` `&"frag"` / `&"stun"`; called by the Projectile System's `Explosion`): the look of a
     grenade's burst, `ExplosionFx` nodes `ExplosionFlash`, `ExplosionFireball` (frag only) and `ExplosionSmoke`, which draw themselves in stepped
     pixel rows and free themselves (Despawner-tracked), and a frag's scorch mark in the world's `ScorchDecals` layer (batched like `BloodDecals`,
     capped by `Despawner.max_scene_objects`). Looks and timings are `PhysicsConfig.explosion_looks`; `PhysicsConfig.explosion_fx_enabled` off
     spawns none of it. `Ragdoll.wake()` restarts a sleeping body's clocks so an explosion's push is simulated (the character's `blast_push`).
   - `PhysicsConfig` (`class_name` static holder, see below) — the deformation tuning
	 (`deform_depth_per_damage`, `deform_max_depth`, `deform_chunk_damage`, `deform_max_impacts`,
	 `deform_update_collider`) that Objects reads directly when recording damage, and the ragdoll
	 solver's `ragdoll_*` tuning (read only by `Ragdoll` itself).
   Physics imports nothing from other domains but General's infrastructure (`Despawner` for debris, hit particles, blood and
   the explosion effects, `PhysicsLayers` for `PhysicsConfig.wall_mask`, `DrawLayers` for its z knobs).

5. **"Pushable" contract** — anything shoveable exposes `apply_impulse(v, at = Vector2.ZERO)` + `get_mass()`,
   `at` the contact offset from the piece's origin (in world orientation; omitted = a central shove).
   Furniture is a `RigidBody2D`, so its native methods (this is their signature) serve the contract and a shove off
   the centre turns it; the character ignores `at` and integrates knockback into locomotion. Used by
   furniture→character contact transfers, bullet impacts, an explosion's blast (central), and the character's punch,
   kick, leg press and walking push (each at its contact point). A vehicle (`vehicle.gd`, a `RigidBody2D`) is pushable through
   its native methods too (a bullet shoves it at the hit); it shoves furniture through the physics solver and a character it
   strikes through the character's `apply_impulse` (interface 19), and a piece pressed against a character it strikes (or
   that it presses against one) through the piece's `apply_impulse`, read against its `linear_velocity`. To carry a piece at walking pace instead of launching it,
   a pusher may also read a `RigidBody2D` pushable's `linear_velocity` / `angular_velocity` and the inverse inertia the
   physics server holds for it (`PhysicsServer2D.body_get_direct_state`), and cap its shove by them; a pushable without
   them (a character) is shoved uncapped.

6. **Items ↔ Character**
   `Item` (`items/item.gd`): `display_name`, `reach`, `hand_stance(hand) -> StringName` (how that
   hand is held — the name of a `CharacterConfig.stances` entry: `relaxed`, `guard`, `aim`, `support`;
   the character's pose eases each hand to it and the rig bends the arm to reach it), `primary(user)` (F), the melee hooks the character's hands read, `strike_direction(aim, amount)` / `strike_end(aim, amount)` / `strike_forward()` / `strike_short()` / `strike_support_gap()` / `strike_tempo()` (a long gun's punch swings it nearly across the body, butt leading; `GunItem` overrides `strike_ahead()` / `strike_turn()`, from which the direction, end and forward follow, and the short, support gap and tempo),
   `secondary(user) -> bool` (LMB; true = a round left the barrel), `tick(delta)` (the item's own clocks; the character ticks
   every item it carries each physics frame), `is_automatic()` (holding the trigger keeps firing), `weapon_hand()`,
   `muzzle_ahead()` (px past the weapon hand where bullets leave; negative = the character's `CharacterConfig.muzzle_ahead`),
   `raises_at_contact()` / `raised_stance(hand)` (a long gun's barrel against a wall or object: held pointing up, cannot fire),
   `draw_weapon(canvas, user)`, `drop(user, velocity) -> Node2D` (let go
   as its user dies: a gun leaves a skidding `DroppedItem` in the world, the default leaves
   nothing; the dropped node's `DroppedItem.item` is that very item) and `draw_dropped(canvas, at, angle, modulate, opts)` (how it looks lying loose; `opts.flip`
   is which side landed up), and `drawn_art() -> Array` (the textures its last draw, `draw_weapon` or `draw_dropped`, painted: every call in
   the frame it was last drawn, e.g. a lying item's shadow and art; pixel art is cached by what it depicts, so a test compares drawings by
   them, like `CharacterVisuals.drawn_art()`). The character
   calls `drop` on death and removes the item from its inventory if a node came back. `ItemRegistry.create(id, rounds, magazine)` / the slot ids `UNARMED_SLOT`, `FISTS_SLOT` and `KEY_SLOT` (the AI selects its fists with `ItemRegistry.FISTS_SLOT`, and names its grenades by `STUN_SLOT` / `FRAG_SLOT` (`AgentThrow.SLOTS`, the bang entry's stun); the debug panel lists the grenade rows through `LoadoutConfig.grenade_options()`; an interaction's `requires_item` is a slot id, the key's) /
   `default_inventory()` / `inventory_for(slots, rounds, magazine, grenades, style := &"police")` (an optional `magazine` type the gun starts loaded with; `grenades` = slot -> count; `style` the weapon style stamped on every item made) /
   `create_magazines(type_ids)` (full `Magazine`s for those `MagazineConfig` types: the character's spare-magazine store) /
   `random_gun_slot(rng)` / `loadout_for(gun_slot, stuns, frags)` / `spares_for(gun_slot)`. The grenades (`docs/grenades.md`) are `Item`s too: slots `ItemRegistry.STUN_SLOT` 7 / `FRAG_SLOT` 8, a *count*
   carried (`Item.uses_left()`, -1 = unlimited for every other item; `Item.is_throwable()`; `Item.throw_stats() -> Dictionary` (`{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }` for a grenade, from its `GrenadeConfig` row via `GrenadeConfig.stats_of`; `{}` default; `ThrownGrenade.throw_stats()` answers the same for a live one); `ItemRegistry.create(slot, count)`), thrown by `secondary` after a `windup` in the `throw` stance (the `GrenadeItem` posts `&"throw"` as it leaves the hand) as a `ThrownGrenade`
   (a world node in the group `live_grenades`: `kind`, `fuse_left()`, `throw_stats()`, `thrower`, and `item`, the grenade item that draws it, in
   the thrown item's weapon style) that posts `&"grenade"` events and, when its fuse ends, calls the Projectile System's `Explosion.frag` / `Explosion.stun` (`(at, world, source, row)`, `row` = its `GrenadeConfig` row). `LoadoutConfig` (static holder) is what Main
   hands a character: `options()` (plain dicts for the setup window: `RANDOM`, then every `GunConfig` gun with its magazines),
   `grenade_options()` (the Stun and Frag rows: `{ id, label, slot, max }`; a loadout names their counts `stuns` / `frags`, 0..3), `grenade_counts(loadout)`,
   `outfit_options()` (the outfit rows: `[{ slot, label, choices: [{ id, label }] }]`, one per slot, a "None" choice `id` `&""` first where the slot may be empty; the
   vest choice that holds plates marked `plates: true`, each plate row `plate: true`),
   `normalize(loadout)` (a `{ weapon, magazine, spares, stuns, frags, outfit }` dict made valid; `outfit_of(loadout)` fills every outfit slot, a missing or unfitting
   id taking `default_outfit`'s: plain clothes, and clears both plates unless the vest holds plates), `apply(character, loadout, rng, style := {}) -> gun id` (arms it through `Character.set_loadout` and dresses it in the whole
   outfit through `Character.set_outfit`; `style` = how it is all drawn, looks only: `look` / `seed` /
   `rank` passed to `Character.set_style`, absent = the character's style left as it is, and `weapon`, the weapon style passed to
   `Character.set_loadout`, absent = `police`) and `random(rng)` (with `random_outfit(rng)`, drawn after the gun). **Weapon style:** every `Item` has a `style`
   (`&"police"` for the invaders, `&"scrap"` / `&"pipe"` for a defender; default `police`), the look it is drawn in, never what it does: a gun
   or grenade draws its `GunConfig` / `GrenadeConfig` row's `looks` row for it (the painter and its colours; `GunConfig.look(gun, style)` /
   `GrenadeConfig.look(kind, style)`, `default_style` `police` for a style it has no row for), held, dropped (either side up) and, for a
   grenade, in flight and at rest; a dropped gun is the item it was, and a thrown grenade's `item` takes its thrower's item's style. **Outfits** (`docs/outfits.md`): `OutfitConfig`
   (static holder: the garment and plate rows, a garment's `looks` per character style (`zenitex`, `trauma`, `merc`, `borg`: its `kind` and a `color`
   or a `palette` name, `default_style` for a style it has no row for), `GARMENT_SLOTS` / `PLATE_SLOTS` (String keys `head body vest pants feet
   front_plate back_plate`), `choices(slot)`, `fits(slot, id)`, `name_of(slot, id)`) and `Outfit` (`RefCounted`, one character's worn set: `set_ids(ids)`, `ids()`, `worn(slot)`, `condition(slot)`,
   `layer(zone, side)` (the armour a round meets there: `{}` or `{ stop_power, penetration, material, color, blunt, reduction, blast, plate }`), `wear(zone, side, damage)`,
   `weight()`, `look(style)` (what the art draws, in that character style), `view()` (what the UI shows) and `revision` (bumped by every change, which the art watches)). The
   character API an item may call: `facing`, `punch(hand)`, `punch_amount(hand)` (0..1, how far that hand is thrown: a long gun swings round by it),
   `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)` (the held item's `muzzle_ahead()` past the hand),
   `world_root()` (also read by the AI: the characters it perceives are the group `characters` under it), `report_shot(body, dmg)`, `kick(hand, strength := 1.0)` (recoil: throws that hand back; `strength` scales it),
   `weapon_facing()` (the drawn weapon direction, trailing the aim; shots still use `facing`), `aim_target()` (the aim point a grenade is thrown to) / `aim_sway()` (rad, the stun's wandering turn of every shot and throw; 0 unstunned) and `weapon_raise()` (0..1, how far
   a long gun is raised off a wall, for its art). **Guns:** every firearm is a `GunItem` (`items/gun.gd`) tuned by its row in
   `GunConfig` (damage, `fire_interval`, `automatic`, `penetration`, `muzzle_speed`, `spread_deg`, `recoil`, its default magazine,
   `raises_at_contact`); `PistolItem` / `SmgItem` / `RifleItem` supply only their sizes and hold (the look is the row's `looks`, above). **Ammo:** `Item` has inert hooks
   `rounds_loaded()` / `ammo_capacity()` (-1 = no ammo), `reload_time()`, `can_reload(user)`, `finish_reload(user)` and a
   `reloading` flag the character sets. **Gun identity:** `gun_id()` (the `GunConfig` id, `&""` for a non-gun) and `round_power()`
   (the penetration power of its rounds, 1 for a non-gun), which the character reads for its `reload` event. A `Magazine` (an `Item` subclass, types in `MagazineConfig`, each tied to one `gun` id,
   with its own capacity and optional `reload_time`) is carried
   by the character, never held or selectable; a gun loads one and each shot spends a round. For a reload
   an item calls the character's `best_magazine(gun)` / `take_magazine(gun)` / `stow_magazine(m)`. Items reach into the
   Projectile System in two places. A gun fires through `ProjectileSpawner.spawn(position, direction, parent, ignore = null, item_damage = 0.0,
   muzzle_speed = -1.0, penetration = 1.0, max_range = -1.0, strikes_shooter = false) -> Node` (the round; the gun connects its
   `hit(body, damage)` signal to its user's `report_shot`) and ejects a case through `CasingSpawner.spawn(position, direction, parent) -> Node`;
   a `ThrownGrenade` calls `Explosion.frag` / `Explosion.stun` (above).

7. **Character ↔ Controller** (enables non-player characters)
   The character reads intent from a pluggable **controller child** — any node with
   `control(character, delta)`. The controller writes `move_input` / `aim_point` / `run_input` (hold run: a
   faster pace that spends stamina while moving, dry = walk until it refills; only a standing character runs) and calls the
   character's action API: `set_posture(p) -> bool` (`stand` / `crouch`; idempotent, so a controller may write it every frame; the player's C calls
   `toggle_crouch()`), `melee()` (F), `leg_kick() -> bool` (a right-leg kick along the facing, whatever is held; false while dead, crouched, busy or a kick is under way; reads `is_kicking()`; **not** the recoil `kick(hand, strength)` above), `shoot() -> bool` (LMB; true = a round left the barrel; ignored while running, reloading,
   or with a long gun's barrel against a wall or object, and a gun holds back between rounds per its fire rate; a controller re-presses it
   every frame while the trigger is held when `is_automatic()`), `reload()` (R: a timed swap to
   the fullest carried magazine, taking the item's `reload_time()`; refused while running or busy and cancelled by running, switching items or
   dying), `select_slot(id)`, `try_interact()` /
   `interact_with(object, id)` / `end_interaction()`, `try_use_vehicle()` (E: get in or out, interface 19), and may read `damage_taken()` (accumulated hit
   damage, for injury sensing), `posture()`, `is_running()` / `stamina_fraction()`, `run_speed()` / `walk_speed()` (px/s standing, running / walking, slower while stunned or weighed down by the outfit: how an AI works out whether it gets somewhere in time) / `posture_coverage(posture)` (the body's height on the coverage scale in `stand` / `crouch`, what furniture must stand above to shield it), the ammo reads `ammo(slot := -1)` / `ammo_capacity(slot)` / `can_reload(slot)` /
   `spare_magazines()` / `is_reloading()` (the held item for slot -1; -1 rounds = no ammo), `item_name(slot := -1)`, `current_item()` / `current_slot()` / `item_reach()` / `has_item(id)` (the held item, its slot and reach, and whether a slot is carried — what the AI's wording, the debug panel and `requires_item` interactions read), `is_attacking()` (a punch swing is under way), `gun_slot()` (the
   gun it fights with: the held item if it takes ammo, else the lowest such slot, else −1), `weapon_blocked()` / `weapon_raise()` /
   `is_automatic()`, `item_count(slot := -1)` (a grenade slot's count, 1 for any other item, 0 for none), `throw_stats(slot := -1)` (what a grenade carried in the slot tells its holder, `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, `{}` for any other item or an empty slot: how the AI reads a grenade's numbers, instead of keeping a copy), `throw_release_offset(slot := -1)` (where a grenade leaves its hand when it throws one standing: the hand of its `throw` stance, as `Vector2(px ahead of the body centre, px to its right)` in its own frame; the AI judges a lob from there, instead of keeping a copy of the stance), `aim_target()` (the swayed aim point a grenade
   is thrown to, interface 6: where the AI expects its own grenade to come down), `set_loadout(slots, hold_slot, spare_types, loaded_magazine := &"", grenades := {}, weapon_style := &"police")` (carry only those slots, holding one, with those spare
   magazines, the gun loaded with that type when it fits, a grenade slot with `grenades[slot]` of them, every item in that weapon style (`Item.style`): how Main arms a spawn with its side's loadout);
   how it is drawn (`docs/outfits.md` O15, looks only): `style` (exported; a `CharacterConfig.styles` key: `zenitex` / `trauma` the police units, `merc` / `borg`
   the defenders' crew; `zenitex` when never given one), `look_seed` (exported: its own variety within the style), `rank` (a police unit's: 0 trooper, 1 sergeant,
   2 lead) and `set_style(style, seed, rank := 0)` (`LoadoutConfig.apply` calls it);
   what it wears (`docs/outfits.md`): `set_outfit(ids)` (`{ head, body, vest, pants, feet, front_plate, back_plate }`, replacing the whole outfit; `LoadoutConfig.apply`
   calls it), `outfit() -> Outfit` (what its art reads `look(style)` and `revision` from) and `outfit_view()` (each garment slot -> its name, "" for none; each plate slot ->
   `{ type, name, condition }`: what the debug panel and the spectator inspector list), and where a round strikes it: `hit_zone(height)` (`feet` / `legs` / `torso` /
   `head` by height over the posture's coverage; `&""` below 0) and `hit_side(direction)` (`front` / `flank` / `back` against the shoulders' facing), with
   `get_surface_at` (interface 3); an outfit's weight slows `run_speed()` and every pace;
   while the character rides a vehicle (interface 19, from the E press to its last step out) `is_busy()` is true, and `current_item()` is null
   while it is posed by the ride (the item put away);
   the stun (a grenade's flash and bang): `take_stun(blind, deaf)`, `is_blind()`, `is_deaf()`, `stun_level()` (0..1 disorientation: slowed to `CharacterConfig.stun_speed`, no running, aim sway), `stun_view()` (`{ blind, blind_total, deaf, level }`, for the UI) and `blast_push(from, impulse)` (an explosion's shove: knockback, or the fallen body's ragdoll thrown) and `faction` (allegiance tag, for AI hostility). The AI also reads
   another character's `facing`, `damage_taken()`, `is_reloading()`, `posture()`, `current_item()` and `faction` — but only while it can SEE that character
   (aim, visible wounds, a reload in progress and the posture are things it perceives); the exceptions are three reads of an unseen character's `faction`,
   which stand for knowing who its own team is: the faction of a character whose footstep it hears (the `footfall` event's `character`, interface 10), so its
   own side's steps are never taken for a stranger's (`docs/hearing.md` H1); of the attacker of a hit on or near it (the `hit` event's `attacker`), so an
   ally's round striking nearby is not fire at it; and of the thrower of a grenade that bursts (the `explosion` event's `attacker`), so it knows a burst as its
   own team's (`docs/grenades.md`). Every character joins the group `characters` in its `_ready`:
   that group is how the AI (its perception and tactics), the Projectile System's `Explosion` and a vehicle tell a character in the world, so it
   is part of this interface and is not renamed lightly.
   `player_controller.gd` is the human one and
   is the only *gameplay* file that touches `Keybinds` (observers read one thing each: Main `MENU`; the test runner `MENU`, `PAUSE` and the camera actions;
   the spectator inspector `PAUSE`; the camera its pan and zoom actions). Signals:
   `hit_landed(body, damage, hand)` (hand 0/1 = melee punch, hand 2 = leg kick, hand −1 = shot),
   `died` (with `is_dead` / `health` to read; a dead body
   falls as a ragdoll, leaves layer 1 and draws beneath the living). Observers (debug HUD, match HUD, camera) attach by
   exported node path and read only the public API/signals; the AI controller joins the group `npc_controllers` in its `_ready`, and
   the HUDs find an NPC's controller as its child in that group (the UI's `hud_probe.gd`; a player's controller is never one). The AI controller also exposes
   `current_act()` (its live decision path as ids, e.g. `combat/t_12/flank/side_left`) and
   `debug_status()` (the same path as labels, every level: `COMBAT - Intruder - FLANK - their left
   side (kitchen)`), `debug_state() -> Dictionary` (the deep snapshot the dev command server's `ai` verb dumps), `debug_zones() -> Array`
   (the tactical points the spectator inspector picks from; it rings the one it describes on the NPC's tactics overlay, the overlay child
   exposing `set_focus(point)` / `clear_focus()`), the draw-only overlays' `debug_*` getters (e.g. `debug_entry_view()` for the tactical-entry ones), `known_contacts_for_display()` (the spectator inspector's contact list) and `goal_text()` (the plain-language goal with `{gun}` filled in with the NPC's gun) for those observers to show. Each overlay is a child of the NPC with a `show_<x>` export named in the UI's `OverlayRegistry` (`show_grenades` reads `debug_grenades()`: `{ known: [{ point, kind, fuse_left, fuse, radius, source }], escape: Vector2 (INF: none), throw: {} }`);
   Main, the spectator inspector and the Testing world set those flags by that name, so an overlay's export is part of this surface. Every NPC is the same generic goal-driven agent
   driven by `ai/goal_controller.gd`; the defender (`ai/npc_defender.tscn`) and the invader
   (`ai/npc_invader.tscn`), both inherited from `ai/npc.tscn` (itself an inherited scene of the controller-less
   `character/character_base.tscn`), differ only in data authored on the scene —
   a plain-language `goal` plus generic primitives (hostility rules, pursuit, territory) and
   decision-tree config. Main injects only `rooms` and `openings` (and `entry_point`); the AI finds and categorizes
   the characters it perceives by sight. Von walks a data-driven DECISION TREE ranked against the
   goal — a broad mode (combat / reload_quiet / investigate / search / idle), then a tactic (engage / flank / advance /
   retreat / reload / locate …), then a concrete option (a place, a firing spot, an object) — one `choice`
   request per level, ending in a behaviour primitive (move / engage / melee / interact / hold / reload / entry / throw) — no
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
   `interactions` object field. The character never learns what an interaction *means*. The component touches only its host's
   `global_position` (a `move_to` action snaps the body onto the object and back), `facing` (the reach query sits ahead of the body, on
   `PhysicsLayers.SOLID`, interface 11, excluding the body's own `get_rid()`), `aim_point` (the player's Space picks the reachable object
   nearest the cursor) and `has_item(id)` (an action's `requires_item`), and takes Godot's own collision exception
   (`add_collision_exception_with`) with the object a `move_to` puts it on. When an interaction ends the component hands
   the object to the character's `keep_clear_of(body)`, which keeps their collision exception until the character's circle no longer
   overlaps it (then drops it; a freed body is forgotten), and calls `stop_clearing(body) -> bool` when the character goes straight back
   onto that object, so its exception stays.

9. **Main / AI → Navigation** (leaf: builds the map, everyone else just pathfinds)
   - `NavBuilder.build(house, rooms, parent, agent_radius=14.0) -> NavigationRegion2D` — bakes
	 one `NavigationRegion2D` whose walkable area is the house footprint plus an outdoor ring minus the house's
	 **static** wall colliders (doorways stay open) **and minus each solid furniture footprint**
	 (baked in as a hole: every `RigidBody2D` with a collider, an anchored piece frozen static among them; walk-over decor has
	 none), so paths route around furniture.
   - `NavBuilder.rebake(region, house, rooms, agent_radius=14.0)` — re-carves the furniture holes in
	 place at the pieces' **current** positions; `rebake_async(region, house, rooms, agent_radius, done)` does it with the
	 bake on the NavigationServer's worker thread (what the Navigation domain's own `nav_updater.gd` drives).
   - `NavBuilder.furniture_holes(house) -> Array` — the carved furniture footprints (the anchored pieces' included) as world-space
	 polygons: what the Navigation domain's draw-only `nav_debug.gd` overlay draws and its `nav_updater.gd` watches for a
	 moved piece, and what Main's `match_spawner.gd` keeps a spawn's clearance from.
   - **Characters at rest are holes too, on a second map.** `NavBuilder.character_holes(root) -> Array` (the footprints of the
	 living characters at rest under the region's parent), `NavBuilder.steering_map(planning_map) -> RID` (a map of its own, holding
	 the furniture *and* those holes; named from the frame `build` returns, before it has synchronized (`ready` tells when it answers);
	 invalid when the world has none), `steering_region(region)` and
	 `rebake_steering(region, house, rooms, agent_radius=14.0)` (driven by `nav_updater.gd`). The world's own map stays furniture-only, because the AI
	 plans on it; the AI's `Locomotion` puts its `NavigationAgent2D` on the steering map for a walk that goes round a body at rest it
	 knows of (the map carves every one; what a walker accounts for is the AI's rule, `domain-ai-behavior`).
   - **Map queries**, what the AI asks of a baked map when it weighs a point or a route: `NavBuilder.ready(map) -> bool`
	 (valid, synchronized at least once and has taken in every region `build` put on it, so a map still showing the previous
	 navmesh counts as unbaked), `snap(map, p) -> Vector2` (`p` on the navmesh; unchanged before the bake),
	 `route(map, from, to) -> PackedVector2Array` (the navigated waypoints; a straight segment before the bake or with no
	 path) and `path_length(path) -> float`. The AI's locomotion, tactics geometry, entry geometry, snapshot options and
	 routes overlay, and the human's `PlayerStack` (how near a doorway it is), all go through these, so the "is the map baked yet" rule lives in one place.
   - **Avoid maps**, for a walk that keeps out of some stretch of floor (the AI's doorway views, `docs/tactical-entry.md` E18):
	 `NavBuilder.avoid_map(region, key, holes) -> RID` (`region`: the planning region `build` returned, found from a world map by
	 `NavBuilder.planning_region(planning_map) -> NavigationRegion2D`; `holes`: world-space polygons; `key` names the set): a map of its
	 own with the planning bake plus those holes, baked on the NavigationServer's worker thread, cached by `key` (re-baked when the
	 planning bake has been redone since), freed by the next ask for another set once nobody has asked for it for 20 s, and with its
	 world, and `ready` as any map. The world's map and the
	 steering map are untouched. The AI's `Locomotion` walks it and `AgentEntry.walk_route` measures on it.
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
    These topics are in use:
    - `&"hit"`: the Projectile System posts one per damaging hit and the Character one per landed
      punch (`{ position, victim, source, direction, damage, attacker }`; `attacker` = the striking
      character or null). The AI controller consumes it for combat awareness, hostility ("attacked
      me") and gunfire heard farther off; the match HUD for its combat feed. It also says *how* the
      hit met the surface, for the Audio domain: `outcome` (`&"blocked"` / `&"penetrate"` /
      `&"ricochet"` for a bullet, `&"punch"` for a fist or a kick, `&"blast"` for a frag's blast: posted by the Projectile System's
      `Explosion` with the thrower as `attacker` and `speed_factor` 0, which Audio does not voice as an impact: the burst has its own sound), `material` (the struck surface's, `""` for a
      wall; for a round armour stopped, the armour's: `metal`, `ceramic`, `composite`, `fabric`; for one through it, the flesh under it), and for bullets
      `speed_factor` and `power` (its penetration power). Its `damage` is the striker's, before the struck character's zone, blunt and reduction
      scaling (`docs/outfits.md`; the same for `hit_landed` / `report_shot`). A shot that flies over cover posts nothing.
    - `&"explosion"`: `Explosion.frag` / `Explosion.stun` (Projectile System) post one when a grenade goes off (`{ position, kind` (`&"frag"` / `&"stun"`)`,
      attacker` (the thrower, or null)`, radius` (the blast radius of a frag, the flash radius of a stun)` }`), before the burst's hits and stuns, for
      Audio (`explosion/<kind>`), the camera (General: `Camera2D.offset` shake by distance and kind) and the AI (`docs/grenades.md`). The grenade's other topics: `&"throw"` (Items, the `GrenadeItem` as it leaves the hand: `{ position, kind, attacker }`), `&"grenade"` (Items, `ThrownGrenade`:
      `{ position, kind, stage }` with stage `bounce` / `rest`) and `&"stun"` (Character, `take_stun`: `{ character, position, blind, deaf }`). Audio voices the
      `throw` (`throw/<kind>`), a `grenade` `bounce` (`grenade/<kind>/<floor>`, the floor from `SoundSurface.at`; a `rest` is silent) and the `explosion`, and of the `stun`
      only a deafening of its `focus` (interface 18); the AI hears where a grenade comes down from its `bounce` / `rest`, and the UI's `StunScreen` reads the human's own `stun` event to freeze the frame of the flash.
    - `&"shot"`: a gun (Items) posts one per round that leaves the barrel (`{ position` (the
      muzzle)`, gun, attacker, power }`). Audio voices it and the Lighting domain lights a muzzle flash (as it lights a burst on an
      `&"explosion"`).
    - `&"footfall"`: `CharacterFootsteps` posts one each time a foot lands (`{ position` (the sole)`,
      foot` (0 left / 1 right)`, speed, running, character` (the walker)`, crouched }`). Audio voices it; the AI hears it
      (`docs/hearing.md` H1: a stranger's steps through walls, out to a range set by `running` / `crouched`).
    - `&"reload"`: `Character` posts one when a reload starts (`stage = &"start"`) and one when it finishes
      (`&"done"`, never after a cancelled one): `{ position` (weapon hand)`, gun, stage, power, character }`.
    - `&"sound"`: the Audio domain's `Sound` service posts one for every sound it accepts (`{ kind,
      profile, variant, position, volume_db, pitch }`), which is what tests assert on.
    - `&"callout"`: an AI controller posts one when it adopts a combat or investigation decision —
      its team radio (`{ speaker, faction, position, status, path, label, target_id, point }`, and with a combat decision `target_pos`:
      the hostile's last-known spot as the speaker knows it, else where the shots at it came from, `Vector2.INF` when it knows neither;
      an ally reads it as a fight in that room, `docs/grenades.md` G18) — and one
      per step of a tactical entry, which adds `opening`, `into` (the room it leads into), `slot`, `side` (the side of the door it stacks on: a stack split across the door, E19, has both), `entry_step` (claim / ready / bang /
      going_in / in / clear / cover / rear / done / abort), `bang` (this member goes in with a stun thrown first), `bang_off` (it gave the bang up: the stack goes in quietly) and `stuns` (how many it carries), `cleared_room` (with a clear) and `covering` (with a cover:
      the doorway on out of the cleared room it watches) (`docs/tactical-entry.md`); a human invader's `PlayerStack`
      (interface 17) posts the same entry steps for the human. A live grenade has its own statuses, which an ally in range reads as "a
      grenade is down there" and not as what the speaker is doing: `status = "grenade"` (an NPC that saw or heard a grenade come down and
      is in its danger zone: `point` the spot it landed, `kind` `&"frag"` / `&"stun"`; the NPC repeats it once if the grenade then comes to rest
      30 px or more away), `"frag_out"` / `"bang_out"` (the thrower of a frag or a stun, `point` the landing; the GRENADE tactic's call, G17), all
      from `docs/grenades.md` G16. Allied AI
      controllers within `callout_range` consume it (which flank an ally holds, whom it fights, where to
      support it, which stack slot is taken, when the point is through, which room is clear, which doorway on is
      covered, when the team moves on, which grenade to get clear of).
    - `&"vehicle"`, `&"engine"`, `&"skid"`: a vehicle (Vehicles) posts `&"vehicle"` `{ position, kind` (`&"car"` / `&"van"`)`, stage }` with
      stage `ignition` (a driver sat down; the vehicle's centre), `door_open` / `slide_open` (a shut door starts to open; at its handle),
      `door_close` / `slide_close` (the frame it shuts), `crash` (a new impact above `VehicleConfig.crash_min_speed` on anything but a
      character, + `speed` (the closing speed) and `material` (the struck `get_surface().material`, `""` for a wall)) or `bump_character`
      (a character struck, + `speed`); `&"engine"` `{ vehicle, kind, stage }` `start` / `stop`; `&"skid"` `{ vehicle, stage }` `start` /
      `stop` (the tyres begin / stop sliding). Audio voices the one-shots and keeps one looping voice per vehicle for its `engine` and its
      `skid`, following the vehicle each frame through `engine_state()`, `slip()` and `speed()` read duck-typed off the event's `vehicle`
      (the `Sound.focus` pattern, interface 18), so it stays a leaf.
    Emitters and listeners never reference each other (like `Despawner`).

11. **General → every domain: shared ids, `PhysicsLayers.SOLID` and `DrawLayers`**
    - `PhysicsLayers` (`general/physics_layers.gd`, a `class_name` static holder) — `SOLID` names
	  the physics layer bit (1) that "walls + solid furniture" live on. Interaction's reach query
	  (`character_interaction.gd`) and AI perception's sight/line-of-fire rays (`agent_vision.gd`; the
	  vision overlay asks the controller's `debug_sight_end` instead of casting) raycast on this one shared constant instead
	  of each redefining the same magic number — the single point of truth for that layer id. The character's
	  hand queries and leg sweeps (`character/body/`), a dropped item's glance (`items/dropped_item.gd`), a thrown grenade's flight (`items/thrown_grenade.gd`), the
	  bullet's `collision_mask` (`projectile/projectile.gd`), the blast's lines (`projectile/explosion.gd`), Physics' `PhysicsConfig.wall_mask` and a vehicle's body layer and mask, door
	  checks and pile queries (`scenes/vehicle/`) and the character's clearing check (`keep_clear_of`) read it too.
    - `LightMasks` (`general/light_masks.gd`, a `class_name` static holder) — the light masks every domain builds its shadows and
	  light layers on, so who shadows whom is decided in one place (`docs/lighting.md` L6): the occluder bits `WALL` 1, `FURNITURE` 2,
	  `EMITTER` 4 (a solid piece that gives light: it shadows only the flashes and the sky), `CHARACTER` 8; the shadow masks the
	  Lighting domain gives its lights (`PIECE_SHADOWS` walls + furniture + characters, `FIXTURE_SHADOWS` walls, `ALL_SHADOWS`); the item
	  light layers `HOUSE` 1 (Godot's default) and `STREET` 2 (the street, lit only by the street lamps, the flashes and its own sky);
	  `shadows` (whether occluders are built: off with the Testing domain's `lighting.enabled`) and
	  `occluder(polygon, bit) -> LightOccluder2D` (null while `shadows` is off; wound and culled so the shape itself stays lit). Read by
	  Objects (walls, solid pieces, the street floors), Character (the living body) and the Lighting domain (interface 20).
    - `DrawLayers` (`general/draw_layers.gd`, a `class_name` static holder) — the world's draw-order ladder, one rung per kind of thing,
	  so what lies on the floor, what a vehicle covers and what flies over it keep one order across domains: `FLOOR` −5 (Objects' `Floor`,
	  via `ObjectArtConfig.floor_z_index`) < `RUG` −4 (rugs and mats, `ObjectArtConfig.rug_z_index`) < `BLOOD` −3 (Physics: splats, a
	  bleed-out pool, prints and smears, the scorch decals; `BloodConfig.z_index` / `print_z_index`) < `LYING` −2 (a dead body,
	  `CharacterConfig.ragdoll_z_index`; a spent casing, Projectile; a `DroppedItem` and a grenade at rest, Items) < `UNDER_VEHICLE` −1
	  (a vehicle's `Chassis`) < `STANDING` 0 (Godot's default: the living, a vehicle's occupants, furniture, walls) < `ABOVE` 1 (a
	  vehicle's `Roof`, a grenade in flight, the UI's `StackMarkers`) < `OVERHEAD` 2 (a piece's `Overhang`, Objects:
	  `ObjectArtConfig.overhang_z_index`, a streetlight's arm and head; a room's ceiling fixture, Lighting) < `EFFECTS` 4 (Physics' `ExplosionFx`). A domain's own z knob is initialised from its rung,
	  never a bare number; within a rung the scene tree decides. `docs/vehicles.md` V3 / V6 (a body struck down lies under the vehicle).

12. **Objects / Character / Items / Vehicles → Art** (leaf: the pixel-art engine; each domain owns its painters)
    - `PixelArt.render(painter, size, color, facing, material, opts) -> Texture2D` — a painter's art
	  at a cardinal facing (the image is turned); furniture, walls, floors.
    - `PixelArt.render_turned(painter, size, color, angle, material, opts) -> Texture2D` + `PixelArt.snap_angle(angle)`
	  — canonical art lit for a snapped angle, drawn rotated by the caller to the exact one;
	  characters, hands, the guns, a vehicle's body, doors, wheels and lamps.
    - `PixelCanvas` — the surface a painter draws on (`static paint(canvas, base, material, opts)`):
	  shapes (`rounded`/`ellipse`/`disc`/`bowed`), `fill`, `bevel`, `outline`, `surface`, `grain`,
	  `speckle`, `glare`, `cast_shadows`, `tones(base)` …; `PixelCanvas.ConvexShape.new(rect, x0, x1, y0, y1)` (a shape from its per-row
	  and per-column spans) is built from outside by the Vehicles domain's `art/vehicle_art.gd`. **What gives light** (a screen's
	  face, a tube, a bulb, an LED) a painter draws inside `canvas.glowing(draw: Callable, area := Rect2i())`, which marks every pixel
	  the drawing changes as emissive; `PixelArt.emissive(painter, size, color, facing, material, opts) -> Texture2D` returns those
	  pixels of `render`'s texture for the same inputs (same paint, cached beside it; transparent elsewhere, null when nothing in it
	  glows), for a caller that draws light sources unshaded.
    - `ArtConfig` (`class_name` static holder) — the shared resolution, light, drop/cast shadow,
	  turn steps, tone ramp and surface-finish tuning.
    Objects' painters + `ObjectArt` registry, Character's body, head, hand, limb, trunk and vest painters, Items' painters
    (`items/art/`: one gun and one grenade painter per weapon style, police, scrap and pipe, drawing the guns held and dropped and the frag and stun grenades, and the spoon) and Vehicles' painters (`scenes/vehicle/art/`: car, van, door, wheel, lamp) all render through
    these; Art imports nothing from other domains.

13. **Testing → every domain** (a second composition root, like `main.gd`)
    `scenes/testing/` builds a test's world and drives it through the interfaces above only:
    WorldGen (1, incl. the catalogue lookups) or an arena / hand-laid room layout from the three
    factories (2, incl. `WallFactory.openings_for`), `NavBuilder`
    + `nav_updater.gd` (9), the dusk lighting as Main lights a match (20: `WorldLighting.light` after the nav bake), the character scenes plus the controller contract (7) — a puppet
    `ScriptedController` or `player_controller.gd` on `character/character_base.tscn` (the
    controller-less character), the vehicle scenes (19: `TestSetup.vehicle(id, kind, pos, rotation := 0.0, props := {})` instances
    `res://scenes/vehicle/<kind>.tscn` under the world root after the nav bake (not carved) and waits one physics frame so the new bodies
    are in the space; `t.vehicle(id)` reads it back; the puppet presses E with `use_vehicle()` and drives with
    `drive(throttle, steer, handbrake)`, writing `move_input` / `run_input` as the player's keys do) — and `EventBus` / character
    signals (7, 10) for its event log.
    Behaviour switches set existing exported props and config-holder `static var`s by name
    (duck-typed, like Main's overlay flags); a test can also script the Von answers through the AI
    decision sub-domain's `DecisionStub` statics (`decision_stub.gd`, read by `decision_client.gd`; the runner also drives the
    `DecisionServerLauncher` for the tests that need the real server; `DecisionBudget.per_frame`, the
    snapshots a frame may start, is set the same way) so AI
    wiring runs without a server. In the in-game runner a test can switch off user interactions that
    would change its result with `TestSetup.lock_interaction` (`camera` / `pause` / `overlays`), sending
    its own input through `TestContext.inject` so the lock lets it through; the runner also builds the
    Navigation domain's draw-only `nav_debug.gd` (via the world, kept current by `nav_updater.gd`) and the
    UI's `PerformanceOverlay` for the overlay bar's global toggles. Its scene carries General's camera (`general/camera_controller.gd`),
    which it points at the setup's camera targets (every actor by default) with `frame(targets)` and whose `pan_enabled` it clears where a
    human-driven player walks on WASD or the test locks the camera. Examples of the knobs: the Physics domain's `BloodConfig.enabled` /
    `PhysicsConfig.debris_enabled` master switches and the Audio domain's `audio.sound` switch; statics are restored after each test.
    A sandbox (`sandboxes/`, e.g. a `ticket-assets` showroom) may also draw through Art (12: its own painter on
    `PixelCanvas`, rendered by `PixelArt.render` / `render_turned`) and render a sound with
    `SoundBank.recipe_for(profile)` / `SoundSynth.render(recipe, seed_value) -> AudioStreamWAV`, played on its own
    `AudioStreamPlayer2D`; the `Sound` service hears nothing of it (16). Main
    reaches it only by changing scene to `testing/test_browser.tscn`, and the browser's Back changes scene back to
    `main.tscn` (the one thing Testing knows of Main); the UI widgets it shows
    (`test_browser_window.gd`, `test_result_hud.gd`) take plain dicts and emit signals. Nothing
    depends on Testing.

14. **Main → General settings, UI settings page** (the composition root wires them; they never meet)
    - `Settings` (`general/settings.gd`, a `class_name` static holder): `load_file()` (Main calls it once in
      `_ready`, after seeding `Settings.debug` from its own export — not `Keybinds._ready`, so tests never
      read a developer's file), the saving mutators `set_debug(on)`, `set_setup(config)`, `set_overlay(flag, on)`, `rebind(action, event) -> bool`,
      `reset(action)`, `reset_all()`, and `binding_rows() -> Array` (plain dicts for the page). It persists
      the Debug switch, the setup window's last choices (`setup`), the overlay toggles (`overlays`) and the `Keybinds`
      bindings that differ from the defaults to `user://settings.json`.
    - Main ↔ the dev command server (General, `general/command_server.gd`): it finds the match's nodes through the
      `match_world` group, restarts through `Main.return_to_setup()`, hands a seed over through the Engine metas
      `skip_setup` / `match_seed`, and drives the node named `Player`; those names are the whole contract.
    - `SettingsMenu` (`ui/menus/settings_menu.gd`): `open({ debug, rows })`, `set_rows(rows)`; signals
      `debug_changed`, `rebind_requested(action, event)`, `reset_requested`, `reset_all_requested`,
      `back_requested`. It takes plain dicts and knows nothing of `Keybinds`/`Settings`; Main opens it from the
      setup window's `settings_requested`, applies each signal to `Settings` and redraws with `set_rows`.

15. **Any domain → General (`GameLog`)** — `GameLog.say(message)` (`general/game_log.gd`, a `class_name` static
    holder) is how every domain prints its "what is happening" log (shots, punches, house seed, Von decisions,
    perf numbers). `GameLog.enabled` is true in the game; the batch test runner sets it from `--verbose`, so
    test runs are quiet unless asked. Plain `print` is not used for gameplay logs.

16. **Objects → Audio: `SoundSurface`** (a floor tells Audio what it is made of; Audio stays a leaf)
    - `SoundSurface.register(rect: Rect2, material: String, pattern: String = "") -> int` /
      `SoundSurface.unregister(id)` — Objects' `Floor` registers its world rect with its `floor_material` and
      the painter's `pattern` in `_ready` and unregisters in `_exit_tree` (the same way it already feeds
      `BloodSurface`); a floor whose definition sets `sound_surface: false` (the street round a house) registers none.
    - `SoundSurface.at(pos) -> StringName` — what the ground is at a world point (`wood tile stone concrete
      carpet`, or `outdoor` when no floor covers it; the newest floor wins). Read only by the Audio domain's
      `Sound` service, to voice a footfall.
    Everything else Audio hears arrives as an EventBus event (interface 10): the gun, projectile and character
    domains only *post*; none of them references Audio.

17. **Main → AI team: the human's place in a stack** (`scenes/ai/team/player_stack.gd`; a human invader is one of the stack)
    - `MatchSpawner.bind_player(player, rooms) -> Node` (Main's helper, beside `bind_npc`) attaches a `PlayerStack` child to the human with
      the house's `rooms` and `openings` (`PlayerStack.attach(character, rooms, openings)`); it returns it.
    - `PlayerStack.view() -> Dictionary` — `{}` with no reservation, else `{ opening, door, slots: [{ n, point, mine, held }], mine, step }`
      (`n` the slot, numbered in claim order; `point` where it stands, on its holder's side of the door: both sides on a split stack, E19):
      the UI's `StackMarkers` (`ui/hud/stack_markers.gd`, `watch(stack)`, built by Main under `World`) draws it on the floor and reads
      nothing else. The stack radios the human's claim as entry `&"callout"`s (interface 10) and reads the allies' off the same bus;
      the AI's entry code treats it as any teammate (E16 in `docs/tactical-entry.md`).

18. **Main → Audio: `Sound.focus`** (whose ears the player has; Audio stays a leaf)
    - `Sound.focus: Node` (a plain var on the `Sound` autoload): the character a bang deafens *for the player*. Main sets it to the human when there is
      one (`_build_stun_screen`) and clears it at teardown; null = nobody (a spectator match, a test). Audio reads only the focus's `stun_view()` (interface 7)
      duck-typed: while `stun_view().deaf` > 0, `Sound.muffled()` is true, the game audio goes through a low-pass and one `tinnitus/whine` sound
      (kind `&"tinnitus"`) plays per stun, following the deafness (`docs/grenades.md` G14). A blind-only stun, or the stun of any other character, changes nothing.
    - The sight half of the same stun is the UI's `StunScreen` (`ui/hud/stun_screen.gd`, `watch(character)`, `drawn()`), built by Main for the human and reading
      `stun_view()` (`blind`, `blind_total`) and the `&"stun"` event; it knows nothing of Audio, nor Audio of it.

19. **Character ↔ Vehicle: the drivable contract** (`scenes/vehicle/`; spec `docs/vehicles.md`)
    - **The character's side.** `character.gd` composes the Vehicles domain's `CharacterVehicleUse` (`vehicle/character_vehicle_use.gd`,
      preloaded and added in `_ready` like `CharacterInteraction`) and forwards opaque calls: `try_use_vehicle()` (E, refused while dead or
      in an object interaction: board by the door whose handle is nearest, or get out), `vehicle() -> Node` (the vehicle it is boarding, riding
      in or getting out of; null on foot) and `is_in_vehicle()` (seated only). It steps the component once a physics frame right after its
      controller (`control(delta)`), so a ride overrides that frame's intent, and calls `abandon()` from `_die` (the ride ends where the body is).
      It asks the component `is_active()` (true from the E press to the last step out): while a ride lasts `is_busy()` is true and
      `try_interact()` / `interact_with` are refused.
    - **What the Vehicles domain calls on the character.** During the walk to the door its controller fields `move_input` / `aim_point` /
      `run_input` (interface 7), and from the driver's seat it reads `move_input` / `run_input` as the drive intent; then the ride API:
      `set_ride_pose(at, toward, fold, step := Vector2.ZERO)` (world point, facing, fold 0 standing .. 1 seated, and `step`, the legs' motion
      through the vehicle's frame in px/s, so a carried body does not walk at the vehicle's speed): the first pose cancels a reload, puts the
      held item away (`current_item()` null) and disables the collision shape; the fold is the drawn crouch fold (`posture_folded()` reads it);
      and `end_ride()` (on its own feet again, shape on, item back). It also reads `facing`, `radius`, `speed`, `global_position`, and for a
      character it strikes (a body in the group `characters`, interface 7) `is_dead`, `health`, `velocity`, `get_mass()` and calls
      `apply_impulse` / `take_damage(amount)`; collision exceptions are Godot's own (`add_collision_exception_with` / `remove_...`); after a
      ride the vehicle goes to the character's `keep_clear_of(body)` (as in interface 8: the exception is dropped once the body is clear of it),
      and boarding the vehicle just left calls `stop_clearing(body)`.
    - **The vehicle** (`vehicle.gd`, a `RigidBody2D` on `PhysicsLayers.SOLID`, found by the group `vehicles`): `doors() -> Array`
      (`[{ id, kind` (`swing` / `slide` / `rear`)`, seat, handle, open` (0..1)`, hinge, angle, offset }]`, world space), `seats() -> Array`
      (`[{ id, occupant }]`), `driver() -> Node`, `board(character, door_id) -> RefCounted` (the ride, or null when that door cannot be used
      now), `exit(character) -> bool`, `drive_input(character, throttle, steer, handbrake)` (driver only, engine running), and the reads
      `speed()` (px/s, unsigned), `engine_state()` (`{ running, rpm, load }`), `slip()` (0 while the tyres grip), `wheel_angle()`,
      `brake_lights()` and `view_zoom_out()` (`VehicleConfig.drive_zoom_out` × speed / top speed: how far a camera following someone
      aboard zooms out). Its two draw layers are part of the contract too (the tests find them by name): the child `Chassis` (`layer`
      export `"chassis"`, at `DrawLayers.UNDER_VEHICLE`) and the child `Roof` (`layer` `"roof"`, at `DrawLayers.ABOVE`). Everything else on it (`half_size`, `outline`, `row`, `door_list`, `seat_point`, `occupant`, `is_free`, `reserve`,
      `change_seat`, `release`, `open_door` / `close_door`, `start_engine` / `stop_engine`, `brake_input`, `exit_door`, `hit_marks`) is
      Vehicles-internal, for its ride and visuals.
    - **Its other contracts:** hittable (3), Deformable / debris / impulse (4), pushable (5), the `vehicle` / `engine` / `skid` topics (10)
      and its painters (12). General's camera reads `target.vehicle().view_zoom_out()` duck-typed (`has_method`), never `VehicleConfig`;
      `player_controller.gd` calls `try_use_vehicle()` on `Keybinds.USE_VEHICLE` (E). Only the sandbox and the tests place a vehicle:
      Main, World-Gen, the nav map and the AI do not know them.

20. **Main / Testing → Lighting, and the world's lights and shadows** (`scenes/lighting/`; spec `docs/lighting.md`; Lighting is a
    leaf: it imports only General and reads the world duck-typed)
    - `WorldLighting.light(root: Node2D, seed_value: int, rooms: Array = []) -> WorldLighting` — lights the built world under `root`:
      adds one `WorldLighting` node under it, in the group `world_lighting` (`rooms` = `WorldGen.get_rooms`, for the fixtures;
      `seed_value` seeds the rhythms); null, building nothing, while `LightingConfig.enabled` is off. Main calls it after the nav bake
      with the house seed; the Testing world the same way, with its setup's seed. Its reads: `lights()` (every piece and fixture
      PointLight2D), `fixtures()` (`{ room, light }`), `flashes()` (the pooled flash lights) and `budget()` (`{ per_floor, dropped }`,
      `dropped` = `{ piece, index }` per declared light left without a light). `LightingConfig` (static holder): `enabled`,
      `ambient_color`, `sky_color` and the rest of the dusk, fixture, flash and budget tuning; the Testing domain's `lighting.enabled`
      switch sets `LightingConfig.enabled` and General's `LightMasks.shadows`.
    - **Objects → Lighting: `get_lights() -> Array`** on a light-giving piece (an EnvironmentObject; read duck-typed, like Audio reads a
      vehicle): one plain dict per light in the piece's frame, `offset` (Vector2), `turn` (rad, the pool's long axis), `colour`,
      `energy`, `radius` (px, along the long axis), `shape` (`round` / `wide` / `tube`), `rhythm` (`[[mode, weight], ...]`, modes
      `steady buzz failing blink shimmer pulse`), `room_light` (it lights its room: no fixture there), `street` (it lights the street
      too) and `glow` (the piece's `Emissive` overlay, dimmed with the light; or null). The Lighting domain parents each light it
      keeps to the piece, so a shoved piece carries it.
    - **The shadows and light layers** (on General's `LightMasks`, interface 11): Objects' walls (one occluder per wall run, `WALL`) and
      solid pieces (their footprint, `FURNITURE` or `EMITTER`) and Character's living body (an oval turned with `facing`, `CHARACTER`,
      freed on death) build their own `LightOccluder2D` children with `LightMasks.occluder`, like their colliders; Objects' street
      floors (catalogue `light_layer: "street"`) put their canvas items on `LightMasks.STREET`; Objects' `Emissive` overlays draw
      unshaded. The Lighting domain reads the floors (`floor_material`, `size`, the `light_mask` of their canvas items) for the per-floor
      budget, and each frame the characters in the group `characters` (`is_dead`, `radius`, interface 7) for whom stands in a light.
    - **The flash events:** the `&"shot"` and `&"explosion"` topics (interface 10) light its flash pool.

### Dependency graph (arrows = "calls / knows"; no cycles)

```
main ─▶ WorldGen ─▶ ObjectFactory / WallFactory / FloorFactory / WearFactory ─▶ Objects ─▶ Physics
main ─▶ NavBuilder ──(parses static colliders)──▶ NavigationServer2D
main ─▶ Character ◀─ PlayerController ─▶ Keybinds
main ─▶ LoadoutConfig ─▶ GunConfig / MagazineConfig / OutfitConfig / ItemRegistry (random_gun_slot / loadout_for / spares_for) ─▶ Character.set_loadout / set_outfit / set_style
main ──(the styles' side / weapons)──▶ CharacterConfig.styles
main ─▶ Settings ─▶ Keybinds   /   main ─▶ SettingsMenu (UI; signals only, no dependency on Settings)
Character ─▶ Item ─▶ ProjectileSpawner ──(get_surface / take_hit)──▶ Objects;  Projectile ──(get_surface_at / take_hit)──▶ Character ─▶ Outfit (Items)
Character ─▶ Interaction ──(get_interactions)──▶ Objects
Character ─▶ CharacterVehicleUse (Vehicles) ─▶ Vehicle   (the ride and a strike call back only the character API of interface 19, as an Item calls its user's)
Character ─▶ Deformable / Deformation / BloodWound / BloodFootprints / Ragdoll / HitInfo / Physics.impact_impulse / spawn_debris / bleed_out (Physics)
Vehicle ─▶ Deformable / Physics.impact_impulse / Physics.spawn_debris (Physics);  Vehicle ─▶ PhysicsLayers (General)
Objects / Character / Item / Vehicle ──(painters)──▶ PixelArt / PixelCanvas / ArtConfig   (Art, a leaf)
AIController ─▶ NavigationAgent2D ─▶ NavigationServer2D   (writes Character.move_input; tactics query the nav map)
AIController ─▶ ItemRegistry slot ids (Items: FISTS_SLOT, STUN_SLOT, FRAG_SLOT)
Physics debris / hit particles / blood / explosion fx, Projectile casings ─▶ Despawner
Projectile / Character ──(&"hit" events)──▶ EventBus ──(posted)──▶ AIController / MatchHUD
AIController ──(&"callout" events)──▶ EventBus ──(posted)──▶ allied AIControllers
PlayerStack (human) ◀──(&"callout" entry steps)── EventBus ──(&"callout": the human's claim)──▶ allied AIControllers;  StackMarkers (UI) ──(view())──▶ PlayerStack
AI perception ──(Explosion.shields / first_stop: the blast's cover rule)──▶ Explosion (Projectile)
ThrownGrenade (Items) ──(Explosion.frag / .stun)──▶ Explosion (Projectile) ──(take_hit / blast_push / take_stun, ProjectileSpawner fragments, Physics.spawn_explosion)──▶ Objects / Character / Physics
Item (&"shot") / Projectile (&"hit") / Character (&"hit", &"footfall", &"reload") ──(events)──▶ EventBus ──(posted)──▶ Sound (Audio) ─▶ SoundBank ─▶ SoundSynth
Character (&"footfall") ──▶ EventBus ──(posted)──▶ AIController (footsteps heard)
Objects Floor ──(SoundSurface.register)──▶ SoundSurface ◀── Sound   (Audio, a leaf: imports nothing but EventBus)
main ──(Sound.focus = the human)──▶ Sound   /   Character (&"stun") ──▶ EventBus ──▶ Sound (tinnitus + muffle for the focus), StunScreen (UI)
Explosion (&"explosion") ──▶ EventBus ──▶ Sound (the burst) / Camera (shake)
Vehicle (&"vehicle", &"engine", &"skid") ──▶ EventBus ──▶ Sound ──(engine_state / slip / speed, duck-typed)──▶ the vehicle's loops
Camera ──(target.vehicle().view_zoom_out(), duck-typed)──▶ Vehicle
UI (DebugUI / MatchHUD / SpectatorInspector) / Camera ──(exported path + signals)──▶ Character  (MatchHUD reads AIController.goal_text; the inspector debug_zones / known_contacts_for_display and the tactics overlay's set_focus / clear_focus; DebugUI and the inspector outfit_view)
DebugUI ─▶ LoadoutConfig.grenade_options (Items)
main ──(Tests button: scene change)──▶ TestBrowser ─▶ TestRunner ─▶ WorldGen / factories / NavBuilder / Character scenes / EventBus
Sandbox (Testing) ──(own painter)──▶ PixelArt / PixelCanvas (Art);  Sandbox ──(recipe_for / render)──▶ SoundBank / SoundSynth (Audio) ─▶ its own AudioStreamPlayer2D
TestBrowser / TestRunner ─▶ UI (TestBrowserWindow / TestResultHUD / OverlayToggles / PerformanceOverlay)
TestRunner / TestWorld ─▶ NavDebug / NavUpdater (Navigation, overlay + re-bake)
TestRunner ─▶ Camera (General: frame(targets), pan_enabled)
main / TestWorld ──(WorldLighting.light)──▶ WorldLighting (Lighting, a leaf) ──(get_lights(), floors, group `characters`, duck-typed)──▶ the world
Item (&"shot") / Explosion (&"explosion") ──▶ EventBus ──▶ WorldLighting (flashes)
Objects (walls, solid pieces, street floors) / Character (the living body) ──(LightMasks.occluder, STREET)──▶ LightMasks (General)
TestWorld ─▶ vehicle scenes (TestSetup.vehicle)
TestRunner / TestWorld ─▶ DecisionStub / DecisionServerLauncher / NPC scenes (AI), config-holder statics (behaviour switches)
TestBrowser ──(Back: scene change)──▶ main
```

Physics, Navigation, Art, Audio, Lighting and World-Gen are leaves — apart from General's infrastructure (`GameLog`, `EventBus`,
`Despawner`, `PhysicsLayers`, `DrawLayers`, `LightMasks`), which every domain may use (World-Gen's only outward code dep is
the four factories; Navigation depends only on Godot's `NavigationServer2D`; Art
only on Godot's `Image`; Lighting reads the world only duck-typed). Tuning is split into fifteen `class_name` static holders: `BallisticsConfig`
(projectile), `PhysicsConfig` (impact, debris and hit particles, deformation, the explosion's look, the ragdoll solver), `CharacterConfig` (walking
push + punch + being stunned + hit zones, sides and the outfit's weight + the character's art and its styles, pose, stances and fall), `BloodConfig` (blood splatter, drips and bleed-out), `ArtConfig` (the shared pixel-art light,
shadows, tones and finishes), `ObjectArtConfig` (Objects' painter proportions/colors, props,
floor/wall tiles, the run-down look: palette grade, grime, neon share, wear marks, street), `WorldGenConfig` (World-Gen's
furnishing fill pass, the run-down dressing's placement, the street ring and its street lamps), `MagazineConfig` (Items: magazine
types, capacities and reload times), `GunConfig` (Items: one row per gun — damage, fire rate, penetration,
muzzle speed, spread, recoil, magazine, whether it raises at a wall, its looks per weapon style), `GrenadeConfig` (Items: one row per grenade kind — fuse, windup, range, flight, the blast or flash and bang numbers, its looks per weapon style), `OutfitConfig` (Items: the garment and plate rows — slot, name, weight, looks per character style, the armour's zones, sides and protection numbers, a plate's durability), `SoundConfig` (Audio: the master switch, category volumes, voice caps and ranges, pitch/volume jitter, sample rate, round-weight bands, the vehicles' engine, skid and crash numbers), `VehicleConfig` (Vehicles: one row per kind — size, mass, engine, brakes, steering, grip, doors and seats — one `looks` row per kind, and the shared getting-in, driving, harm, crash, camera and look numbers), `LightingConfig` (Lighting: the master switch, the dusk, the room fixtures, the flashes, the per-floor budget and the light textures) and `LoadoutConfig` (Items: the setup choices' bounds — spare magazines, grenades — and the default outfit). World-Gen's `LayoutRules` (which rooms may
hold the front door or an exit, which room types may share a door) is a rules table in the same style, not
tuning. There is no `Config` autoload. Three more static holders are not tuning but shared ids (General, interface 11):
`PhysicsLayers` (a physics-layer id, the same role `Wall.Side` plays for doorway sides), `DrawLayers` (the shared draw-order
ladder every domain's z knob starts from) and `LightMasks` (the occluder bits, shadow masks and light layers).

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
- **Worktree editor:** `tools/editor.sh [--autorun]` opens a Godot editor on the checkout, named after the
  worktree directory (`GAME_TICKET`; Main passes it as `ticket` to the setup window, which shows it on top;
  a `--ticket=` user arg overrides it, and a run from any editor falls back to the directory name), unless
  one is already open there (it then prints that editor's pid, port and log). Each gets its own free
  command-server port (`GODOT_CMD_PORT`), importing first in a fresh worktree. `--autorun`
  makes the editor plugin `addons/ticket_autorun/` press Play once it is up.
- **Verification ladder** — use the cheapest rung that proves the change:
  1. **Loads?** `godot-run` skill: headless load check (run `--import` first when you add a `class_name`).
     **Clean?** `tools/lint.sh [paths]` (a few seconds) prints every GDScript analyzer warning of the editor's
     Debugger > Errors tab (unused variable, integer division, shadowed names ...) per file; it runs first in
     every `run_tests.sh` and fails the run before a test starts. Fix the code; silence a warning only as a last resort.
  2. **Behaves?** `tools/run_tests.sh [words]` runs `tests/**/*_test.gd` headless and deterministically
     (exit 1 on a lint warning, a failure, or any engine error/warning logged during a test). Useful flags: `--list`,
     `--changed` (the domains your uncommitted changes can break, in one run), `--id=<id>` / `--domain=a,b`
     (exact selection), `--failed` (rerun last run's failures), `--jobs=auto` (parallel shards),
     `--fail-fast`, `--summary` (failures + totals only), `--repeat=N` (flaky check), `--seed=N`,
     `--no-lint`, `--json`, `--include-von` / `--require-von`. A failure prints actor state and a `bundle:` JSON path.
     Writing tests: `domain-testing` skill; debugging one: `test-debug` skill. In the game, the setup
     window's **Tests** button opens the browser to play one.
  3. **Exploratory / not yet scriptable?** `godot-run` skill: drive the live game through the dev
     command server (`tools/gcmd.py`).
  4. **Whole-AI outcomes?** `tools/match.py` scores full defender-vs-invader matches.
  **Fast enough?** `tools/run_tests.sh --domain=perf`: the performance tests (`tests/perf/`: nine guards) hold a 5v5 and a 10v10 match to one 60 fps
  frame on average and hold stress cases to their budgets: automatic fire, nav re-bakes and path queries, a whole match dying in one
  frame, a furniture pile shoved at once, house generation, hundreds of hits on one body and an NPC crowd (`domain-testing` skill,
  "Performance tests"); a change to a per-frame path should leave them green.
  A bugfix starts with a failing test on rung 2 (`fix` skill).
- The relevant **`domain-<name>` skill** documents each domain's behaviour to verify (house
  generation, movement/pushing, items, interactions, combat).
