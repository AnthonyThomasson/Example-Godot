---
name: domain-ui-hud
description: Deep implementation detail for the UI hud sub-domain (scenes/ui/hud/) — the player debug panel (DebugUI), the spectator match HUD (MatchHUD: per-NPC panels, timer, goals, winner banner, combat feed, match_ended), the seed readout, the spectator inspector (click-to-select NPC, pause, tactical-point details) and its world-space contact markers. Use when editing scenes/ui/hud/ or working on the in-game HUDs, match verdict, the combat feed, the seed label or click-to-inspect. Decoupled observers of the Character API and the EventBus. Complements the `domain-ui` overview and the `architecture` skill.
---

# UI · HUD sub-domain (`scenes/ui/hud/`)

The in-game observers: each reads only the Character public API / signals, the AI controller's `debug_status()` / `current_act()` / `goal_text()` / `debug_zones()` / `known_contacts_for_display()` and the EventBus `&"hit"` topic. See `domain-ui` for what all UI scripts share.

- `debug_ui.gd` — the **player debug panel** (`DebugUI` node). Bottom-right stats block: current
  item slot, an ammo line (`Ammo: 7/12  (+2 mags)`, "reloading…" mid-swap, "—" for an item without ammo, read through
  `ammo()` / `ammo_capacity()` / `spare_magazines()` / `is_reloading()`), punch active flag, active interaction, reach, stamina (and whether running), posture (`Standing` / `Crouching`, read through `posture()`). Top-left hit banner: last body hit, method
  (punch left/right or gunshot), damage, and elapsed time. Listens to `hit_landed` on the character;
  freed in spectator mode. Font sizes: stats 34pt, hit banner 32pt.

- `match_hud.gd` — the **spectator match HUD** (`MatchHUD` node). `begin(combatants, time_limit := 0.0, show_details := true)` wires it to
  any number of characters (a human included); it is **re-entrant** (an endless run calls it for each new match),
  emits `match_ended(verdict)` once when a faction is eliminated or `time_limit` seconds pass undecided
  ("TIME UP - DRAW"), `set_countdown(text)` shows a line under the verdict (Main's next-match countdown), and
  `show_details` off (a match with a human) hides the goal readout and combat feed, leaving the timer and result; each combatant gets a compact floating panel (300×145 px, 28pt font) — name,
  faction, health bar, current act (the controller's `debug_status()` — the full decision path,
  word-wrapped) — whose bottom-centre is placed 24 px above the NPC's on-screen origin each
  frame via `get_global_transform_with_canvas()` (clamped inside the viewport). Also: a top-centre
  running timer (34pt), a top-left goal readout listing every NPC's name and goal (28pt, spans the left half of the screen and word-wraps), a centre
  winner banner (62pt gold), and a bottom-left combat feed (28pt orange, last 6 hits from EventBus
  `&"hit"`). Declares the winner once an entire faction is eliminated.

- `seed_display.gd` — the **seed readout** (`SeedDisplay` node). `show_seed(level_seed)` writes the
  run's seed into a 32pt label anchored to the bottom-right corner (semi-transparent), so a layout
  you like can be re-entered in the setup window.

- `spectator_inspector.gd` — the **spectator inspector** (`SpectatorInspector` node), built by `main.gd`
  only in spectator mode via `setup(combatants, flags)` (`flags` = the current overlay toggles; `set_flag(flag, on)` updates one live from the toggle bar and re-applies it to the selected NPC).
  **Space** toggles `get_tree().paused`. A **left-click** on an NPC (nearest within `PICK_RADIUS` of the
  cursor's world point, via the framing camera) selects it — revealing ONLY that NPC's *enabled* overlays
  (each toggle set from `flags`) and hiding every other NPC's; clicking it again or empty ground clears
  it. No NPC shows any overlay until clicked (the view stays focused on one NPC). With an NPC selected, a
  left-click on one of its tactical points (nearest zone within `ZONE_PICK_RADIUS`, from its
  `debug_zones()`) highlights that point (overlay `set_focus`) and fills a detail panel — top-left,
  directly beneath the match HUD's goal readout — with the zone's kind, label and Von's reasoning (`desc`). It runs `PROCESS_MODE_ALWAYS` so Space/clicks work while
  paused (freeze the match, then inspect). Decoupled like the other observers: reads the combatants'
  public `global_position`, the camera, and each NPC's `debug_zones()`, and flips the debug-overlay
  toggles (every per-NPC flag of the overlay registry) by the same
  duck-typed names `main.gd`'s `_configure_debug` uses. Reads `Keybinds.PAUSE` (Space; shares it with
  `INTERACT`, unused in the player-less match). Mouse-ignoring hint + detail labels (with text shadow).

- `contact_markers.gd` — the **contact markers** (`ContactMarkers` Node2D, world space, built by the inspector). When an NPC is
  selected it draws a coloured ring + name label at each character that NPC has in memory (visible ones bright, remembered ones
  faded), showing the NPC's own knowledge rather than the contacts' true state. The inspector pushes fresh contacts every frame
  (`set_contacts`, from the controller's `known_contacts_for_display()`), so the rings stay live and hold steady while Space-paused.

## Interface recap

- `main.gd` calls `MatchHUD.begin(combatants, time_limit, show_details)` / `set_countdown(text)` and listens to `match_ended`; `SeedDisplay.show_seed(seed)`; builds `SpectatorInspector` (spectator mode only) with `setup(combatants, flags)` / `set_flag(flag, on)`. `DebugUI` attaches by exported `character_path`.
- Tests: `tests/ui/match_hud_verdict_test.gd`.
