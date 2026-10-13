---
name: domain-ui-menus
description: Deep implementation detail for the UI menus sub-domain (scenes/ui/menus/) — the pre-game setup window (Play as, seed, per-side count/weapon/magazine/spares, Start / Watch / Endless / Tests / Settings buttons, remembered choices) and the settings page (Debug switch + key rebinding with capture). Use when editing scenes/ui/menus/ or working on the setup menu, its start config, the settings page or key rebinding UI. Plain-data windows that only emit signals. Complements the `domain-ui` overview and the `architecture` skill (interfaces 13, 14).
---

# UI · Menus sub-domain (`scenes/ui/menus/`)

Two full-screen, code-built windows that take **plain data** and only emit signals — they know nothing of `Items`, `Keybinds` or `Settings`; Main (the composition root) feeds them dicts and applies what they report. See `domain-ui` for what all UI scripts share.

- `setup_menu.gd` — the **pre-game setup window** (`SetupMenu` node). `open({ side, seed, defenders, invaders, weapons, ticket })` shows a
  full-screen modal (40 px margins, VBox separation 20, the controls in a `ScrollContainer` fitted to the window
  height) with: a "Play as" dropdown (Defender / Invader), a "Seed" text field (blank = random), two side
  columns (Defenders | Invaders) each with Count, Weapon, Magazine and Spares rows (the Weapon / Magazine
  choices arrive as plain data in `weapons`, `[{ id, label, magazines: [{ id, label }] }]`, from Main — the window
  never sees Items; a weapon with no magazines hides the Magazine + Spares rows; `defenders` / `invaders` seed
  `{ count, weapon, magazine, spares }` or a bare count), and three start buttons: **Start** (play as the chosen
  side), **Watch** (AIs alone) and **Endless** (AIs alone, a fresh randomised match after each). (The Debug switch
  lives on the settings page.) A non-blank `ticket` in the defaults shows as a "TicketLabel" (32pt,
  muted) above the title. Pressing a start button emits `start_requested({ mode: "play"|"watch"|"endless", side, seed,
  defenders: { count, weapon, magazine, spares }, invaders: { … } })`. Main opens it on a fresh launch; a scripted `restart` sets the
  Engine `skip_setup` meta so the harness bypasses it. Title 64pt; controls 30pt; column headings 36pt; the Tests and Settings buttons 28pt;
  Start button 32pt. A **Tests** button (28pt) below Start emits `tests_requested`; Main changes scene to
the test browser. `current_config() -> Dictionary` returns the same
  `{ side, seed, defenders, invaders }` as the window stands (empty before `open`); Main saves it through
  `Settings.set_setup` on Start, on Tests and on Escape, and feeds `Settings.setup` back into `open`'s defaults, so the
  window reopens as it was left. Pressing a start button also **disables all three**, because Main may hold the start
  open for a moment (it waits for the Von decision server) and a second press would build the world
  twice. `set_status(text)` writes a 24pt line above the Start button (hidden when blank) — Main
  shows "Waiting for the decision server…" there so that pause is never silent. A **Settings** button
  (28pt) below Tests emits `settings_requested`; Main opens the settings page over this window.

- `settings_menu.gd` — the **settings page** (`SettingsMenu` CanvasLayer, layer 20 so it opens over the
  setup window, built by Main on `settings_requested`). A plain-data window like the test browser: it
  takes `open({ debug, rows })` (rows = `{ action, label, group, text, conflicts: [labels], changed }`,
  in display order) and `set_rows(rows)` to redraw, and only emits signals — `debug_changed(on)`,
  `rebind_requested(action, event)`, `reset_requested(action)`, `reset_all_requested`, `back_requested`.
  It knows nothing of `Keybinds` or `Settings`; Main applies each change and answers with `set_rows`.
  Layout: an opaque full-screen page (title 44pt, Debug checkbox 26pt) over a scrolling list grouped by
  `group` (28pt headings; rows 22pt: name, key button, a red "also: <labels>" note when another action
  shares the binding, Reset — disabled until the row differs from the default), then Reset all keys / Back.
  **Capture:** clicking a key button swaps it for "Press a key…" and the next key or mouse-button press is
  emitted as `rebind_requested` (the host may still refuse it); Esc cancels. Escape (cancel, else
  `back_requested`) and every key press during a capture are consumed in `_input`, which runs before
  Main's `_unhandled_input`, so Escape never triggers Main's "return to setup" and a captured key never
  reaches the game; so Esc itself can't be bound. A redraw keeps the list's scroll position. Key and
  Reset buttons take no focus (Space/Enter must not re-press them). Tested by `tests/ui/settings_menu_test.gd`.

## Interface recap

- `main.gd` calls `SetupMenu.open(defaults)` / `set_status(text)` / `current_config()` and connects `start_requested`, `tests_requested`, `settings_requested`; it opens `SettingsMenu.open({ debug, rows })` / `set_rows(rows)` and applies `debug_changed`, `rebind_requested`, `reset_requested`, `reset_all_requested`, `back_requested` to `Settings` (architecture interface 14). The Tests button changes scene to the test browser (interface 13).
- Tests: `tests/ui/setup_menu_config_test.gd`, `setup_menu_ticket_test.gd`, `settings_menu_test.gd`.
