---
name: domain-lighting
description: Deep implementation detail for the Lighting domain (scenes/lighting/) — the world's dusk lighting, a leaf like Audio. WorldLighting (built by Main and the Testing world under the world root, group `world_lighting`) adds the ambient CanvasModulate and the street's sky DirectionalLight2D, a PointLight2D per light a piece declares (`get_lights()`, parented to the piece) and per room fixture, the per-floor budget (12 of Godot 4.4's 15 point lights per canvas item, the weakest dropped), the seeded rhythms (steady / buzz / failing / blink / shimmer / pulse) dimming each light and its piece's unshaded overlay, the flash pool lit on `shot` / `explosion`, and the per-frame character-mask clearing; LightingConfig is its tuning. The occluders and light layers are General's `LightMasks`, built by Objects (walls, solid pieces, the street) and Character (the living body). Use when editing scenes/lighting/, retuning the dusk, a fixture, a flash or the budget, adding a light-giving piece (its row in ObjectArtConfig.light_specs), changing who shadows whom, or asserting on lights in a test. Complements the `architecture` skill (interfaces 11 and 20); the spec and its tests are docs/lighting.md.
---

# Lighting domain (`scenes/lighting/`)

A **leaf**: it imports nothing but General (`EventBus`, `DrawLayers`, `LightMasks`) and Godot, and reads the world duck-typed, the
way Audio reads a vehicle. Nothing calls into it but Main and the Testing world (`WorldLighting.light`, interface 20) and the
Testing domain's switch row; the lights and shadows of the world's things are declared and built by their own domains. The spec
is `docs/lighting.md` (L1 to L10, each with its tests); the tests are `tests/lighting/` through `tests/_lighting/lighting_probe.gd`.

```
main.gd / test_world.gd ──WorldLighting.light(root, seed, rooms)──▶ WorldLighting ──(get_lights(), floors' size / light_mask)──▶ the world
Objects: walls, solid pieces ──LightMasks.occluder──▶ LightOccluder2D children   (Character: the living body's, freed on death)
Objects: street floors ──light_mask = LightMasks.STREET                           Objects: Emissive overlays ── unshaded material
Item (&"shot") / Explosion (&"explosion") ──EventBus──▶ WorldLighting's flash pool
WorldLighting ──(group `characters`: is_dead, radius, global_position)──▶ the character-mask clearing
```

## Files

| File | Role |
|---|---|
| `lighting_config.gd` (`LightingConfig`) | Static tuning: `enabled` (master switch), the dusk (`ambient_color` (0.40, 0.37, 0.55), `sky_color` (1.0, 0.5, 0.42), `sky_from`, `sky_energy`: the street's only), the fixtures (`fixture_color`, `_energy`, `_reach_scale` / `_pad` / `_range`, `fixture_rhythms`), the flashes (`flash_pool` 3, `flashes` rows `shot` / `frag` / `stun`: colour, energy, reach, `reach_per_radius`, `hold` (s at full
energy, none when absent: the stun's 0.08) and `life` (the fall-off after it); the stun's is energy 8, life 0.7, its burst's whole look,
since Physics draws no disc for it), the budget (`item_lights` 15, `per_floor()` = 15 − the pool, `floor_reach`), `body_clear` 1.3, and the pool textures (`textures` per shape, two smooth profiles, linear points: a low light's glow `glow_offsets` / `glow_levels`, an overhead light's downward pool `pool_offsets` / `pool_levels`). |
| `world_lighting.gd` (`WorldLighting`) | The node: `static light(root, seed_value, rooms := []) -> WorldLighting` (null while `enabled` is off), the reads `lights()`, `fixtures()`, `flashes()`, `budget()`, and the per-frame work (`_process`). |
| `light_budget.gd` (private) | The per-floor count: `add_floor(ground)`, `take(box, item_mask, always) -> bool`, `box_of(light, xf)`. |
| `light_rhythm.gd` (private) | One light's rhythm: `pick(kinds, rng)`, `new(mode, seed)`, `step(delta) -> factor`. |
| `ceiling_fixture.gd` (private) | A fixture's bulb glyph, drawn unshaded at `DrawLayers.OVERHEAD`. |

General's `scenes/general/light_masks.gd` (`LightMasks`, interface 11) holds the shared ids: the occluder bits `WALL` 1,
`FURNITURE` 2, `EMITTER` 4 (a solid piece that gives light), `CHARACTER` 8, `TALL` 16 (`TALL_COVERAGE` 75); the shadow masks
`OVERHEAD_SHADOWS` (walls), `LOW_SHADOWS` (walls, tall pieces), `ALL_SHADOWS`; the item layers `HOUSE` 1 (Godot's default) and
`STREET` 2; `shadows` (the occluders' switch) and `occluder(polygon, bit) -> LightOccluder2D` (null while `shadows` is off): it
winds the polygon clockwise on screen and culls counter-clockwise (`OccluderPolygon2D.CULL_COUNTER_CLOCKWISE`), the probed winding
that keeps the shape itself lit and darkens only what lies behind it.

## Building (`_build`, once)

1. `Ambient` (CanvasModulate) and the sky: `Sky` (range `STREET`, no shadows, rotated so its +y, which a DirectionalLight2D
   shines along, points along `-sky_from`). None on the house's items: the house has a roof.
2. One walk of `root`'s descendants (itself excluded): an Objects floor (`floor_material` and `size`) is a budget area (its rect grown
   by `floor_reach`, its light layers the union of its canvas items' `light_mask`); a node with `get_lights()` gives candidates
   (`[piece, index, spec, order]`), and a `room_light` among them marks its room (`rooms`, by the piece's position) lit.
3. Fixtures for the rooms no `room_light` marked, counted against the budget whatever (`always`).
4. The candidates **by declared energy, highest first** (ties in walk order): each is placed (`_piece_light`: a PointLight2D under
   the piece at its `offset` / `turn`, range `HOUSE`, plus `STREET` for a `street` light; its `height` picks its shadow mask and
   texture: `overhead` `OVERHEAD_SHADOWS` and the downward pool, `low` `LOW_SHADOWS` and the glow) when `take` says every floor its
   box reaches has room, else listed in `budget().dropped` as `{ piece, index }` and freed. A fixture is overhead (walls, pool).
5. A room whose room lights were all dropped gets its fixture if its floors have room.
6. The flash pool (`Flash1..3` under the node, disabled), and the `EventBus` connection (dropped in `_exit_tree`).

Each kept light is a `Lit` (node, full energy, rhythm or null, `glow`): the rhythm is drawn by
`LightRhythm.pick` from the declaration's `rhythm` weights with an RNG seeded `hash([seed, piece position (rounded), index])`
(a fixture: `hash([seed, "fixture", room key])`), and none is made for `steady`.

## Each frame (`_process`), allocation-free

- Every `Lit` with a rhythm: `energy = full × step(delta)`, its `glow` (the piece's `Emissive` overlay, or the fixture's glyph)
  `modulate`d to `0.3 + 0.7 × factor`.
- Every live flash: its full energy through its `hold`, then `energy × left²` with `left` = 1 − (t − hold) / life, disabled at the
  end of its hold + life (the shot and the frag hold none, so theirs is the plain fall-off).
- `_clear_bodies`: the character list is re-read from the group `characters` only when `get_node_count_in_group` changes; each
  frame fills each living character's position and its `radius × body_clear` reach (squared) into packed arrays, then every lit
  flash (the only lights the characters shadow, `ALL_SHADOWS`) drops `CHARACTER` from its shadow mask while a character's centre
  is within reach of the flash's, and gets it back once none is; `shadow_item_cull_mask` is written only when it changes. A flash
  runs it at once when lit.
Lights follow their piece by being its children; the occluders follow theirs the same way, so nothing is moved by hand.

## The world's side (built by the owning domains)

- **Objects** (`domain-objects`): `object_lights.gd` works out a piece's `get_lights()` once in `_ready` from its painter,
  options, size and facing and the per-kind rows in `ObjectArtConfig.light_specs`; a solid piece builds its occluder (rect, or a
  12-gon for a round piece; `EMITTER` when it gives light, else `TALL` from `LightMasks.TALL_COVERAGE`, else `FURNITURE`); a wall
  builds one per segment, the collider's rect (`WALL`); the street's floors (catalogue `light_layer: "street"`) put themselves and
  their canvas items on `STREET`; every `Emissive` overlay draws through an unshaded CanvasItemMaterial.
- **Character** (`domain-character`): an oval occluder (`CharacterConfig.shadow_depth` / `_width` / `_sides`) on `CHARACTER`,
  turned with `facing` when it turns, freed in `_die`.

## Adding to it

- **A light-giving piece:** a row in `ObjectArtConfig.light_specs` and its case in `object_lights.gd` (`_kind`, and its colour /
  offset in `of`); its painter draws the source inside `canvas.glowing` so its overlay shows it.
- **Who shadows whom:** the masks in `LightMasks` (General) and the shadow mask each light is given here.
- **A flash:** a `LightingConfig.flashes` row and its topic in `_on_posted`. A flash that is the whole look of something (the stun's)
  takes a `hold` and a longer `life` rather than a drawn effect beside it; it stays in the pool (no light of its own kept alive).

## Gotchas

- **15 point lights per canvas item** (Godot 4.4): any new big batched layer must stay under a floor's count (split it per room,
  as the wear is) or be drawn on a layer the house's lights do not reach (as the street is).
- **A DirectionalLight2D's shadows run to the edge of the view** (`max_distance` is a camera cull distance, not a shadow length):
  hence no shadows on the street's sky.
- **Headless**, the dummy renderer accepts every light and occluder: the tests read node properties (texture box, masks, energy),
  and the perf tests see only the CPU side (the rhythms, flashes and clearing above); the GPU cost of shadows is measured by hand (`docs/lighting.md`, "Measured cost").
- The test world is lit like a match: a test that must not have lights or occluders turns `lighting.enabled` off (so does a sandbox
  that lights itself).

**Interfaces:** 10 (the `shot` / `explosion` topics it listens to), 11 (`LightMasks`, `DrawLayers.OVERHEAD`), 20 (Main / Testing →
Lighting; the pieces' `get_lights()`; the occluders and light layers) — signatures in `architecture`.
