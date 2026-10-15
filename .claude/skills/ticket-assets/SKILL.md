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
- **One set at a time:** many exhibits are not laid out in one big hall. The showroom is a staging room with on-screen
  previous / next buttons and a label naming the set shown: a press removes the current set and spawns the next (today's
  version, then each variant). Only one set exists at a time, so it stays light and readable.
- **Check:** load check and lint pass (`godot-run`), and each sandbox runs headless without engine errors or warnings,
  through every set (the cycle below). No screenshot tours: the user looks at the showroom in the game window
  (`show-me`), not at screenshots.

### Setting up the staging room

A showroom is deleted before its audit, so this is the shape to build each time (file names are suggestions):

- **The sandbox stays thin.** `configure` lays the floor, the `player` actor, a camera on it and a few real props for scale.
  `run` adds the world nodes and returns. The `GameTest` object, and every lambda or signal bound to it, is freed once
  `run()` returns. Anything live (buttons, pads, timers, puppets) is a node under `t.world`, never a method of the test.
- **A stage node owns the sets** (`set_stage.gd`). The sets are a `const` table in picker order. A set resolves to a
  *cast*: `{ row: [{ look, outfit, caption }], walker: {…} }`, so a new kind of set is a new cast function, not a new
  layout. The stage adds everything it spawns beside itself (`get_parent().add_child`) and keeps a list of it. On a
  pick it `remove_child`s then `queue_free`s each node, so the next set's bodies never share the physics space with the
  last set's.
- **The picker** (`set_picker.gd`) is a `CanvasLayer` panel at the bottom with Previous / Next (`focus_mode` none, so
  Space and Enter never press them) and a label of `n / N   title` plus one line. It emits `picked(index)`, and the stage
  stages that set.
- **Bodies are real characters** (`character_base.tscn` + a `ScriptedController`), with props and the variant set
  before they join the tree and the position set before `add_child`. The variant goes in through a per-body switch on
  the domain node (a temporary `showroom_*` property, e.g. on the body's visuals) when a `static` would restyle every
  body at once. A row is 110 px apart:
  a character's legs sweep for anything within 86 px every physics step.
- **Motion is a driver node** (`pose_driver.gd`) that steers the puppets: a turntable in 8 held steps (turning all the
  time repaints a body every frame), and a walker on a loop. Captions are `floor_label.gd` nodes under each body.
- **The player tries variants on** by stepping onto floor pads (`look_pads.gd`), which set the same per-body switch.
- **Headless cycle:** a user arg `--showroom-cycle=<s>` presses Next every `s` sim seconds through every set and back
  to the first, then quits. `--play` is the runner's own flag, so launch the runner through Godot (`tools/run_tests.sh`
  only does batch runs, and those never see sandboxes), then scan the log:
  `"$GODOT" --headless --path . --fixed-fps 60 --log-file "$out/godot.log" res://scenes/testing/test_runner.tscn -- --play <words> --showroom-cycle=1`,
  then `python3 tools/scan_godot_log.py "$out/godot.log" --from=0`.
- **After a round of picks, add team sets** after the variant sets. Each shows the picks as a match would field them:
  that side's match kit (Main's loadouts: the invaders' `invader_loadout` outfit, a defender's
  `LoadoutConfig.outfit_of({})`), a few bodies plus a walker, and team-wide rules shown as the user stated them (e.g. a
  side that wears one picked look per match gets one set per look; a side that mixes picks per body gets a crew seeded
  per body, with fixed seeds so it is the same on every visit). This is how the user judges the picks together before
  the plan.
- **Environment showrooms** stage one house at a time through `WorldGen.generate(seed, plan, ...)` with fixed seeds (never
  World-Gen's internals), Previous / Next through floorplans and a second row of style buttons re-staging the same house.

## Feedback rounds

Before each round, run `show-me` so the game window is open: an editor already up without a game running gets the game
window opened on its own; never ask the user to press Play. Then it opens from Tests → SANDBOXES, by its `describe()`
name (or the runner's `--play <words>`, `test-debug`). Ask per exhibit: pick A/B/C, steer one, or new variants. The `showroom` worker revises; repeat until
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
