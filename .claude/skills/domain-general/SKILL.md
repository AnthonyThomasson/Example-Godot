---
name: domain-general
description: Deep implementation detail for the General domain (scenes/general/) — input (Keybinds), despawner, camera, debug HUD, and the dev command server. Use when editing scenes/general/ or working on input/keybinds/rebinding, the dev command server (gcmd), camera follow, the despawn cap, or the debug HUD. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# General domain

Everything else: input (Keybinds), despawner, event bus, camera, debug HUD, dev command server.
`Keybinds`, `Despawner` and `EventBus` are the only autoloads (`project.godot`).

## Input architecture

All input flows through the `Keybinds` autoload; gameplay never hard-codes action strings or
`KEY_*`. To add/change an input: add an action constant, add its default to `DEFAULTS`, and expose
a typed helper. `player_controller.gd` (Character domain) is the one gameplay consumer of
Keybinds; the only other is `command_server.gd` (dev-only), which reads the action *names* to
inject real input when driving the game from outside. `rebind()` / `rebind_mouse()` remap at
runtime (basis for a future config UI). `project.godot [input]` just keeps the editor's Input Map
panel in sync.

## Dev command server

`command_server.gd` (a node in `main.tscn`, editor-only, cleaned up on exit) lets an external tool
control a running game with text commands. It is **off** unless `application/debug/command_port` >
0 and never exists in an exported build (`_ready()` bails when `OS.has_feature("editor")` is
false). It listens on 127.0.0.1 with a line-delimited protocol: each line is a curated verb
(`help`, `pos`, `tp X Y`, `slot N`, `move up|down|left|right [off]`, `stop`, `fire`, `punch`,
`interact`, `aim X Y`, `match`, `restart [seed]`) or, failing that, a GDScript `Expression`
evaluated against the node (e.g. `scene().get_node("Player").speed`). Movement and actions are
driven by injecting `Input` action presses through `Keybinds` names — the same path a human's
keyboard/mouse uses — so no game domain is coupled to it. `match` prints a one-line, parseable
status of both spectator combatants (`Defender`/`Invader`): each one's health, current act and
alive flag, plus the verdict and elapsed time — reading only the characters' public API and their
controller's `current_act()`. `restart [seed]` reloads the scene for a fresh matchup, pinning the
next layout when a seed is given (stashed in `Engine` meta, which survives the reload; `main.gd`
reads it) and sets the `skip_setup` Engine meta so the reloaded scene builds immediately instead of
reopening the pre-game setup window — the harness never clicks it. Drive it from `tools/gcmd.py` (`python3 tools/gcmd.py "tp 600 300"`) for single
commands, or `tools/match.py` to run and score N matches in a row; each command is echoed as a
`[cmd] …` Output line. (The `godot-drive` skill covers driving it.)

## Event bus

`event_bus.gd` (autoload `EventBus`) — a minimal generic publish/subscribe bus for decoupled
cross-domain notifications: `post(topic, data)` broadcasts and the `posted(topic, data)` signal
delivers to any listener, which filters by `topic`. Emitters and listeners never reference each
other. The only topic in use is `&"hit"`, posted by the Projectile System for each damaging hit and
by the Character for each landed punch (`{ position, victim, source, direction, damage, attacker }`)
and consumed by the AI for combat awareness and hostility.

## Camera, despawner, HUDs

- `camera_controller.gd` — by default follows the character; attaches by exported node path and
  reads only the public API/signals. It also has a **framing mode** (`frame(targets)`): instead of
  following one target it eases to the midpoint of the live targets and zooms to fit them plus
  `frame_margin` (clamped by `min_zoom`/`max_zoom`), dropping any whose `is_dead` is true — used by
  the spectator match view.
- `despawner.gd` (autoload) — global cap for transient bodies (debris, casings, blood pools);
  domains register spawns with it.
- `debug_ui.gd` — the player HUD; attaches by exported node path, listens to `hit_landed`, shows
  the last hit + damage.
- `match_hud.gd` — the spectator-match HUD (`MatchHUD` node). `begin(combatants)` wires it to any
  number of NPCs; each combatant gets a compact panel (goal, current act, faction, health bar) that
  **floats just above the NPC it describes** — its world position projected to screen each frame via
  `get_global_transform_with_canvas()` (clamped on-screen), so panels track their NPCs and scale to any
  count instead of two fixed corner panels. Plus a shared combat feed (EventBus `&"hit"`), a running
  timer and the winner banner (on `died`). A decoupled observer: it reads the Character public
  API/signals, each controller's `current_act()` + exported `goal`, and the EventBus — never a domain's
  internals.
- `setup_menu.gd` — the pre-game setup window (`SetupMenu` node, a `CanvasLayer` that builds its own
  UI in code like the other HUDs). `open(defaults)` shows a modal with a "Human player" checkbox,
  a "Spawn doors" checkbox, a "Seed" text field (blank/0 = a fresh random seed each run),
  defender/invader count spinboxes, and three debug-overlay checkboxes
  ("Agent labels", "Agent paths", "Vision cones"); pressing Start emits
  `start_requested({ has_player, seed, spawn_doors, defenders, invaders, show_agent_labels,
  show_agent_paths, show_vision })`. Main opens it on a fresh launch and builds the world only once
  Start is pressed; a scripted `restart` sets the Engine `skip_setup` meta so reloaded scenes build
  immediately and the headless match harness never has to click it. A decoupled piece: it knows
  nothing of the domains, only the parameter dict it emits.
- `seed_display.gd` — the seed readout (`SeedDisplay` node, a `CanvasLayer`). `show_seed(level_seed)`
  writes the run's seed into a small always-on label in the bottom-right corner, so a layout you
  like can be read off and re-entered in the setup window. A decoupled piece: Main calls it once the
  world is built; it knows nothing of the domains.

## Spectator match mode

`main.gd`'s `spectator_mode` (on by default) turns the scene into a 2-AI contest: it frees the
human `Player` and `DebugUI`, points the camera at both NPCs in framing mode, and activates
`MatchHUD`. The `match` / `restart` command verbs plus `tools/match.py` make the matchup scriptable
for watching and regression-testing both AI agent-types (defender and invader). Composition-root
wiring lives in `main.gd`; the General observers only read published contracts.

## Interface recap (authoritative in the `architecture` skill)

- Observers (debug HUD, match HUD, camera) attach by exported node path and read only the Character
  public API/signals plus the AI controller's observer reads `current_act()` / `goal` (interface 7).
  `player_controller.gd` and `command_server.gd` are the only files that touch `Keybinds`.
