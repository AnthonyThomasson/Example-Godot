---
name: domain-general
description: Deep implementation detail for the General domain (scenes/general/) — input (Keybinds), despawner, camera, and the dev command server. Use when editing scenes/general/ or working on input/keybinds/rebinding, the dev command server (gcmd), camera follow, or the despawn cap. HUDs and menus live in the UI domain (scenes/ui/) — see `domain-ui`. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# General domain

Infrastructure: input (Keybinds), despawner, event bus, camera, dev command server.
`Keybinds`, `Despawner` and `EventBus` are the only autoloads (`project.godot`).
HUDs and menus have moved to the **UI domain** (`scenes/ui/`) — see the `domain-ui` skill.

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

## Camera and despawner

- `camera_controller.gd` — by default follows the character; attaches by exported node path and
  reads only the public API/signals. It also has a **framing mode** (`frame(targets)`): instead of
  following one target it eases to the midpoint of the live targets and zooms to fit them plus
  `frame_margin` (clamped by `min_zoom`/`max_zoom`), dropping any whose `is_dead` is true — used by
  the spectator match view.
- `despawner.gd` (autoload) — global cap for transient bodies (debris, casings, blood pools);
  domains register spawns with it.

HUDs and menus (`debug_ui.gd`, `match_hud.gd`, `setup_menu.gd`, `seed_display.gd`) have moved to
`scenes/ui/` — see the `domain-ui` skill for their implementation detail.

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
