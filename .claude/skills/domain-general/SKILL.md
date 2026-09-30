---
name: domain-general
description: Deep implementation detail for the General domain (scenes/general/) — input (Keybinds), despawner, camera, debug HUD, and the dev command server. Use when editing scenes/general/ or working on input/keybinds/rebinding, the dev command server (gcmd), camera follow, the despawn cap, or the debug HUD. Complements AGENTS.md, which holds the cross-domain interfaces.
---

# General domain

Everything else: input (Keybinds), despawner, camera, debug HUD, dev command server.
`Keybinds` and `Despawner` are the only autoloads (`project.godot`).

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
`interact`, `aim X Y`) or, failing that, a GDScript `Expression` evaluated against the node (e.g.
`scene().get_node("Player").speed`). Movement and actions are driven by injecting `Input` action
presses through `Keybinds` names — the same path a human's keyboard/mouse uses — so no game domain
is coupled to it. Drive it from `tools/gcmd.py` (`python3 tools/gcmd.py "tp 600 300"`); each
command is echoed as a `[cmd] …` Output line. (The `godot-debug` skill covers driving it.)

## Camera, despawner, debug HUD

- `camera_controller.gd` — follows the character; attaches by exported node path and reads only
  the public API/signals.
- `despawner.gd` (autoload) — global cap for transient bodies (debris, casings, blood pools);
  domains register spawns with it.
- `debug_ui.gd` — attaches by exported node path, listens to `hit_landed`, shows the last hit +
  damage.

## Interface recap (authoritative in AGENTS.md)

- Observers (debug HUD, camera) attach by exported node path and read only the Character public
  API/signals (interface 7). `player_controller.gd` and `command_server.gd` are the only files
  that touch `Keybinds`.
