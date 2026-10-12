---
name: domain-main
description: Deep implementation detail for the composition root (scenes/main.gd, scenes/main.tscn, scenes/match_spawner.gd) — the one place that wires every domain: the pre-game setup flow (Start / Watch / Endless / Tests / Settings), awaiting the Von decision server, building one match under a World node (house, nav map and re-baker, NPC placement, loadout arming, match HUD, spectator inspector, debug overlays), endless-run teardown and randomisation, the settings page wiring, and the Main exports. Use when editing main.gd or match_spawner.gd, or working on match start-up, spawn placement rules, loadout arming, the endless run or how the overlays are toggled. Complements the `architecture` skill (interfaces 1, 9, 13, 14).
---

# Main — the composition root (`scenes/main.gd`, `main.tscn`, `match_spawner.gd`)

`main.gd` (with the Testing domain's runner, interface 13) is the only code that knows every domain; nothing depends on it. It owns no
gameplay of its own: it asks World-Gen for a house, places NPCs, arms characters, and attaches the HUDs and overlays. The exports on
the `Main` node are the authoring surface for a run (`house_seed`, `force_plan`, `entrance_distance`, `defender_count`, `invader_count`,
`invader_margin`, `spawn_clearance`, `spectator_mode`, `player_side`, `defender_loadout` / `invader_loadout`, `endless_delay`,
`endless_time_limit`, `debug_overlays`, and one `show_<x>` per overlay).

## Setup flow

On a fresh launch Main loads the saved settings (`Settings.load_file()` after seeding `Settings.debug` from its export, so the headless test
runner never reads a developer's file), opens the UI setup window (`domain-ui-menus`) and builds nothing until a start button is pressed.
A scripted `restart` (the dev command server) sets the Engine `skip_setup` meta so the reloaded scene builds at once. The window offers:

- **Start** — a human joins the chosen side, on top of its NPC count, with the side's loadout and faction;
- **Watch** — AIs alone (spectator mode);
- **Endless** — AIs alone; 5 s after each match ends (the MatchHUD's `match_ended`) Main frees its `World` node and builds a fresh match with
  a new seed, random counts up to the chosen ones and random loadouts; an undecided match is called a draw after `endless_time_limit`;
- **Tests** — changes scene to `testing/test_browser.tscn`; **Settings** — opens the settings page over the window.

Main saves the window's choices (`Settings.set_setup`) on Start, Tests and Escape and feeds them back into the window's defaults.
Before `_spawn_world()` it **awaits the AI domain's `DecisionServerLauncher.resolved(live)`**, so no NPC makes its first decision against a
still-booting Von server; the launcher is a root node of `main.tscn`, probes at scene load and always resolves (a run with no server still
starts, with NPCs that hold steady). The settings page is wired here (interface 14): Main applies each `SettingsMenu` signal to `Settings`
and answers with `set_rows`.

## Building one match (`_spawn_world`)

Everything one match builds lives under a fresh `World` node (group `match_world`), so `_teardown_world` can free it in place:

1. resolve `house_seed` (0 → random) and show it (`SeedDisplay`); `WorldGen.generate(seed, force_plan, front_entrance, world)`; `WorldGen.get_rooms`;
2. `NavBuilder.build` the nav map, the `nav_debug.gd` overlay and the `nav_updater.gd` re-baker (interface 9);
3. a `match_spawner.gd` instance places the NPCs from one RNG seeded with the house seed (see below);
4. a human, when there is one, joins its side (`_join_player`: a clear spot for a defender, the scene anchor for an invader) and is reparented
   under `World` (draw order house < player < NPCs);
5. `_arm_characters`: every character gets its side's loadout through `LoadoutConfig.apply` → `Character.set_loadout` — a chosen gun with its
   magazine and spares, or by default one random gun drawn from an RNG seeded with the house seed XOR `LOADOUT_SEED_SALT`, so a pinned seed pins
   the loadouts without shifting placement. Tests and sandboxes never come through here and keep the weapon they ask for;
6. `_configure_debug`, `MatchHUD.begin(combatants, time_limit, show_details)`, in spectator mode the camera framing + `SpectatorInspector`
   (the player and its panel are freed), and the performance overlay + overlay toggle bar when Debug is on (built once, kept across an endless run).

Overlay flags live in `_overlay_flags` (one entry per row of `OverlayRegistry`); `_on_overlay_toggled` applies a flip live — the furniture holes to
the single NavDebug, the performance flag to its overlay, spectator mode via `SpectatorInspector.set_flag`, otherwise to every NPC's overlay
nodes by duck-typed `show_<x>` property (`domain-ui-overlays`).

## NPC placement (`match_spawner.gd`, a `RefCounted`)

Main builds one per match and sets `world`, `spawn_clearance` and `invader_margin` on it; it keeps the list `combatants` that the camera, HUD,
inspector and overlays observe.

- `spawn_defender(rooms, rng, index)` — a random room; `clear_spot(rect, rng)` returns its centre when clear, else the first clear point of
  `SPAWN_TRIES` (32) drawn from the rng (inset from the walls). **Clear** = at least `spawn_clearance` from every solid furniture footprint
  (`NavBuilder.furniture_holes`, read off the shapes, so it is right on the frame the house is built) and twice that from every combatant already
  placed; the centre again when nothing is clear. (A body spawned inside a piece is ejected with it and the piece's momentum flings it.)
- `spawn_invader(rooms, rng, index, count, front_entrance)` — around the perimeter of the rooms' bounding box grown by `invader_margin`, one even
  fraction per index plus a little jitter, so several attackers start on different sides; the front entrance is injected so the controller heads
  straight for it.
- `add_npc` instances the scene under `world`, hands its controller the house `rooms` (and `entry_point`) through the `control` duck-type, and appends it to
  `combatants`; the first of a kind is named plainly (`Defender`, `Invader`), the rest `<base> 2`, …
- Test: `tests/general/match_spawn_clear_test.gd` (two defenders in a room with a bed over its centre start clear and apart); `match_setup_test.gd`
  covers the setup dicts, loadout arming and the endless randomisation.
