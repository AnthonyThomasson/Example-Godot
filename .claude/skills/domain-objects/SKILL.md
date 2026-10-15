---
name: domain-objects
description: Deep implementation detail for the Objects domain (scenes/objects/) — the world's furniture, walls, floors and street: their data, how they're hit/pushed/deformed, how they're drawn (the procedural top-down pixel art for every piece, wall and floor in the run-down look: painters, decay finish, neon share, emissive light sources, props, the world-placed wear and street decals, PixelCanvas, ObjectArtConfig), how they compose Physics, and what they give the lighting (a piece's `get_lights()`, the occluders of walls and solid pieces, the street's light layer). Use when editing scenes/objects/ (environment_object, object_lights, wall, floor, the factories, art/, decals/) or working on the hittable/pushable/interactable contracts, object field schema, pixel art / painters / props / floor and wall tiles, wear, the emissive overlay, a piece's lights and shadow, or wall segment math. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Objects domain

Owns the world's objects (furniture, walls, floors, the street round a house), their wear and decals: their data, how they're
hit/pushed, and their procedural pixel art. Objects owns the *field schema* and turns a plain definition dict
from World-Gen into a node.

## The hittable contract (interface 3)

Every world object (furniture **and** walls) implements it; the signatures and `HitInfo`'s fields are in `architecture`.
The striker decides the ballistic outcome and hands the object a HitInfo; the object decides what a hit *does to it*
(shove + deform + debris). A melee punch shoves through the pushable contract below and does **not** deform.

## The pushable contract (interface 5)

Furniture is a `RigidBody2D`, so its native `apply_impulse(v, at)` and `get_mass()` serve the contract (the engine integrates
motion, collisions, pivoting and settling). An **anchored** piece (definition `anchored: true`, the streetlight's post) is frozen static
in `_ready` (`freeze_mode` STATIC): the physics server gives it no inverse mass, so every shove (a push, a kick, a blast) is ignored and a
body walking into it stops as at a wall, and its `take_hit` skips the `Knockback` shove; it is still found by every query, struck,
dented (`Deformable`, the collider rebuilt from the dents), throws debris and is carved into the nav map
(`tests/objects/anchored_piece`, `tests/navigation/anchored_hole`). A character's shoves (walking push, leg press, punch, kick) pass the contact offset as
`at`, so a piece pushed near one end slides and turns about a point near the far end, one pushed in the middle of a side just
slides; the turn is the body's own torque, damped by `PhysicsConfig.body_angular_damp`. A melee punch is a range-of-motion-scaled
shove at the fist.

## The interactable contract (interface 8)

Which objects offer which actions is pure catalogue data: `get_interactions()` returns the object's `interactions` field and
holds no interaction logic.

## Objects → Physics (objects compose physics; Physics is a leaf)

- `Knockback` (Node child): RigidBody2D adapter — configures its parent body (no gravity,
  `mass`, damping, origin-pinned center of mass) and owns `apply_impulse(v, at_world)`.
- `Deformable` (Node child): `record(hit, turn = 0.0)`, `impacts`, `damage_total`, `changed` signal.
- `BloodSmear` (Node child, solid pieces only): fed the footprint polygon (`Deformation.shape_polygon`, re-fed
  when the collider is rebuilt); drags blood out of a puddle as streaks while the piece slides.
- `Deformation` (static): silhouette/collider polygons + drawing.
- `Physics.impact_impulse(hit) -> Vector2` and `Physics.spawn_debris(world, hit, surface)`.

## Runtime-shape convention (built in `_ready()`, not in the scene)

- `wall.gd._build_walls()` — a `RectangleShape2D` per wall segment (layout is data-driven from
  `size`/`openings`; `openings` are `{ side, offset, width }`). `wall.gd` owns the wall-segment
  math (`wall_segments()`) and colliders.
- `environment_object.gd` (a `RigidBody2D`) builds its collider only when `solid` (and freezes it static when `anchored`); non-solid
  decor is `freeze`d (no shape) and gets `z_index = ObjectArtConfig.rug_z_index` (`DrawLayers.RUG`, −4); a non-solid piece of
  cloth (`material` `fabric`: a rug, a mat, cardboard) registers a porous `BloodSurface` rect, the rest of the walk-over decor
  (litter, cables, a puddle, a neon tube) none. Physics components (`Knockback`,
  `Deformable`, `BloodSmear`) are added as child Nodes in `environment_object._ready()`.

The editor shows "no shape" warnings on each `Wall` — expected; the shapes exist at runtime.

## Layering (control / animate / draw)

`environment_object.gd` / `wall.gd` / `floor/floor.gd` are the control nodes (geometry, colliders,
look data — never draw). `environment_object_visuals` / `wall_visuals` / `floor_visuals` (own
child `Node2D`s) read from their control node and draw it.

**The overhang** (`overhang_visuals.gd`, interface 2): a definition's `overhang` (`{ size, reach }`) makes `ObjectFactory` add a
child `Overhang` to the piece, the overhead part that reaches beyond the footprint (a streetlight's arm and lamp head over the road).
It draws the piece's own painter with `part: "overhang"` at `size` (across x out, canonical; swapped for a sideways facing), centred
`reach` px out along the piece's facing, at `ObjectArtConfig.overhang_z_index` (`DrawLayers.OVERHEAD`, absolute: over the living and a
vehicle's roof), with no collider (only the footprint is solid); `get_rect()` is the area it draws in its own frame, and like the
piece's visuals it has `emissive()` / `emissive_layer()` (a child `Emissive`) for what in it gives light (`tests/objects/overhang`).

## Lights and shadows (interface 20; spec `docs/lighting.md`)

The Lighting domain lights the world; Objects declares and builds what its pieces, walls and floors take part with, on General's
`LightMasks` (interface 11):
- **`get_lights() -> Array`** (`environment_object.gd`, worked out once in `_ready`, after the visuals, by `object_lights.gd`): the lights
  a piece gives, one plain dict each in its own frame (`offset`, `turn`, `colour`, `energy`, `radius`, `shape`, `rhythm`,
  `room_light`, `street`, `glow`). What gives light is what its painter draws glowing; the kind is read off the painter and its
  options (`_kind`: a `lamp`; a `tv` (appliance panel), a `desk` (a table with a monitor prop), the den's `monitor_wall`, `server_rack`
  and `rig`, the ripperdoc's `surgical` chair and `tool_cart`, the vestibule's `scanner`, the `hotplate`, the `neon_tube` decor, a
  streetlight's `cobra` or `sign` head (at the `Overhang`'s centre, its overlay the glow, `street` on), and any other piece with a
  `neon` option, its `trim`), and the numbers are that kind's row of `ObjectArtConfig.light_specs` (energy, radius, shape, how far
  ahead of the front edge, the rhythms by weight, `room_light`: the lamp and the surgeon's lamp). Its colour is the painter's glowing
  colour: the neon (cyan / magenta), else the screen's green, the bulb's `lamp_glow_color`, the tube's tone, the lens's
  `streetlight_lens_color`, the beam's, the ring's. A screen's pool lies across its front (`turn` = facing + 90°), a tube's along it.
  The Lighting domain parents each light it keeps to the piece, so a shove carries it (`tests/lighting/shoved_lamp_light_follows`).
- **Occluders**, built like the colliders, through `LightMasks.occluder` (none while `LightMasks.shadows` is off): a solid piece one
  over its undented footprint (its rect, or a 12-gon, `OCCLUDER_SIDES`, for a round one), a child so it follows a shove, on `EMITTER`
  when `get_lights()` is not empty (its own light sits inside it) and `FURNITURE` otherwise; walk-over decor none; a wall one per
  segment, its collider's rect (`WALL`), built in `_build_walls`. Dents are not followed (too small for a shadow).
  (`tests/lighting/occluders_walls_pieces_characters`.)
- **The street's light layer:** a floor whose definition says `light_layer: "street"` (the catalogue's street and sidewalk) puts
  itself and every canvas item under it on `LightMasks.STREET`, so only the street lamps, the flashes and the street's sky light it.

## Floors (`objects/floor/`)

`FloorFactory.spawn(rect, definition, name, parent)` builds a `Floor` (`Node2D`, no collider —
shots, navigation and AI perception all pass over it) holding `size`, `art`, `color`,
`floor_material`, `art_opts`, `sound_surface`, `marks`, `tile_offset`, `light_layer` (`street`: on the street's light layer, above). It sits at `ObjectArtConfig.floor_z_index`
(`DrawLayers.FLOOR`, −5: beneath blood pools, casings and rugs). `floor_visuals.gd` repeats `ObjectArt.tile(...)` across the rect
(`texture_repeat` on, nearest filter, scaled by `pixel_size`), its grid starting `tile_offset` px into the tile (the
definition's `tile_from`; 0 for a room's floor, the street's pieces share one grid). A floor whose definition carries `marks`
(the street) gets a child `StreetMarks` (`decals/street_marks.gd`) that lays them.

A floor registers itself with Physics' `BloodSurface` (`_ready`; unregisters on exit) with `flow_groove(world, half)`,
which asks `ObjectArt.groove(art, local, opts, half)` (its painter's `groove`, 0 for one that models none: the street), e.g.
`FloorPainter.groove(local, opts, half)` — analytic, mirroring the painted geometry (tile/mosaic/
slab grid lines, plank row seams, parquet borders + strips; butt joints and cracks aren't modelled) — and
`ObjectArt.porous(art, opts)` (`FloorPainter.porous`: carpet), so blood follows the texture and soaks into carpet. A non-solid piece of cloth (a rug,
mat or runner, cardboard) registers its rect the same way as a porous surface and unregisters on exit; every non-solid piece
draws at `ObjectArtConfig.rug_z_index` (`DrawLayers.RUG`, −4, above floors, below blood) so a pool shows on it. A floor also registers its rect, `floor_material` and
`art_opts.pattern` with the Audio domain's `SoundSurface` (interface 16) so footsteps sound like
the floor (planks and parquet wood, ceramic tile, slate stone, concrete, carpet; no floor = outdoors), unless its
`sound_surface` is off: the street's pieces register none, so footsteps out there stay `outdoor`.

## Pixel art (`objects/art/`, private to Objects)

Every catalogue piece, every wall and every floor is drawn as procedural top-down pixel art,
rendered through the **Art** domain (`PixelArt` / `PixelCanvas` / `ArtConfig`, interface 12 —
see `domain-art` for the engine). A piece whose definition sets `art` (a painter id) is drawn as
art instead of a flat shape with its name label (the flat path stays for any definition without
`art`).

**The look: run-down, rust & grime with a share of neon** (one look for every piece: there is no style switch). Three parts:
- **The palette grade** (`decay.gd` `grade`, ObjectArtConfig.`grade_*`): `ObjectArt.texture` / `tile` hand every painter its
  colour (and a checker's `alt`) washed toward dun, rust and nicotine yellow, so World-Gen's catalogue keeps its plain colours
  ("walnut", "navy") and the house still draws run down. `ObjectArt.AS_GIVEN` painters (`wear`, `street`, `decor`) take their
  colours as given. A piece's and a wall's `get_surface().color` (debris) is the drawn colour (`ObjectArt.drawn_color`). The
  colour knobs of ObjectArtConfig (handles, metal, glass, sheets, prop palette …) hold the grimy values.
- **The finish** (`decay.gd`): each painter draws its shape, then its finish: upholstery torn, taped and stained
  (`SofaPainter.upholstery`, also the office chair), wood scratched, ringed and burnt (`ChairPainter.worn_wood`, also the table),
  storage scratched, stickered, rusty when metal (`CabinetPainter.casegoods`, also the shelf), counters stained, appliances rusted
  and greasy, porcelain limescaled and cracked (`ToiletPainter.porcelain`, also the bath), rugs stained and moth-eaten, the
  plant dead (`plant_wilt`), the garage car a beater (`car_beater`, a primer door). Some are rebuilt: the bed is a bare mattress
  on the floor, the lamp a tin shade over a bare bulb, a TV a boxy cracked CRT.
- **The neon share** (`ObjectArt.neon_for`, `ObjectArtConfig.neon_share`): `ObjectFactory` gives a share (25-60% by kind) of the
  light-giving pieces (lamps, TVs, desks with a monitor, mirrors, counters, cabinets, shelves, beds, appliances, and by their `kind`
  for the painters in `ObjectArt.BY_KIND`: the monitor wall, the server rack, the rig, the tool cart) a `neon` option
  (`cyan` / `magenta`), picked per piece from where it stands (deterministic; `opts.neon` overrides): a neon trim, under-glow,
  ring tube or screen. Only three looks per piece, so the texture cache stays small. The ring (`decay.gd` `neon_ring`) reads the
  canvas's `coverage()` bytes, not `covered` per pixel (pinned to that plain scan by `tests/objects/neon_ring_matches_plain_scan_test.gd`).
**No light is baked in** (no glow pools, sheen, halos, spill): what gives light is drawn bright and **marked emissive**: a
painter draws it inside `canvas.glowing(draw, area)` (PixelCanvas, interface 12): the bare bulb, a CRT's screen, a monitor's lit
edge (`props.gd`), an appliance's display, every neon trim and the neon tube. Each visuals
node (`environment_object_visuals`, `floor_visuals`, `wall_visuals`, and the overhang's) exposes `emissive() -> Texture2D`
(`ObjectArt.emissive` / `tile_emissive`: `PixelArt.emissive` of the same inputs, null when nothing glows) and `emissive_layer()`, a
child `Emissive` (`emissive_layer.gd`, its own canvas item) that draws those pixels over the art through the same geometry (a
piece's deformed silhouette, the tiled floor, the dented wall segments), **unshaded** (one shared `CanvasItemMaterial` in
`LIGHT_MODE_UNSHADED`): the dusk and the lights never change a light source, while the art under it is lit
(`tests/lighting/emissive_overlays_unshaded`). The Lighting domain dims it with the piece's light (its `modulate`, through the
light's `glow`, below).

**Repetition:** a floor or wall tile carries only even grain and seam dirt (`floor_painter._grimy`, `wall_painter._grime`): all
damage is placed in the world (below), so no mark repeats on the tile's grid.

- `object_art.gd` — the painter registry: `PAINTERS` maps an `art` id to its painter;
  `texture(art, size, color, facing, material, opts)` renders it via `PixelArt.render` (a cardinal
  facing), `tile(art, color, material, opts)` at the painter's own `tile_size(opts)` (floors), `emissive` / `tile_emissive`, `groove` /
  `porous` (a tiling painter's blood grooves and soak), `neon_for`, `drawn_color`.
- Painters (`*_painter.gd`, each `static paint(canvas, base, material, opts)`): `sofa` (also the
  armchair), `table` (+ `gaps`, `props`; desks, benches, the workbench), `chair`, `cabinet`
  (doors/drawers front lip, crown, glass top, chest lid), `shelf` (books / boxes / shoes),
  `counter` (backsplash, basin, overhang), `appliance` (`panel`: burners, fridge, microwave,
  washer, dryer, tv (a CRT)), `bed` (a bare mattress), the cyberpunk rooms' pieces (den, ripperdoc, vestibule, kitchenette) (`kind` in their options): `tech` (the den's
  `monitor_wall`, its screens glowing, and `server_rack`, its LEDs glowing), `recliner` (the den's jack-in `rig`, its neural halo
  glowing, and the ripperdoc's `surgical` chair, its lamp glowing), `clinic` (the ripperdoc's `tool_cart`, its screen glowing, and
  `cyberware_shelf`), `security` (the vestibule's `barricade`, `scanner` post, its emitter glowing, and `lockers`), `hotplate` (the
  kitchenette's, its hot ring glowing), `streetlight` (`part` `pole`: the base plate and post top in the footprint; `overhang`: the
  arm and the head, `head` `cobra`, its lens glowing in `streetlight_lens_color`, or `sign`, its tube and letters glowing in its
  `neon`), `office_chair`, `toilet`, `bath` (tub / shower), `rug` (medallion,
  stripes, plush), `plant`, `lamp` (tin shade, bare bulb), `coat_rack`, `car` (the garage's parked car: static furniture, unrelated
  to the Vehicles domain's drivable car, whose painters are its own), `fixture` (mirror / towel rack), `decor` (the walk-over
  clutter `trash`, `cables`, `cable_nest`, `cardboard`, `puddle`, and the `neon_tube` on a wall, `kind` + `v` detail variant), the
  tiling `floor` (`tile_size(opts)`; planks, parquet, tiles, checker, mosaic, carpet, concrete), `street` (`kind` `asphalt` /
  `sidewalk`) and `wall` (plaster / brick cap, symmetric across the thickness), and `wear` (one world-placed mark a canvas: the
  floor's `plank_gap`, `strip_gap`, `missing_cells`, `crack`, `stain`, `oil`, `worn`, `burns`, `scuffs`, the wall's `peel`,
  `wall_stain`, `wall_crack`, `cable`, the street's `patch`, `gum`, `weeds`, `dash`, `slab`, `chip`). Each knob reads
  `opts.get(key, ObjectArtConfig.<painter>_<key>)`, so a catalogue `art_opts` picks the variant
  or overrides it for one piece. Round footprints keep their art inside the inscribed circle.
- `decay.gd` — the run-down look's shared helpers (grade, grime, stains, tears, rust, stickers, cracks, the neon trims, screens).
- `props.gd` — small props dressing a surface (monitor, keyboard, mug, papers, book,
  clock, bowl, fruit bowl, vase, cutting board, tools, vise, crayons, plate),
  drawn by `table` / `cabinet` / `counter` from `art_opts.props` (`{ kind, at }`, `at` relative
  to the surface), raised so they cast shadows; colors from `ObjectArtConfig.prop_colors`; a monitor's screen glows in the
  host's screen colour (its neon, or the cheap screens' green).
- `object_art_config.gd` — `ObjectArtConfig`, the Objects painters' tuning: per-painter
  proportions and colors (the cyberpunk rooms' `tech_*`, `recliner_*`, `clinic_*`, `security_*`, `hotplate_*` and the `streetlight_*`), the
  prop palette, the floor/wall tile sizes, the floor, rug and overhang z-indices, the grade, grime and neon share, the wear marks and
  the street (the shared light, shadows, tones and finishes are `ArtConfig`).

## Wear and the street's marks (`objects/decals/`, interface 2)

Damage is decals placed in the world, never in a tile. `decal_layer.gd` is a draw-only batch of `[texture, rect]` marks.
- **A room's wear** (`WearFactory.spawn`, `decals/room_wear.gd`): World-Gen places the clusters (where wear gathers, seeded);
  the room's wear node decides each cluster's 1-3 floor marks, following the room's floor pattern (planks break along a plank
  row, tiles go missing on the tile grid, carpet wears bald, concrete cracks and takes oil; grid marks snap to the floor's grid,
  every mark its own size, turn and `v` variant), and with `wear_wall_chance` a mark on the free stretch of wall the cluster is
  by. Its two layers are `FloorWear` (the floor's rung) and `WallWear` (the walls'); built after every room's floor and walls, so
  each draws over them; one node per room, so it takes the lights of that room's floor (the per-floor budget, `docs/lighting.md` L4).
- **The street's marks** (`decals/street_marks.gd`, a child of a street Floor's visuals, from its definition's `marks`
  `{ seed, lane, edges }`): on a sidewalk the odd slab of another shade or with a broken corner on the shared slab grid,
  cracks, stains, gum, weeds and the curb along `edges`; on a road the worn lane dashes (`lane`), cracks, patches and oil, and
  litter and puddles in the gutter along `edges`.

Object fields for art: `art`, `art_opts` (from the definition) and `facing` (`opts.facing` from
World-Gen; visual only, a cardinal direction in the local frame — the `rotated` size swap still
owns the footprint). The visuals draw a drop shadow — the art's own alpha through the deformed
outline, offset away from the light in world space by `coverage × drop_shadow_per_coverage`
(capped; non-solid decor casts none) — then `Deformation.draw_shape(..., texture)` so dents and
chunks cut into the art. A piece repaints only when that can have changed — its `Deformable` recorded an impact or its rotation
changed (the shadow's offset is fixed in world space) — not every frame (a house has ~90 pieces); a hit also queues one deferred
collider rebuild however many hits land before it runs. Walls: `WallFactory`'s `style` sets `art` / `art_color` / `art_opts` on
the wall (its debris takes the drawn colour); `wall_visuals.gd` fetches a
`wall_tile_px × wall_thickness` tile and passes it to `Deformation.draw_wall(..., texture,
wall_tile_px)`. To add a painter: write `<name>_painter.gd` (its shape, then its run-down finish from `decay.gd`, anything that
gives light inside `canvas.glowing`), register it in `ObjectArt.PAINTERS`,
add its knobs to `ObjectArtConfig`, and set `"art": "<name>"` on catalogue definitions.

**Interfaces:** 2 (World Generation → Objects, incl. `WearFactory` and the floor's `sound_surface` / `marks` / `tile_from` / `light_layer`), 3 (hittable), 4 (Objects → Physics), 5 (pushable), 8 (interactable), 11 (`DrawLayers` for the floor and rug z, `LightMasks` for the occluders and the street's light layer), 12 (Objects → Art), 16 (`SoundSurface`), 20 (`get_lights()`, the occluders, the unshaded overlays) — signatures in `architecture`.
