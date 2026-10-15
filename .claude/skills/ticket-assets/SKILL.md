---
name: ticket-assets
description: Extra rules for a ticket labelled `assets`, `graphics` or `audio` (with `ticket-story`) - ask for reference material while grilling, a showroom of 2–3 variants per new asset, sound, effect or animation before the plan, the picks recorded in the plan, the showroom deleted before the audit. Invoked from `ticket`.
---

# Ticket: assets

Follow `ticket-story`; load `domain-art` for anything drawn, `domain-audio` for anything heard, and the `domain-<name>`
skills that own where it goes (painters, the character rig, a gun, an effect). With `bug` or `spike` that kind wins: no
showroom. With `ai`: also `ticket-ai`. Nothing visible or audible to make (e.g. a voice-pool cap): no showroom; say so.

## Grilling: references

Before anything is built, ask for reference material: images, clips, sound files, links, games or films to match, what
to avoid. None given: search the web and offer a few to pick from. Links and file paths are recorded in the plan and the
showroom brief; supplied files stay in the scratchpad, never committed; images are read with `Read`.

## Showroom (before the plan)

Built by a `showroom` worker; you run the feedback rounds.

- **Files:** `sandboxes/showroom/<slug>_sandbox.gd` (`<slug>`: the ticket in snake_case, e.g. `muzzle_flash`),
  helpers in `sandboxes/showroom/<slug>/`. Extends `GameTest` like `sandboxes/player_gun_range_sandbox.gd`: a
  `player` actor, a `describe()` name, no assertions.
- **Exhibits:** one per new asset, sound, effect or animation: today's version (if any) beside 2–3 variants A/B/C. A
  floor label each: name, letter, one line on how it differs. At game zoom, beside the real things it will sit among.
  Animations loop; effects and sounds fire when the player steps onto the exhibit's pad. The user walks it as the
  player.
- **Variants live in the showroom files,** drawn and synthesized through the API `architecture` interface 13
  sanctions: a showroom painter on `PixelCanvas`, rendered by `PixelArt.render` / `render_turned`; a recipe in
  `SoundBank`'s shape (`SoundBank.recipe_for(profile)` is today's) rendered by `SoundSynth.render(recipe, seed_value)
  -> AudioStreamWAV` and played on the showroom's own `AudioStreamPlayer2D`, so a variant skips `Sound`'s volume and
  muffle. Today's sound plays by posting its real EventBus event. Production code is untouched before acceptance.
- **Exception:** what cannot be shown that way (e.g. an animation in the real character rig) goes in its domain behind
  a temporary, named variant switch (`static var`) the showroom flips (`set_static` in `configure`). The plan's risks
  name it.
- **Check:** load check and lint pass (`godot-run`).

## Feedback rounds

Open it in the `show-me` editor (Tests → SANDBOXES, by its `describe()` name; or the runner's `--play <words>`,
`test-debug`). Ask per exhibit: pick A/B/C, steer one, or new variants. The `showroom` worker revises; repeat until
each exhibit has a pick. All before the plan is accepted.

## Plan

Per exhibit: the pick, its parameters, the references, the rejected variants and why.

## Build and tests

The pick is rebuilt properly in its domain (painter, recipe, config row), not pasted from the showroom; a variant
switch collapses to the pick. Tests per `ticket-story` phase 3 cover the wiring, mapping and registration; the look
itself is the user's pick, not asserted.

## Feedback gate

The showroom shows the built asset, through the real code, beside the picked variant. An exhibit whose variant was a
switch shows the built version only, compared with the pick's parameters recorded in the plan.

## Before the audit

Once the user approves, a `showroom-removal` worker deletes `sandboxes/showroom/<slug>*` and any leftover switch. The
audit brief adds a check that no showroom file, switch or reference to them remains.
