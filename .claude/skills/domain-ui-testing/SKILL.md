---
name: domain-ui-testing
description: Deep implementation detail for the UI testing sub-domain (scenes/ui/testing/) — the test browser window (searchable tree of tests by domain, checkboxes, Run all / Run N checked, Play, sandboxes) and the test result banner (running / verdict / queue / pause). Use when editing scenes/ui/testing/ or the in-game test browser UI. Plain-data widgets hosted by the Testing domain; they know nothing of its classes. Complements the `domain-ui` overview and `domain-testing`.
---

# UI · Testing sub-domain (`scenes/ui/testing/`)

The two widgets the Testing domain's browser and runner show. Both take plain dicts and emit signals (architecture interface 13: *nothing depends on Testing*); `domain-testing` covers the host side. See `domain-ui` for what all UI scripts share.

- `test_browser_window.gd` — the **test browser window** (`TestBrowserWindow` CanvasLayer, hosted by the
  Testing domain's `test_browser.tscn`). `open(tests, sandboxes, results, matcher, filter, selected, checked)` builds a
  full-screen window: a search box (filtered by the host's `matcher(test, text)`), a `Tree` of tests grouped
  by domain and, under a domain, by topic folder (`tests/ai/entry/`: a topic row without the ▶ button), marked ✓/✗/⏱/–/○ by last result (○ = GAP), `[Von]` tag, a separate SANDBOXES section after the tests (`open(tests, sandboxes, …)`), a details pane (description, world,
  tags, switches with off in red, Von need) and Run all / a status line / Back / Play. Play,
  double-click or Enter emit `play_requested(path)`; Back emits `back_requested`; typing emits
  `filter_changed(text)`; Run all, or the ▶ `Tree` button on a domain row, emits `run_requested(domain)`
  (`""` = every test; the row's button always means the whole domain, whatever the search shows), and
  the host answers with `set_run_status(text, running)` (running disables Run all and every domain row's ▶) and
  `set_results(results)` (redraws the marks). Takes plain test descriptor dicts — knows nothing of the
  Testing classes. **Checkboxes:** every test row (not sandboxes, nor a test whose script fails to load) has
  one; a domain or topic row's box is tri-state over *its shown tests* and toggles exactly those, and the header's
  **Check shown / Uncheck shown** button does the same for every shown test — so bulk checks respect the search,
  and ticks of hidden tests survive it. Toggles redraw the boxes in place (`_sync_checks`, no list rebuild) and
  emit `checked_changed(ids)` (the host persists them; `open(…, checked)` restores them). **Run N checked**
  (bottom row, disabled at 0 or during a headless run) emits `run_queue_requested(paths)` — every ticked test's
  script path in list order — for the headed, one-by-one run. Double-clicking a test's label (not its box) opens it: Godot raises `item_activated` for rows without a checkbox
  and for Enter, but not for a double-click on an editable check cell, so `_on_tree_input` handles that one. Tested
  with real mouse events by `tests/ui/test_browser_window_test.gd`; the topic rows by `tests/ui/test_browser_category_rows_test.gd`.

- `test_result_hud.gd` — the **test result banner** (`TestResultHUD` CanvasLayer, layer 10, top-left, built by
  the test runner in interactive mode). `show_running(entry)` names the test, `show_status(text)` shows a wait
  line, `show_result(result)` shows the verdict (PASS / FAIL / TIMEOUT / SKIPPED, GAP for a `gap`-tagged test that failed as expected, or MANUAL for a passing
  sandbox) with each check ✓/✗, the sim time and, for a failure, each actor's final state (`result.snapshot`). Rerun / Back buttons emit `rerun_requested` /
  `back_requested`; they take no focus so keys stay with the game underneath. In a queued run
  `show_queue(index, total)` adds a "Queue 3 / 12" line, hides Rerun and shows **Next ▸**
  (`next_requested`, enabled by `set_next_ready` once a verdict is up); `show_queue_done(summary)` ends it (the summary counts passed, failed, timed out, skipped and gap tests).
  A **Pause / Resume** button emits `pause_requested` (`set_paused(on)` relabels it, `set_pause_enabled(on)` hides
  it when a test locks pause); the HUD is `PROCESS_MODE_ALWAYS` so its buttons work while the world is frozen.

## Interface recap

- `scenes/testing/test_browser.gd` hosts `TestBrowserWindow` (`open`, `set_run_status`, `set_results`); `scenes/testing/test_runner.gd` builds `TestResultHUD` and the overlay bar.
- Tests: `tests/ui/test_browser_window_test.gd`.
