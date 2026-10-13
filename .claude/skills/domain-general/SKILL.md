---
name: domain-general
description: Deep implementation detail for the General domain (scenes/general/) — input (Keybinds), saved settings (Settings), despawner, camera, the dev command server, and shared physics-layer ids (PhysicsLayers). Use when editing scenes/general/ or working on input/keybinds/rebinding, the saved settings file (debug switch + key bindings), the dev command server (gcmd), camera follow, the despawn cap, or a cross-domain physics-layer constant. HUDs and menus live in the UI domain (scenes/ui/) — see `domain-ui`. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# General domain

Infrastructure: input (Keybinds), saved settings (Settings), despawner, event bus, camera, dev command
server, shared physics-layer ids. `Keybinds`, `Despawner` and `EventBus` are the General autoloads (`project.godot`; the Audio domain adds a fourth, `Sound`).
HUDs and menus are the **UI domain** (`scenes/ui/`) — see the `domain-ui` skill.

`physics_layers.gd` (`class_name PhysicsLayers`, no instance/autoload — same style as the other
`class_name` static holders) names physics-layer bits so they aren't redefined as magic numbers
per caller. `SOLID := 1` is the layer walls, solid furniture and bodies sit on — read by Interaction's reach query
(`character_interaction.gd`), AI perception's sight/line-of-fire rays (`agent_vision.gd`) and its
debug mirror (`ai/debug/vision_debug.gd`), the character's hand queries and leg sweeps (`character/body/`), a dropped
item's glance (`items/dropped_item.gd`), the bullet (`projectile/projectile.gd`) and `PhysicsConfig.wall_mask`.

## Input architecture

All input flows through the `Keybinds` autoload; gameplay never hard-codes action strings or
`KEY_*`. To add/change an input: add an action constant, add its default to `DEFAULTS`, and expose
a typed helper. `player_controller.gd` (Character domain) is the one gameplay consumer of
Keybinds (movement, `RUN` — held, default Shift —, `CROUCH` (C) — a toggle, in the "Movement" group after Run — and the action keys, incl. `RELOAD`, default R, in the "Combat" group next to Punch and Fire). Everything else reads its own actions: `main.gd` and the test runner `MENU`, the spectator
inspector `PAUSE`, the camera its pan and zoom actions; `settings.gd` persists the bindings, and
`command_server.gd` (dev-only) reads the action *names* to inject real input when driving the game from
outside. `Keybinds._ready` registers every action in the InputMap, so there is no `project.godot [input]` section: this file
is the source of truth. `PAUSE`
(default Space) is read by the spectator inspector (UI domain) and the test runner; it shares Space with `INTERACT`,
harmless because the spectator match has no player to interact.

Each action holds exactly one binding, a key (stored by physical keycode) or a mouse button. Keyboard
defaults live in `DEFAULTS`, pointer defaults in `MOUSE_DEFAULTS` (`FIRE` left-click, `ZOOM_IN` /
`ZOOM_OUT` wheel up/down); `actions()` is their union and what resets, overrides and loading cover.
`FIRE` is read two ways, both by the player controller: `is_fire_just_pressed()` (a click: one round) and `is_fire_pressed()`
(held: an automatic gun keeps firing, `Character.is_automatic()`); no new action, so rebinding `FIRE` moves both.
`CAMERA_LEFT/RIGHT/UP/DOWN` (default WASD, read through `get_camera_vector()`) and `ZOOM_IN/OUT` are read
by the camera and the test runner; the camera keys share WASD with `MOVE_*`, harmless because the spectator match has no
player to move. `LABELS` (settings-page order + names) and `GROUPS` must cover every action (a test
enforces it). Runtime API: `bind(action, event)` (key or mouse button incl. wheel up/down; refuses the
horizontal wheel and anything else), `reset(action)` / `reset_all()`, `default_event`, `event_of`, `text_of` ("W", "Space",
"Mouse Left"; skips the layout lookup on the headless display server, which logs an error for it),
`conflicts_of(action)` (other actions on the same input, minus the deliberately shared `SHARED` pairs —
Interact/Pause and each camera pan key with its move key), and `overrides()` / `apply_overrides(d)` (only the bindings that differ from the
defaults, as `{ "key": int }` / `{ "mouse": int }`; malformed entries are skipped one by one).
`Keybinds._ready` registers the defaults only.

## Saved settings

`settings.gd` (`class_name Settings`, a static holder like the config holders — no instance, no autoload)
keeps the **Debug** switch (`Settings.debug`, the master switch for the AI overlays) and the key-binding
overrides in one JSON file, `Settings.path` (`user://settings.json`):
`{ "debug": bool, "setup": { side, seed, defenders, invaders }, "overlays": { show_<x>: bool }, "keybinds": { action: { "key": int } | { "mouse": int } } }`. Only differences from
the defaults are stored, so a changed default still reaches an action the player never touched.
- **`load_file()`** resets every binding, applies the saved overrides and takes the saved `debug`; a
  missing file keeps the defaults, an unreadable one `push_warning`s and does the same, and a file that
  doesn't name `debug` leaves it as it was.
- **Main calls it, not `Keybinds._ready`**, once in `_ready` (after seeding `Settings.debug` from its own
  export), so the headless test runner — which never loads `main.tscn` — never reads a developer's file.
- **`Settings.setup`** holds the match-setup window's last choices (`set_setup(config)` saves them, dropping the
  start `mode`); Main feeds it back into the window so it reopens as it was left.
- **`Settings.overlays`** holds the toggle bar's switches (`set_overlay(flag, on)` saves one); Main seeds the overlays from it.
- **Mutators save at once:** `set_debug(on)`, `set_setup(config)`, `set_overlay(flag, on)`, `rebind(action, event) -> bool`, `reset(action)`,
  `reset_all()` (leaves `debug`). `binding_rows()` reshapes the bindings into the plain dicts the settings
  page draws: `{ action, label, group, text, conflicts: [labels], changed }`.
- Tests point `Settings.path` at a scratch file with `set_static` (`tests/general/settings_file_test.gd`);
  `Keybinds` state is not restored by the harness, so a test that rebinds ends with `Keybinds.reset_all()`.

## Dev command server

`command_server.gd` (a node in `main.tscn`, editor-only, cleaned up on exit) lets an external tool
control a running game with text commands. It is **off** unless the port — the `GODOT_CMD_PORT` env
var (per-worktree, set by `tools/editor.sh`), else `application/debug/command_port` — is >
0 and never exists in an exported build (`_ready()` bails when `OS.has_feature("editor")` is
false). It listens on 127.0.0.1 with a line-delimited protocol: each line is a curated verb
(`help`, `pos`, `tp X Y`, `slot N`, `move up|down|left|right [off]`, `stop`, `fire`, `punch`,
`interact`, `reload`, `crouch`, `aim X Y`, `match`, `ai`, `restart [seed]`, `menu`, `eval EXPR`) or, failing that, a GDScript `Expression`
evaluated against the node (e.g. `scene().get_node("Player").speed`). Movement and actions are
driven by injecting `Input` action presses through `Keybinds` names — the same path a human's
keyboard/mouse uses — so no game domain is coupled to it. Combatants and the player are discovered under the scene root **or a node in the `match_world` group** (Main's container for everything a match builds). `match` prints a one-line, parseable
status of every AI combatant it finds: each one's health, current act and
alive flag, plus the verdict and elapsed time — reading only the characters' public API and their
controller's `current_act()`. `ai` is the diagnostic counterpart: it dumps every AI combatant's
`debug_state()` as JSON (every level of its last decision walk — the state and question Von saw,
the options, Von's probabilities and pick — plus the facts gated on, the known contacts, the running
primitive and the pathing state), duck-typed the same way so the server stays a decoupled
observer. `tools/von_probe.py --capture` turns such a dump into replayable Von scenarios. `restart [seed]` reloads the scene for a fresh matchup, pinning the
next layout when a seed is given (stashed in `Engine` meta, which survives the reload; `main.gd`
reads it) and sets the `skip_setup` Engine meta so the reloaded scene builds immediately instead of
reopening the pre-game setup window — the harness never clicks it. Drive it from `tools/gcmd.py` (`python3 tools/gcmd.py "tp 600 300"`) for single
commands, or `tools/match.py` to run and score N matches in a row; each command is echoed as a
`[cmd] …` Output line. (The `godot-drive` skill covers driving it.)

## Event bus

`event_bus.gd` (autoload `EventBus`) — a minimal generic publish/subscribe bus for decoupled
cross-domain notifications: `post(topic, data)` broadcasts and the `posted(topic, data)` signal
delivers to any listener, which filters by `topic`. Emitters and listeners never reference each
other. Topics in use: `&"hit"`, posted by the Projectile System for each damaging hit and
by the Character for each landed punch (`{ position, victim, source, direction, damage, attacker }`, plus
`outcome` / `material` and, for bullets, `speed_factor`, `power`)
and consumed by the AI for combat awareness, hostility and gunfire heard, and by Audio for impacts;
`&"shot"` (a round left a gun), `&"footfall"` (a foot landed) and `&"reload"` (a
reload started / finished), posted by
Items and Character and consumed only by Audio; `&"sound"`, which Audio posts for every sound it
makes (what tests assert on); and `&"callout"`, an AI
controller's team radio (`{ speaker, faction, position, status, path, label, target_id, point }`),
consumed by allied AIs.

## Camera and despawner

- `camera_controller.gd` — by default follows the character; attaches by exported node path and
  reads only the public API/signals. It also has a **framing mode** (`frame(targets)`): instead of
  following one target it eases to the midpoint of the live targets and zooms to fit them plus
  `frame_margin` (clamped by `min_zoom`/`max_zoom`), dropping any whose `is_dead` is true — used by
  the spectator match view.
  - **Zoom** (both modes): the `ZOOM_IN`/`ZOOM_OUT` actions (mouse wheel) scale the zoom by `zoom_step`
    per notch. A trackpad's two-finger scroll arrives as `InputEventPanGesture` (no wheel events on macOS) and
    counts `trackpad_zoom_sensitivity` notches per unit of its `delta.y` (up zooms in); it isn't rebindable. The scale (`_zoom_bias`) is lasting and multiplies the
    automatic zoom (`_base_zoom`: 1 when following, the clamped fit when framing), so it works the same
    in both modes, can go beyond the fit's `min_zoom`/`max_zoom`, and is limited only by
    `wheel_min_zoom`/`wheel_max_zoom`. The zoom eases at `follow_speed`. Read in `_unhandled_input`, so
    scrolling UI gets the wheel first.
  - **Hand control** (framing mode only): the camera keys or the mouse within `edge_pan_margin` px of
    a screen edge pan the camera at `pan_speed` (screen px/s, so zoom-independent). Panning
    sets `_manual`, which suspends the automatic framing position (the zoom keeps auto-fitting, scaled
    by the wheel); after `manual_hold` (5) seconds without panning `_manual` clears and the framing
    eases back in. Edge
    panning only runs while the pointer has been seen moving over the window (`_mouse_in_window`,
    cleared on `NOTIFICATION_WM_MOUSE_EXIT` / focus-out), so a cursor that left at an edge or has
    never moved can't drag the camera. `pan_enabled` off removes the pan (wheel still works); the
    test runner turns it off for a world with a human-driven player, where WASD walks.
- `game_log.gd` (`GameLog`, a `class_name` static holder) — the one way any domain logs what is happening:
  `GameLog.say(message)` prints while `GameLog.enabled` (default true). The batch test runner turns it off
  unless `--verbose`; never route errors/warnings through it.
- `despawner.gd` (autoload) — global cap for transient bodies (flying debris chips, casings, blood splatters and pools);
  domains register spawns with it. The Physics domain's `DebrisLayer` reads `max_scene_objects` as the cap on landed chips too.

HUDs and menus (`debug_ui.gd`, `match_hud.gd`, `setup_menu.gd`, `seed_display.gd`) belong to
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
  `player_controller.gd` is the one gameplay consumer of `Keybinds`; `main.gd` and the test runner (`MENU`),
  `spectator_inspector.gd` (`PAUSE`) and the camera (pan and zoom) read their own actions for
  top-level/spectator control, `settings.gd` persists the bindings, and `command_server.gd` reads the
  action names to inject input.
- `main.gd` (the composition root) is the one caller of `Settings`: it loads the file at startup and routes
  the UI settings page's signals to `Settings.set_debug` / `rebind` / `reset` / `reset_all`, redrawing the
  page from `Settings.binding_rows()`. The UI window itself knows nothing of `Keybinds` or `Settings`.
