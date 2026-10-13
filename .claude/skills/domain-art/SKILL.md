---
name: domain-art
description: Deep implementation detail for the Art domain (scenes/art/) — the procedural top-down pixel-art engine every painter draws through: PixelCanvas (the drawing surface, shapes, shading, material finishes), PixelArt (the cached renderer, cardinal vs. freely turning art, lighting steps) and ArtConfig (shared resolution, light, shadows, tones, surface textures). Use when editing scenes/art/, writing or debugging any painter (furniture, walls, floors, characters, held items), or tuning the shared pixel-art look. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Art domain

A leaf: the pixel-art engine. It knows nothing about furniture, characters or items — each domain
owns its own **painters** and renders them through this domain. Depends only on Godot's `Image`.

## Painters

A painter is any script with
`static func paint(canvas: PixelCanvas, base: Color, material: String, opts: Dictionary)`. It
draws in a **canonical frame** — front toward +y, width across the front — under `canvas.light`,
the world light already turned into that frame, so its shading lands correctly after the art is
turned. Painters live in their own domain: Objects (`objects/art/*_painter.gd` + the `ObjectArt`
registry), Character (`character/body/body_painter.gd`, `head_painter.gd`, `hand_painter.gd`, `limb_painter.gd`, `torso_painter.gd`), Items
(`items/pistol_painter.gd`, `smg_painter.gd`, `rifle_painter.gd` and the three `*_flat_painter.gd` for a gun lying
dropped). Knobs follow `opts.get(key, <DomainConfig>.<painter>_<key>)`.

## PixelArt (`pixel_art.gd`) — the renderer

- `render(painter, size, color, facing, material, opts)` — for a cardinal `facing`: paints at
  `size / ArtConfig.pixel_size`, lit for that facing, then turns the image (`rotate_90/180`).
  Furniture, walls, floor tiles.
- `render_turned(painter, size, color, angle, material, opts)` — the image stays canonical but is
  lit as if turned by `angle`; the caller draws it rotated (`draw_set_transform`, or
  `Deformation.draw_shape(..., texture_angle)`). Callers pass `snap_angle(angle)` (one of
  `ArtConfig.turn_steps` lighting steps) and rotate to the exact angle when drawing — smooth
  turning, few cached textures, world-consistent light. Characters, hands, the pistol.
- Static cache keyed by painter path + inputs (+ orientation); survives scene reloads. Each
  piece's random detail is seeded by its inputs *without* orientation, so it doesn't change as the
  piece turns.
- `render_turned` sits behind a bounded memo (`_turned_memo`, `TURNED_MEMO_MAX` entries) keyed by the call's exact arguments, so
  a repeat call (a character repaints every part every frame) costs one lookup instead of formatting the key string. It only
  shortcuts the string-keyed cache: values that key treats as equal (an angle within four decimals) still share one texture
  (`tests/art/pixel_art_turned_cache_test.gd`).

## PixelCanvas (`pixel_canvas.gd`) — the surface

An RGBA8 Image at art resolution plus coverage and height layers (R8 images filled natively, read
through snapshots).
- **Shapes:** `rounded(r, radius)`, `ellipse(r)`, `disc(c, radius)` are `ConvexShape`s (one span
  per row/column: native row fills, O(1) depth-from-edge + normal, edge band enumerated
  directly); `bowed(r, radius, bow)` is a mask `Shape` (run-length sweeps).
- **Drawing:** `fill(shape, color, height)`, `clear`, `paint_over(rect, color)`, `line`, `px`.
- **Shading:** `bevel(shape, from_k, to_k, lit, unlit)` (light-facing edges lit, far edges
  shaded; swap for a recess), `bevel_relative` / `outline_relative` (shade what's drawn — shapes
  in several colors), `outline`, `glare`, `cast_shadows()` (a taller part shades lower pixels on
  its far side from the light, via the height layer), `tones(base)` (outline … highlight ramp).
- **Surface finishes:** `surface(shape, material, base, along_x, wraps)` — wood grain, brushed
  metal, stone flecks, ceramic/glass glare, fabric weave, plastic grain — plus `speckle` (sampled;
  matches 8-bit pixels with a tolerance), `grain`/`knot` (`wraps` for seamless tiles).

## ArtConfig (`art_config.gd`)

Shared tuning: `pixel_size`, `light_from`, `turn_steps`, drop shadow (`drop_shadow_per_coverage`,
`drop_shadow_max` — read by the object visuals; `drop_shadow_alpha` — also by the character's shadow), cast shadow,
the tone ramp, and the surface-finish densities. Domain-specific proportions and colors stay in
each domain's config (`ObjectArtConfig`, `CharacterConfig.art_*`).

## Interface recap (authoritative in the `architecture` skill)

- **Objects / Character / Items → Art** (interface 12): `PixelArt.render`, `PixelArt.render_turned`,
  `PixelArt.snap_angle`, the `PixelCanvas` drawing API for painters, and `ArtConfig`.
