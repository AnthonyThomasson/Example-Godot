---
name: domain-ui-hud
description: Deep implementation detail for the UI hud sub-domain (scenes/ui/hud/) — the player debug panel (DebugUI), the spectator match HUD (MatchHUD: timer, winner banner, match_ended), the spectator inspector (click-to-select NPC, pause, tactical-point details, the selected NPC's outfit) and its world-space contact markers, the human leader's command menu (right-click: pause and order teammates) and order markers, and the shared outfit lines (outfit_lines.gd). Use when editing scenes/ui/hud/ or working on the in-game HUDs, match verdict, or click-to-inspect. Decoupled observers of the Character API and the EventBus. Complements the `domain-ui` overview and the `architecture` skill.
---

# UI · HUD sub-domain (`scenes/ui/hud/`)

The in-game observers: each reads only the Character public API / signals (incl. `outfit_view()`), the AI controller's `debug_zones()` / `known_contacts_for_display()`, a squad's `view()` callable (the command menu and the order markers) and its `resolve()` (the command menu) and, for the stun screen, the EventBus `&"stun"` topic. See `domain-ui` for what all UI scripts share.

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

- `command_menu.gd` — the **command menu** (`CommandMenu` CanvasLayer, layer 40, `PROCESS_MODE_ALWAYS`; `docs/leadership.md` LD11, interface 21),
  built by `main.gd` under `World` only when the human leads ("Lead the team"). `setup({ rooms, teammates, view, resolve, leader })` (the house's
  rooms as plain dicts, the characters it may order, the squad's `view()` and `resolve(request)` callables, the human: it opens only while the
  view names it the leader; the panel and the teammates' boxes are built here, hidden). `Keybinds.COMMAND` (right mouse, read in `_unhandled_input`, so a
  click the toggle bar or the panel takes never opens it) or `open_at(world)` pauses the whole tree (unpaused on close only if it paused it, and
  in `_exit_tree` if freed open) and fills the panel for what is under the point, hit-tested in this order: a living teammate within `PICK_RADIUS`
  (28 px) — "Select <name>" / "Deselect <name>", the menu staying open; a doorway, the one the squad resolves a stack at the click to (`resolve({ kind: "stack", pos })`: the
  nearest within its width; no `resolve`, no doorway) — "Stack into the <room> (quiet)" and "Stack into the <room> with stun", `<room>` the type
  of the room it resolves the stack into (`into`), so the label names the room of the order (`tests/ui/command_menu_label_matches_order`), the stun item
  disabled while no recipient's `item_count(ItemRegistry.STUN_SLOT)` is above 0 (D1); a room whose rect holds it — "Defend the <room>"; then
  "Cancel order" while a recipient holds an order in the view. Recipients: the selection, else every living teammate (never the human); the
  selection is the ticked boxes (`CheckBox` per teammate, text its name, `toggled`) plus a left-click on a body while open, lasts across
  closes, and drops a dead teammate (its box disabled) on the next open. Choosing an item (a `Button`, `pressed`, `FOCUS_NONE` so Space stays
  INTERACT) emits `order_requested` — `{ kind: "stack", to, pos, bang }` (`pos` the raw click: the squad resolves the doorway's side and room),
  `{ kind: "defend_room", to, room }`, `{ kind: "cancel", to }` (the recipients holding an order) — and closes it. Escape (`Keybinds.MENU`)
  closes it in `_input` and is set handled, so Main's "back to setup" never sees it. `selection_changed(nodes)` carries the selection while open
  and [] on close (Main connects it to the order markers). Layout: a panel docked at the left (`PANEL_LEFT` 24, `PANEL_TOP` 120, at least
  `PANEL_WIDTH` 440; title 28pt naming the target, a "Orders go to:" line 22pt, the items 26pt, a "Teammates" list 22pt, a hint 18pt), so it
  never covers the bodies and doorway it is about, and a ring on the clicked point (a full-rect, mouse-ignoring `Control`). `items()` is
  `[{ label, disabled }]` (empty while closed), `is_open()`, `close()`. It holds no AI reference and computes no AI id. Tested by
  `tests/ui/command_menu_items_test.gd` (plain dicts, a fake view and a real squad's `resolve`), `tests/ui/command_menu_label_matches_order_test.gd`
  (a real squad: the stack item names the room of the order posted) and, wired by Main, `tests/general/command_menu_wiring_test.gd`.

- `order_markers.gd` — the **order markers** (`OrderMarkers` Node2D, world space, z at `DrawLayers.ABOVE`, `PROCESS_MODE_ALWAYS` so the
  selection shows while the menu holds the tree paused; LD12, D5), built by `main.gd`
  under `World` with the command menu, only when the human leads. `watch(view)` takes the squad's `view()` callable, polled each frame;
  `set_selection(nodes)` is the menu's selection. It draws, for each living
  member with an order a dashed line to the order's target (`order.pos`: the doorway's centre for a stack, the room's for a defend), ringed
  and labelled once per target ("Stack (stun) · moving", "Defend · in position"; red when the member `refused`; a `done` order is not drawn),
  and a green ring round each selected teammate. `drawn()` is `[{ kind, point, node }]` (`kind` `order` (`point` the target,
  `node` the member) / `selected`), redrawn only when it changes. Who leads is not drawn here: the crown over each squad's leader is the
  overlays sub-domain's `leader_overlay.gd` (`domain-ui-overlays`), a debug overlay. Tested by `tests/ui/order_markers_draw_test.gd`.

**Interfaces:** 7 (observers of the Character API and the AI controller), 10 (EventBus `&"hit"`, `&"stun"`), 11 (`DrawLayers.ABOVE` for the stack and order markers), 17 (stack markers), 18 (stun screen), 21 (the command menu and the order markers) — signatures in `architecture`.
