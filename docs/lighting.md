# Lighting

Every match and test world is lit at **dusk** with real 2D lights and shadows: no light is baked into any art. Behaviours L1 to
L10 are the spec; each has its tests named under it, following the convention of `docs/grenades.md`. The tests are in
`tests/lighting/` (`tools/run_tests.sh --domain=lighting`, 10 tests), through `tests/_lighting/lighting_probe.gd`, which keeps the
plan's numbers as its own consts (the ambient, 15 lights an item, 12 a floor) and reads the game only through the published names
below, so a test checks this file and not the code. The code is the Lighting domain (`scenes/lighting/`, skill `domain-lighting`);
the masks are General's `LightMasks` (`architecture` interface 11), the lights and shadows of the world's things are their own
domains' (interface 20).

All distances are px and times seconds. The numbers are `LightingConfig`'s (`scenes/lighting/lighting_config.gd`) and, for what
each piece gives, `ObjectArtConfig.light_specs`.

## What is built

`WorldLighting.light(root, seed_value, rooms)` (Main after the nav bake, the Testing world the same way) adds one `WorldLighting`
node under the world root, in the group `world_lighting`, with the reads `lights()` (every piece and fixture PointLight2D),
`fixtures()` (`{ room, light }`), `flashes()` (the pooled flash lights) and `budget()` (`{ per_floor, dropped }`, `dropped` holding
`{ piece, index }` per declared light left without a PointLight2D). The world's own things carry the rest:

- a light-giving piece declares its lights with `get_lights()` (Objects, plain dicts in the piece's frame: `offset`, `turn`,
  `colour`, `energy`, `radius`, `shape`, `rhythm`, `room_light`, `street`, `height`, `glow`);
- every wall run, every solid piece and every living character builds its own `LightOccluder2D`, like its collider, on the bit
  `LightMasks` gives its kind;
- the street's floors are on the street light layer (`LightMasks.STREET`); everything else on the house's (`HOUSE`, Godot's
  default).

## Behaviours

**L1. Dusk.** One CanvasModulate tints the world `ambient_color` **(0.40, 0.37, 0.55)**, a cool blue-violet. One
DirectionalLight2D, `Sky`, in `sky_color` **(1.0, 0.5, 0.42)** comes low from the south-west (`sky_from` (−0.38, 1.0), so it shines
toward +x, −y; the front of a house is south) at energy 0.42 and lights only the street's layer, **unshadowed** (a directional
shadow runs to the edge of the view, so a body out there would throw one across the whole street). **The house has a roof:** no sky
reaches its rooms, which are lit by the ambient, their fixtures and their pieces (a sky let in by the doorways would throw a band
of light the length of the room, a 2D light having no height).
Tests: `lighting/dusk_ambient_and_sky` (seed 4: the configured ambient; one CanvasModulate in it; every sky light in the sky
colour, from the south-west; the one reaching the street's floors unshadowed; none reaching the rooms' floors).

**L2. A light per light-giving piece.** Every piece that gives light declares it (`get_lights()`): a lamp's bulb (a room light), a
screen (a TV, a desk's monitor, the den's monitor wall: a wide spill across its front, shimmering), a neon tube (a tube-shaped pool
along it, in its tone), a server rack's LEDs, the rig's halo, a cart's display, the scanner's beam, the hot ring, the surgeon's
lamp (a room light), a street lamp's lens or sign (it lights the street too) and a piece's neon trim. Its colour is what the
painter draws glowing. Each light has a **height**: `overhead` (a lamp's bulb, the surgeon's lamp, a street lamp's head or sign:
above the heads) or `low` (every other: screens, tubes, LEDs, the hot ring, trim). The Lighting domain gives each declared light a
shadowed PointLight2D (hard shadows, a texture `round`, `wide` 2:1 or `tube` 3:1) **as a child of the piece**, unless the budget
drops it (L4). Every pool **fades smoothly**, without rings. A low light glows from its middle, fading to its rim (`glow_offsets`);
an **overhead light pools downward**: its cone meets the floor, so its pool is nearly flat out to half its radius (`pool_offsets`)
and fades quickly at the rim. A street lamp's and a sign's pool is tight under its head (**130** px in radius, centred on the
head); a standing lamp's is 160.
Tests: `lighting/house_lights_per_piece` (seed 4: every lamp, screen, neon tube and streetlight declares its light; for every piece
declared = placed under it + dropped; every light has a texture and casts shadows; every light is a piece's or a fixture's),
`lighting/overhead_lights_pool_downward` (a lamp, a street lamp and a sign declare `overhead`, a TV `low`; every overhead pool, a
fixture's too, still ≥ 0.9 of its centre at half its radius, the TV's under 0.7; every pool, the TV's too, with no jump over 0.08
of its centre between 64 samples from its centre to its rim; a street lamp's and a sign's pool ≤ 140 px in radius and within 4 px
of the middle of its `Overhang`).

**L3. Room fixtures.** A room that no kept `room_light` stands in gets a ceiling fixture at its centre: a bare bulb glyph drawn
unshaded over everything (`DrawLayers.OVERHEAD`) and its light (`fixture_color` (1.0, 0.62, 0.22), energy 0.8, a pool the room's
longer side × 1.1 + 60 across, clamped 300..900): an overhead light, **shadowed by the walls only** and pooling downward (L2, L6).
Tests: `lighting/house_lights_per_piece` (each fixture a PointLight2D inside its room; every room lit by a kept room light or a
fixture), `lighting/overhead_lights_pool_downward` (a fixture's pool is flat).

**L4. At most 12 lights a floor.** Godot 4.4 lights a canvas item with at most **15** point lights (the renderer stops gathering at
`MAX_LIGHTS_PER_ITEM − 1`; directional lights are apart) and drops the rest; **3** are kept for the flashes, so no floor (a room's,
the arena's or a piece of the street, counted with its walls and wear out to `floor_reach` 8 px past its rect) is reached by more
than **12** piece and fixture lights. A light reaches a floor when its pool's box (its texture × `texture_scale`, turned) meets the
floor and its item mask meets the floor's light layers: the house's lights never reach the street, only the street lamps (and the
flashes) do. The fixtures of rooms no piece lights are counted first; then the declared lights, **strongest first** (declared
`energy`), so a room over budget **drops its weakest**; a room whose room lights were all dropped then gets its fixture where its
floors have room. Each room's walls and wear are their own items over its floor's rect, so they take its floor's count. The
batched decal layers (blood, scorch, debris) are drawn in 128 px chunks, smaller than any room: a chunk is reached by the lights of
the floor it lies on, one straddling a wall by those of both rooms (not budgeted on its own).
Tests: `lighting/house_lights_per_piece` (`per_floor` ≤ 12; every floor, rooms and street, reached by ≤ 12, ≤ 15 with the flashes),
`lighting/floor_budget_drops_weakest` (ten lamps and six neon tubes in one room: the floor reached by exactly 12; declared = placed
+ dropped; something dropped; no dropped light brighter than a kept one).

**L5. Lights move with their piece.** A light is a child of its piece, so a shoved lamp carries its light at the same place in its
own frame, while it slides and at rest, and it stays one of the lighting's lights.
Tests: `lighting/shoved_lamp_light_follows` (a lamp shoved with `apply_impulse((900, 120))`: each light within 0.5 px of its place
in the lamp's frame every 2 frames and at rest; the lamp moved ≥ 40 px).

**L6. Shadows by height: walls, tall pieces and the living; never the dead.** Each wall run casts a shadow (an occluder over its
collider's rect, `LightMasks.WALL`); each solid piece over its footprint, a child so it follows a shove (`EMITTER` for a piece that
gives light: its own light sits inside it; `TALL` for one as tall as **75** `coverage` or more, taller than a standing person's 60:
a wardrobe, a fridge, shelving, lockers, a shower; `FURNITURE` for the rest); walk-over decor (a rug, a tube, litter) none; each
living character an oval over its body, `0.72 r` deep along its facing by `1.05 r` across the shoulders, turned with its facing
(`CHARACTER`), freed when it dies. Each occluder is wound so the shape itself stays lit and only what lies behind it falls dark. A
2D occluder has no height, and its shadow runs to the rim of the light's pool as if the light stood on the floor, so who shadows
whom is chosen by the light's height: an **overhead** light (a fixture, a lamp, the surgeon's lamp, a street lamp or sign) by the
**walls only** (they hang over the furniture and the characters); a **low** light (a screen, a tube, LEDs, the hot ring, trim) by
the walls and the **tall** pieces; a flash (at hand height, and brief) by everything. The pieces and the characters keep their
drawn drop shadows. A flash whose centre a living character stands within **1.3** of its radius leaves the characters out of its
shadows that frame (a body would black out the light it stands in: a blast at its feet).
Tests: `lighting/occluders_walls_pieces_characters` (every wall run covered at ¼, ½, ¾; the armchair, the wardrobe, the lamp and
the TV each carry their own occluder, the rug none; a living puppet stands in an occluder, before and after a walk, and so does a
second one; once it dies none under it nor over where it lies; the lamp's light shadowed by the wall's occluder mask and not the
wardrobe's, the armchair's or the walker's; the TV's by the wall's and the wardrobe's and not the armchair's or the walker's),
`lighting/flashes_on_shot_and_explosion` (every flash by a wall, the wardrobe, a chair and the gunner).

**L7. Light sources draw unshaded.** What gives light is drawn by each visuals node's `Emissive` overlay (Objects' `emissive_layer()`),
which draws through an unshaded CanvasItemMaterial: neither the dusk nor any light changes a light source, while the art under it is
lit like everything else. Nothing glows around a source but its real light.
Tests: `lighting/emissive_overlays_unshaded` (seed 4: every overlay unshaded, the visuals under it not).

**L8. Rhythms, seeded per light.** A light flickers in one of the rhythms its piece allows (`steady`, `buzz`, `failing`, `blink`,
`shimmer`, `pulse`: screens shimmer, signs blink, tubes and bulbs now and then fail or buzz), picked and seeded from the world's seed
and the piece (its place and the light's index), so the same world lit with the same seed flickers the same, and two pieces never in
step. The light's energy and its piece's light-source overlay dim together.
Tests: `lighting/rhythms_seeded_per_piece` (one room built twice in worlds of their own and lit with the same seed: every light's
energy equal to its twin's in every frame over 240 frames; within one copy no two changing lights alike).

**L9. Flashes.** A pool of **3** lights (shadowed by everything, L6, lighting the house and the street): a `shot` lights one at
the muzzle, warm (1.0, 0.82, 0.55), 340 across, falling off to dark over **0.07**; an `explosion` one at the burst, a frag orange
(1.0, 0.62, 0.3) over **0.5**, a stun white (0.92, 0.95, 1.0) over **0.3**, at least 600 / 700 across (4 / 3.5 × the event's
`radius`). The next flash takes the pool's next light in turn. Tests: `lighting/flashes_on_shot_and_explosion` (within 3 frames of
the `shot` a flash lit within 24 px of the muzzle, all dark within 0.25; the same at the frag's burst, dark within 1.5).

**L10. The switch.** `lighting.enabled` (default on; `LightingConfig.enabled` and General's `LightMasks.shadows`) off builds none of it:
no WorldLighting, ambient, sky, point light or occluder anywhere, the characters' included.
Tests: `lighting/lighting_switch_off` (after a shot, none of those node types under the world).

## Measured cost

These figures were measured before shadows by height (L6): every piece light was then shadowed by the furniture and the
characters too, and a shadowed sky lit the house. The lighting now builds fewer shadow casters per light and no sky in the house,
so they are an upper bound until it is measured again.

The perf tests run headless and see only the CPU side, so the GPU cost is measured by hand. On 2026-10-15 a 10v10 match in
`garage_home` was measured, set up as `perf/match_10v10_stress` sets it up (seed 7, scripted Von). It ran windowed on Vulkan
(`--rendering-driver vulkan`, Apple M2 Max) with `--fixed-fps 60`, so each frame is one physics step, and with vsync off. Each run
was timed over 1200 frames after a 10 s warm-up. GPU ms is the root viewport's measured render time
(`RenderingServer.viewport_get_measured_render_time_gpu`). The baseline is the same match, measured the same way, on the commit
this lighting builds on (2ea038d, which has no lighting), run in turn with this code's unlit runs. The machine was shared: its load
average was 3.8 to 4.6 (12 cores) for every run. A row with two figures is two runs.

| Window | Lighting | Frame ms avg / p95 / max | GPU ms avg / p95 / max |
|---|---|---|---|
| 1152×648 | on | 20.7 / 27.2 / 37.4 and 25.9 / 36.7 / 47.6 | 2.44 / 3.31 / 4.32 and 2.42 / 3.63 / 4.60 |
| 1152×648 | off | 21.3 / 30.4 / 38.8 and 23.7 / 33.4 / 46.2 | 0.94 / 1.30 / 2.33 and 1.20 / 1.95 / 3.19 |
| 1152×648 | off | 22.4 / 32.0 / 39.1 and 27.0 / 36.2 / 48.5 | 1.18 / 1.80 / 2.96 and 1.00 / 1.36 / 2.87 |
| 1152×648 | baseline (2ea038d) | 29.8 / 39.9 / 54.3 and 22.6 / 41.6 / 53.4 | 1.41 / 2.28 / 3.91 and 1.14 / 1.49 / 2.70 |
| 2560×1440 | on | 41.0 / 53.0 / 66.8 | 7.82 / 10.51 / 12.14 |
| 2560×1440 | off | 38.1 / 49.3 / 61.5 | 5.10 / 6.10 / 7.29 |

The lighting costs the GPU about 1.4 ms a frame at 1152×648 and about 2.7 ms (4.4 ms at p95) at 2560×1440. Both are within the
3.7 ms planned for the biggest house. The windowed 10v10 does not hold 60 fps with the lighting on or off, and the baseline does not
either: its frames are as long, so the miss does not come from the lighting or the restyle. The frame is CPU-bound: the same match
takes 11.5 ms a frame headless, and windowed the GPU accounts for 1 to 8 ms of it. So cheapening the lighting (a cheaper shadow
filter, merged wall occluders) would not bring that match to 60 fps.
