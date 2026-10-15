---
name: domain-ui-hud
description: Deep implementation detail for the UI hud sub-domain (scenes/ui/hud/) — the player debug panel (DebugUI), the spectator match HUD (MatchHUD: timer, winner banner, match_ended), the spectator inspector (click-to-select NPC, pause, tactical-point details, the selected NPC's outfit) and its world-space contact markers, and the shared outfit lines (outfit_lines.gd). Use when editing scenes/ui/hud/ or working on the in-game HUDs, match verdict, or click-to-inspect. Decoupled observers of the Character API and the EventBus. Complements the `domain-ui` overview and the `architecture` skill.
---

# UI · HUD sub-domain (`scenes/ui/hud/`)

The in-game observers: each reads only the Character public API / signals (incl. `outfit_view()`), the AI controller's `debug_zones()` / `known_contacts_for_display()` and, for the stun screen, the EventBus `&"stun"` topic. See `domain-ui` for what all UI scripts share.

- `debug_ui.gd` — the **player debug panel** (`DebugUI` node). Bottom-right stats block: current
  item slot, an ammo line (`Ammo: 7/12  (+2 mags)`, "reloading…" mid-swap, "—" for an item without ammo, read through
  `ammo()` / `ammo_capacity()` / `spare_magazines()` / `is_reloading()`), a grenades line (`Grenades: 1 stun, 2 frag`, "—" with none, read through `item_count(slot)` for the slots of `LoadoutConfig.grenade_options()`), punch active flag, active interaction, reach, stamina (and whether running), posture (`Standing` / `Crouching`, read through `posture()`). Top-left hit banner: last body hit, method
  (punch left/right, kick or gunshot) and damage; the bottom-right "Last Hit" block adds the time since. Attaches to its character by the
  exported `character_path`; listens to `hit_landed` on the character; freed in spectator mode. Font sizes: stats 34pt, hit banner 32pt.
  Bottom left (26pt, growing up from the bottom edge: free), an `=== OUTFIT ===` block of
  `OutfitLines.of(outfit_view())`, refreshed every frame (`docs/outfits.md` O13). Tested by `tests/ui/debug_panel_outfit_test.gd`.

- `match_hud.gd` — the **spectator match HUD** (`MatchHUD` node). `begin(combatants, time_limit := 0.0, show_details := true)` wires it to
  any number of characters (a human included); it is **re-entrant** (an endless run calls it for each new match),
  emits `match_ended(verdict)` once when a faction is eliminated or `time_limit` seconds pass undecided
  ("TIME UP - DRAW"), `set_countdown(text)` shows a line under the verdict (Main's next-match countdown), and
  nothing else is shown but a top-centre running timer (34pt) and a centre winner banner (62pt gold): no goal readout or combat feed. Declares the winner once an entire faction is eliminated. `main.gd` calls `begin` / `set_countdown` and listens to
  `match_ended`. Tested by `tests/ui/match_hud_verdict_test.gd`.

- `spectator_inspector.gd` — the **spectator inspector** (`SpectatorInspector` node), built by `main.gd`
  only in spectator mode via `setup(combatants, flags, right_clear)` (`flags` = the current overlay toggles; `right_clear` = the screen width from the right edge its outfit
  panel keeps clear, which Main hands it as the overlay toggle bar's `RESERVED_WIDTH`; `set_flag(flag, on)` updates one live from the toggle bar and re-applies it to the selected NPC).
  **Space** toggles `get_tree().paused`. A **left-click** on an NPC (nearest within `PICK_RADIUS` of the
  cursor's world point, via the framing camera) selects it — revealing ONLY that NPC's *enabled* overlays
  (each toggle set from `flags`) and hiding every other NPC's; clicking it again or empty ground clears
  it. No NPC shows any overlay until clicked (the view stays focused on one NPC). With an NPC selected, a
  left-click on one of its tactical points (nearest zone within `ZONE_PICK_RADIUS`, from its
  `debug_zones()`) highlights that point (overlay `set_focus`) and fills a detail panel — top-left,
  below the match HUD's timer — with the zone's kind, label and Von's reasoning (`desc`). It runs `PROCESS_MODE_ALWAYS` so Space/clicks work while
  paused (freeze the match, then inspect). Decoupled like the other observers: reads the combatants'
  public `global_position` and `outfit_view()`, the camera, and each NPC's `debug_zones()`, and flips the debug-overlay
  toggles (every per-NPC flag of the overlay registry) through `OverlayRegistry.apply` (`domain-ui-overlays`), as Main does: a selection
  applies `flags` to the selected NPC and all-off to every other, `set_flag` re-applies `flags` to the selected one. Reads `Keybinds.PAUSE` (Space; shares it with
  `INTERACT`, unused in the player-less match). A mouse-ignoring detail label (with text shadow).
  While an NPC is selected, an outfit panel (22pt, shadowed, mouse-ignoring) lists `<name> — OUTFIT` and `OutfitLines.of(outfit_view())`, at the bottom
  right with its right edge `right_clear + OUTFIT_GAP` (10 px) from the screen edge, clear of the
  toggle bar's column, growing up and to the left; refreshed on select and every frame (`_refresh_outfit`), so plate wear shows live;
  hidden with no selection. Tested by `tests/ui/inspector_outfit_test.gd`.

- `outfit_lines.gd` — the **outfit lines** (a `RefCounted` with one static, preloaded by the debug panel and the inspector). `OutfitLines.of(view)` turns a
  character's `outfit_view()` into one line per slot in the view's order: a garment `Head: Helmet`, a plate `Front plate: Ceramic IV plate 68%`
  (`"%d%%" % roundi(condition * 100)`), `—` for nothing worn. It reads nothing but the view.

- `hud_probe.gd` — the **controller probe** (a `RefCounted` with one static, preloaded by the inspector).
  `controller_of(character)` returns the character's child in the group `npc_controllers` (the AI controller, which joins it in its `_ready`),
  or null for the player, a null or a freed character: the node `debug_zones()` and `known_contacts_for_display()` are read off.
  The inspector still checks `has_method("debug_zones")` on it before it picks a tactical point.

- `contact_markers.gd` — the **contact markers** (`ContactMarkers` Node2D, world space, built by the inspector). When an NPC is
  selected it draws a coloured ring + name label at each character that NPC has in memory (visible ones bright, remembered ones
  faded), showing the NPC's own knowledge rather than the contacts' true state. The inspector pushes fresh contacts every frame
  (`set_contacts`, from the controller's `known_contacts_for_display()`), so the rings stay live and hold steady while Space-paused.

- `stack_markers.gd` — the **stack markers** (`StackMarkers` Node2D, world space, built by `main.gd` under `World` for a human match). Draws the
  slots of the doorway the human's `PlayerStack` has reserved a place at (`docs/tactical-entry.md` E16): a numbered ring on the floor for each
  slot where it stands (both sides of the door on a split stack, E19; numbered in the order they were claimed), the human's own bright and filled, the ones an AI holds dimmer, a free one faint; nothing without a reservation. A decoupled observer:
  `watch(stack)` then it polls the stack's `view()` and redraws on change; it draws at `DrawLayers.ABOVE` (interface 11), over the standing world, so a
  character on a slot never hides its ring; `drawn()` is what is shown (what the test reads,
  `tests/ui/stack_markers_draw_test.gd`).

- `stun_screen.gd` — the **stun screen** (`StunScreen` CanvasLayer, layer 90, built by `main.gd` under `World` for a human match; G14 of
  `docs/grenades.md`). `watch(character)`, then it reads the character's `stun_view()` each frame (`blind`, `blind_total`): the screen is
  **white** by `blind / blind_total` (1 at the burst, falling steadily to 0 as the blindness ends), over a **frozen afterimage** of the frame on screen
  when the flash landed (`get_viewport().get_texture().get_image()`, taken on the character's `&"stun"` event with `blind` > 0 and held solid until the
  white is half gone, then faded out to the live view; none on a headless display, where `afterimage` is still true). A new flash while still white
  (≥ 0.2) keeps the old frame. A deaf-only stun, another character's flash and a dead/freed character draw nothing. `drawn()` is `{ white, afterimage,
  remaining }` (what the test reads, `tests/ui/stun_screen_whiteout_test.gd`). A decoupled observer; the white is drawn on an inner full-rect `Control` (mouse-ignoring).

**Interfaces:** 7 (observers of the Character API and the AI controller), 10 (EventBus `&"hit"`, `&"stun"`), 11 (`DrawLayers.ABOVE` for the stack markers), 17 (stack markers), 18 (stun screen) — signatures in `architecture`.
