---
name: domain-testing
description: Deep implementation detail for the Testing domain (scenes/testing/ + tests/) — game tests that declare a world (arena, hand-laid room layout or generated house), the actors and objects in it and which behaviours are on, run it, and assert what happened; plus the in-game test browser/runner and the headless CLI runner (tools/run_tests.sh). Use when writing or debugging a test, adding a behaviour switch, running the suite, or editing scenes/testing/. Any engine error/warning during a test fails it. Complements the `architecture` skill (interface 13).
---

# Testing domain (`scenes/testing/`, cases in `tests/`)

A second composition root beside `main.gd`. It builds a test's world **only through the published
interfaces** (WorldGen + its catalogue lookups, the Objects factories, NavBuilder, the character scenes
and controller contract, EventBus and character signals) and never reaches into domain internals.

## Running tests

- **Lint first:** every `tools/run_tests.sh` run starts with `tools/lint.sh` (about 5 s; skipped for `--list`,
  `--self-test`, `--play`, with `--no-lint`, and when the sources are the ones the last clean lint saw: the wrapper
  keeps a fingerprint of HEAD plus every uncommitted change in `$TMPDIR`, so a rerun of an unchanged tree does not
  lint again, while any edit, new file or commit does). It loads every project script with the engine's debugger on, the only
  way a headless run reports GDScript analyzer warnings (unused variable or parameter, integer division, a name that
  shadows a member or built-in, a redundant `await` ...), and prints them per file; any warning ends the run with exit 1
  before a test starts. The engine names no line, so the report gives candidate lines, and the exact `line:col` of each
  integer division (it recompiles the script once per `/`). Run `tools/lint.sh scenes/x.gd` for one script. Fix the
  code: `@warning_ignore` or a lowered level in `project.godot` is a last resort (see `m-audit`).
- **CLI:** `tools/run_tests.sh [filter words] [--include-von]` runs
  `godot --headless --fixed-fps 60 res://scenes/testing/test_runner.tscn -- --run-tests …`. A fresh checkout
  (no `.godot/` class cache) is imported first, since without it every script fails to parse. It prints one
  line per test (`PASS/FAIL/TIMEOUT/SKIPPED/GAP  <id>  (<sim s> sim, <ms> ms)`, failed checks indented with ✗), then a
  summary, and writes `report.json`. Exit code 1 means a test failed or timed out, or an
  error/warning was logged outside any test. **GAP** is a test tagged `gap` (a behaviour written into a spec that the
  code does not show yet, left red on purpose) that failed or timed out: expected, printed with its failed checks and a
  bundle like a FAIL, counted apart in the summary and never a failure of the run; a `gap` test that *passes* is a FAIL
  ("drop the gap tag"). `tools/run_tests.sh gap` lists them (tag prefix); `--failed` and `--fail-fast` leave them out. Filter words are word prefixes over id, name, domain,
  description and tags (`ai` matches the ai domain, not "chair"). Sandboxes live apart in `sandboxes/` and are never run.
  `requires_von` tests are skipped unless `--include-von` is passed (`--require-von` runs them and
  fails when no server is live), and are then paced in real time
  (see below). Run with the Bash sandbox disabled, like every Godot launch.
- **Per-run output dir:** the wrapper gives every invocation a fresh `mktemp -d`, passed as
  `--log-file <dir>/godot.log` (engine flag) plus `--out=<dir>`. The report, failure bundles and shots go
  under `<dir>` (`Report:` / `bundle:` lines print the paths) and the runner's `LogWatch` follows
  `<dir>/godot.log` (`--log-file` is consumed by the engine, so it is not in `get_cmdline_args()` and does
  not change the project setting — the runner derives the log from `--out`). So concurrent runs, and a
  game being played meanwhile, never share a log (a new process rotates the old `user://logs/godot.log`,
  and `LogWatch` tails by path) or overwrite each other's report. Without `--out` the runner falls back
  to `user://test_report.json` and `user://test_failures/`.
- **Quiet by default:** the game's own log of what happens (shots, punches, house seed, Von decisions, the
  `PERF …` numbers) goes through `GameLog.say` (General), which a batch run turns off; pass `--verbose` to
  see it (e.g. to read the `PERF` lines when re-baselining). Engine errors/warnings are never gated.
- **Selecting:** `--domain=NAME[,NAME]` (exact domain(s); the filter words are word prefixes, so `ai` also
  catches a test that mentions "aim"), `--id=ID[,ID]` (exact ids), `--failed` (wrapper only: the tests
  that FAILED / TIMED OUT in the previous run of this checkout, read from its merged report in `$TMPDIR`),
  `--list [words]` (id, von flag, tags; runs nothing). Domain/id selection is decided from the file
  path, so unselected test scripts are never loaded.
- **Speed:** `--jobs=N|auto` (wrapper only) splits the run over N parallel godot processes via the runner's
  `--shard=I/N`, merges their output into one combined total, one `Slowest:` list and one `--failed` report.
  `auto` = cores, at most 6 (the stress tests stay under half their budgets at 6 jobs on a 12-core machine). **Without `--jobs`, a run of the whole suite uses `auto` and any selection (filter
  words, `--id`, `--domain`, `--failed`, `--repeat`) one process**, since a process costs ~2 s to start; an explicit
  `--jobs` never starts more processes than the `--id` list has ids. Not used with `--list`/`--self-test`/`--play`/`--shots`
  (the `_a`/`_b` restore pairs need one process in id order). **Shards are balanced by measured cost:** the wrapper
  keeps each test's wall-clock ms (the mean of the previous and the latest measurement) in
  `$TMPDIR/example_godot_costs_<checkout hash>.json`, rewritten only after all shards have finished, and passes it to
  every shard as `--costs=<file>`; costliest tests go first onto the lightest shard (Von tests all stay in shard 0 and
  weigh it only when they run). With no costs file (a fresh checkout) it falls back to the declared `timeout`, an
  unmeasured id costs the median. Perf tests budget wall-clock ms about 4x their baseline, so heavy CPU contention is
  the thing to suspect if one trips only under `--jobs`. `--fail-fast` stops after the first FAIL/TIMEOUT (per shard).
- **Output:** `--summary` prints only non-passing tests and the totals; every run reports wall-clock ms
  per test (`wall_ms` in the report) and ends with a `Slowest:` line. `--verbose`, `--json` apply too.
- **Other flags:** `--skip-domain=a,b` (leave those exact domains out; wins over every other selection, `--changed`'s included),
  `--repeat=N` (each test N times; names `FLAKY` / `FAILING` ones), `--seed=N` (every
  `house()` uses that seed), and, in the wrapper only, `--changed` (see below). Options take the
  `--name=value` form.
- **`--changed`:** the wrapper maps each changed file (`git diff HEAD` plus untracked) to a domain and
  runs those domains plus the ones that compose them (its `affected()` table, from the architecture
  dependency graph) in **one** process; `main.gd`, root scenes, `project.godot`, worldgen, art, general, audio and testing
  run everything, and `scenes/testing/` / the Von stub add `--self-test`. **An edited test file
  (`tests/<domain>/<name>_test.gd`) runs only that test** (`--id=<domain>/<name>`; it can only change its own
  result), unless its domain is already running; `tests/_ai` and `tests/_audio` helpers run that domain,
  `tests/_perf` runs the `perf` domain, `tests/_harness` the self-tests, and an unknown helper folder everything.
  `GAME_TEST_CHANGED_FILES` (newline-separated paths) stands in for git's view of the changes, which is how
  `tools/test_log_gate.py` tests this mapping.
- **Which command?**

  | Situation | Command |
  |---|---|
  | One test | `tools/run_tests.sh --id=<domain>/<name>` |
  | Just saw failures, fixed something | `tools/run_tests.sh --failed` |
  | Finished an edit | `tools/run_tests.sh --changed --summary` |
  | Before committing / big change | `tools/run_tests.sh --summary` (the whole suite shards over `auto` jobs by default) |
  | Intermittent | `--id=<id> --repeat=10` (`--seed=N` pins the layout) |
  | What exists? | `tools/run_tests.sh --list [words]` |
  | Edited `scenes/testing/` | `tools/run_tests.sh --self-test` (`--changed` adds it) |

- **`--self-test`:** runs the harness's own tests (`tests/_harness/`, `internal: true` in `describe()`;
  hidden from the browser and normal runs): verdict rules, catalog selection and shard partitioning, LogWatch really seeing engine logs, and the
  statics / Von-stub restore pairs (`*_a` then `*_b`, run in id order). Run it after editing
  `scenes/testing/`. `--changed` does this automatically when `scenes/testing/` changed.
- **`--shots`:** `tools/run_tests.sh --shots words` runs windowed (not headless) and saves
  `<bundle dir>/<id>__fail.png` for each failed test (printed as `shot:`); `t.screenshot(label)` saves one
  on demand (returns "" when headless or `--shots` is off). Read the PNG to see what went wrong.
- **Coverage:** `python3 tools/test_coverage.py` lists untested domains, unused switches and interfaces
  no test calls.
- **Failures:** a FAIL/TIMEOUT prints each actor's final state and the `t.trace` series ranges, and writes
  `<out dir>/failures/<id>.json` (path printed as `bundle:`) with the full time-stamped event log, the
  final snapshot, traces and logged errors. See the `test-debug` skill.
- **In game:** the setup window's **Tests** button opens `test_browser.tscn`. Search, pick, then Play,
  double-click or Enter. The runner plays it with the result banner, keeps the world running, and
  offers Rerun and Back/Escape (Back changes scene to `main.tscn`, the setup window). The in-game overlay toggle bar works on the test's NPCs.
  `-- --play <filter>` on the command line opens the first matching test straight in the runner.
  The browser's **Run all** button, and the ▶ button on each domain row (which passes `--domain=<name>`),
  spawn a separate headless run of the whole suite or just that domain, Von tests included
  (`--include-von`; they skip if no server comes up) (its own
  `user://test_runs/<n>/` dir as above), show elapsed time, then fold `report.json` into the marks (only
  the ids in the report change) and the status line (failure bundles are under that dir). The buttons are
  disabled while a run is going.
- **Headed queue:** tick tests in the browser (checkbox per test, bulk buttons per domain and in the header; they
  respect the search) and press **Run N checked**. The browser stores the ordered paths in the `test_queue` meta
  (`TestCatalog.META_QUEUE`; the ticks themselves are `test_checked`, `META_CHECKED`) and opens the runner, which
  plays them one by one in the real window: each verdict is held `QUEUE_PAUSE` (2 s, or until the banner's Next ▸),
  then the world is freed and the next test starts. A failure does not stop the queue; Esc/Back cancels the rest.
  Results fold into the browser's marks as for a single Play; a summary shows after the last test.
- **Pause and overlays (headed runs):** the banner's **Pause / Resume** (and Space, unless the test has a `player`
  actor, where Space is INTERACT) freezes the world. The runner stays `PROCESS_MODE_ALWAYS`, each `TestWorld` is
  explicitly pausable, and the test clock (`ctx.time`, so waits and the timeout) stops with the tree; the tree is
  always unpaused on a new test, Back and exit. The overlay bar works on the test's actors; its **Navigation holes**
  (a `NavDebug` the `TestWorld` builds and the re-baker keeps current) and **Performance** (the runner's own
  panel) toggles work too.
- **Locking interactions:** `s.lock_interaction([&"camera", &"pause", &"overlays"])` in `configure` switches off
  what a person could do in a headed run that would change the result. `camera` drops the user's wheel /
  trackpad / camera-key events and the runner camera's hand-pan; `pause` hides the Pause button and ignores
  Space; `overlays` leaves out the overlay bar. A test that sends its own input must use
  `TestContext.inject(event)` (not bare `Input.parse_input_event`), which tags it so the lock lets it through.
  Held keys are polled state and cannot be told apart. The three `tests/general/camera_*_test.gd` use it; the
  browser's details pane lists "Locked while it runs".

## Writing a test

One file `tests/<domain>/<name>_test.gd` that `extends GameTest`. Id = `<domain>/<name>`.

**Sandboxes** (worlds you play by hand) are separate: `sandboxes/<name>_sandbox.gd`, same `GameTest` base, no assertions or timeout. `TestCatalog.discover_sandboxes()` lists them for their own browser section; `discover()` and the batch runner never see them (`--play <words>` can still open one).

```gdscript
extends GameTest

func describe() -> Dictionary:
	return { "name": "Pistol shot wounds a target", "tags": ["pistol"], "timeout": 6.0 }

func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(600, 250))

func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"hit"), 2.0), "the shot lands"):
		return
	t.check(t.actor(&"target").health < 50.0, "the target lost health")
```

- **`describe()`** (all optional): `name`, `domain`, `description`, `tags` (the tag `gap` marks a test written
  before the behaviour exists: it is expected to fail and reports GAP, see "Running tests"), `timeout` (sim s, default
  10), `requires_von`,
  `fail_on_errors` / `fail_on_warnings` (default true), `allowed_logs` (regexes).
- **`configure(s: TestSetup)`** is data only, and the browser also calls it to list the switches.
  - World: `layout(rooms, doors, { thickness })` (a hand-laid building: `rooms` = `[{ key, type, rect,
    floor? }]`, `doors` = `[{ pos, width }]` on the walls the rooms share or on an outer edge; walls in the
    house style, doorways open, so the nav bake and `WorldGen.get_rooms` / `get_openings` work as for a
    house), `arena(rect, { floor, walls, thickness })` (a walled room in the house style, with the same
    `rooms` meta a house has) or `house(seed, plan := "", entrance := Vector2.ZERO)`. Default is an
    800×500 arena.
  - Objects: `object(id, catalogue_key_or_definition, pos, opts)`. Objects are placed under the
    house/arena root before the nav bake, so they are carved.
  - Actors: `actor(id, kind, pos, props)`. Kind is `puppet` (scripted), `player` (human-driven),
    `defender`, `invader`, or a scene path. `props` are set on the character before `_ready` (for
    example `max_health`, `start_slot`: 1 unarmed / 2 fists / 3 pistol / 4 key / 5 SMG / 6 assault rifle, `faction`, and the ammo props
    `start_rounds` (what the starting gun is loaded with; -1 = full) and `spare_magazine_types` (e.g. `[]` for none,
    `[&"extended"]`; the default is two standard magazines for each gun, so a test counting spares sets it)). Actors built here
    keep `default_inventory()` (every item) and the weapon they ask for: only Main arms a spawn with its side's loadout
    (`Character.set_loadout`). To retune a gun for one test, `set_static(GunConfig, "guns", modified_copy)` (e.g. spread 0 for a
    straight shot). Use
    `set_props(id, "GoalController", {...})` for a child's exports. NPCs get `rooms` injected, as Main
    does.
  - Behaviour: `switch(name, on)` (table below) and `set_static(ConfigClass, prop, value)`.
  - Scripted Von: `von_script([{ pick: id, question: substring? }, …])` replaces the server with those
    picks (first rule whose id is offered; else the first offered option), so an AI test needs no server
    and is deterministic (`von_script(rules, latency_frames)` holds each answer back that many physics frames, `DecisionStub.latency_frames`, to test what an NPC does while a decision is in flight); `von_down()` makes every decision fail (the hold-steady fallback). Read what was
    asked with `t.von_requests()` (`{ state, question, options, pick }`). Ids are the decision tree's node
    ids (`combat`, `flank`, `engage`, …) and option ids. Keep `requires_von` tests for judging Von itself.
  - Presentation: `show_overlays(["show_vision", …])` and `camera_follow([ids])` (default frames all
    actors; the camera's hand-pan is off when a `player` actor is present, since WASD walks it).
    `lock_interaction([&"camera", …])` switches off user interactions in a headed run (see below).
- **`run(t: TestContext)`**, a coroutine. Always wait through `t`. A raw `await get_tree()…` can
  resume into a torn-down world.
  - Waits, all in sim time: `await t.seconds(s)`, `await t.frames(n)`,
    `await t.until(cond, timeout, msg := "") -> bool` (with `msg`, a timeout records a failed check).
  - Lookup: `t.actor(id)`, `t.puppet(id)` (the ScriptedController), `t.object(id)`,
    `t.controller(id, method)` (e.g. `&"current_act"` for an NPC brain), `t.world`, `t.rooms`, `t.time`.
  - Event log: `t.events_of(topic, filter)`, `t.happened(topic, filter)`, `t.spawned(name_part)`.
    Topics are every EventBus topic (`&"hit"`: position, victim, source, attacker, direction, damage;
    `&"callout"`), `&"died"` / `&"hit_landed"` per actor (`actor` = its id; hit_landed adds body,
    damage, hand, −1 = shot), and `&"spawned"` / `&"removed"` for direct children of the world root
    (blood splatters and pools, debris, projectiles, dropped items).
  - `t.trace(name, value)` samples a number over time (a distance, a health) for the failure output.
  - Assertions: `check(cond, msg)` (soft), `require(cond, msg)` (ends the test; follow it with
    `if not …: return`), `expect_eq`, `expect_near`, `expect_log(pattern, count)`, `skip(why)`.
    A test that asserts nothing fails.
- Puppet (`scripted_controller.gd`): `aim_at(node_or_point)`, `walk_to(point)` + `has_arrived()`
  (straight line, no pathing), `walk(dir)`, `set_run(on)` (holds run while moving), `set_posture(p)` (wants `stand` / `crouch`, written every frame like the AI does; `&""` stops asking), `toggle_crouch()` (one press of C), `stop()`, `select_slot(n)`, `punch()`, `shoot()` (one click), `hold_fire(on)` (hold the trigger: an automatic gun fires at its rate; a semi-auto one is unaffected), `reload()`,
  `interact(object, id)` (refusals land in `failed_interactions`), `end_interaction()`. Actions run on
  the character's next frame, and the character derives `facing` from the aim one frame later, so
  aim, wait a moment, then fire.
- Make randomness deterministic where the assertion depends on it (e.g. `projectile.flyover` off,
  since a character is partial cover).

## Performance tests (domain `perf`, `tests/perf/`)

Their own category: regression guards for speed and runaway object counts, one folder, one browser section, one
selector. They are ordinary tests that load other domains, so they live apart from them:

| Test | Load |
|---|---|
| `perf/match_5v5_stress` | the whole-match case: a generated house, five defenders and five invaders placed by `MatchSpawner`, default loadouts, debug overlays off as in Main, nav re-baker, blood, debris, sound and radio on, scripted Von |
| `perf/match_10v10_stress` | the same with ten a side: the largest match the game means to carry, held to the same standard |
| `perf/npc_crowd_stress` | twelve scripted-Von NPCs sensing, deciding and shooting in one open furnished arena (everyone sees everyone: the decision snapshot's worst case) |
| `perf/automatic_fire_stress` | SMGs and rifles on the trigger plus pistols clicking into furniture: one run covers the single-shot and the automatic path |
| `perf/hit_overload_stress` | hundreds of hits on one chair and one character: deformation, debris, blood and their caps |
| `perf/crowd_deaths_stress` | a whole 5v5 (ten characters) killed in one frame: ragdolls, blood, bleed-out |
| `perf/furniture_pile_stress` | 120 rigid bodies shoved at once |
| `perf/bake_and_path_stress`, `perf/generate_houses_stress` | one-shot work: nav re-bake and path queries, world-gen |

`tools/run_tests.sh --domain=perf` (or the word `perf`) runs just them. The pre-commit hook leaves them out
(`--skip-domain=perf`): their frame-time budgets fail when the machine is busy, so run them on their own before a push
that touches a per-frame path. They stay in the default run, balanced across shards
by measured cost like every test, and `--changed` adds the domain whenever a scene they exercise changes (`affected()` in
`tools/run_tests.sh`) or `tests/_perf/` changes. The shared helper is `tests/_perf/perf_probe.gd` (`const Perf :=
preload(...)`; not a test). `audio/bank` and `character/standing_body_repaints_on_change` keep a budget or a count but are
functional tests of their domain.

- **Measured:** wall-clock ms per frame (`Perf.frame_stats` -> avg / p95 / max; headless `--fixed-fps`
  outruns the clock, so frame-to-frame wall time is the CPU cost; rendering is not covered), one-shot ms
  (`Perf.time_ms`), and exact counts (`Perf.nodes()`, `Despawner.count()`, dent / blood-pool caps).
- **The standard:** a match runs without frame loss, so every frame-based test holds `Perf.SMOOTH_AVG_MS` (16.7, one 60 fps
  frame, the Performance overlay's target), `SMOOTH_P95_MS` (20) and `SMOOTH_MAX_MS` (33.4, two frames) through
  `Perf.within_frames`, at the scale of the largest match (twenty characters, `match_10v10_stress`), with no looser tail.
  One-shot work
  (`Perf.time_ms`) keeps a `const` budget at the top of its test, about 4x the baseline stated in the comment above it.
  `Perf.within` prints `PERF <label> <value> (budget <limit>)`, traces it, and fails the check with the value. Counts
  (nodes, dents, pools) are asserted tightly.
- **Re-baselining:** run `tools/run_tests.sh --domain=perf --repeat=5 --verbose` and read the `PERF` lines. The frame standard is not
  loosened to fit a slower game: make the game faster, or state in the test why one load is heavier than a match. Update the
  "before" numbers in a test's comment only when its load changes.
- **Finding what costs:** the wall time of a frame is script time, so attribute it by timing. A throwaway `Time.get_ticks_usec`
  accumulator wrapped around the suspect functions (never committed), dumped at the end of the measured window, ranks them
  in minutes; switching a feature off with `set_static`/`switch` shows what it is worth. Measure before reading: a per-frame
  cost is rarely where the code suggests.
- **Gotchas:** a lambda captures ints by value (count into an Array); `nav.rebake` is off in tests that
  shove or shoot furniture into overlaps (re-baking overlapping holes logs a nav sync error; the nav
  test covers re-baking), and the 5v5 test, which keeps it on, allows that log (`allowed_logs`); world-gen's first run in a
  process is slower (cold caches), so its budget covers the cold case; headless runs skip the sound pre-warm, so a test that
  plays sound calls `Perf.warm_sounds()` first or turns `audio.sound` off, or the first play of each variant (9 to 35 ms) lands
  in its worst frame. A speed-up must not change what the game does: where a fast path replaces a plain algorithm, a test
  pins its output to the plain one (`navigation/furniture_union_fast_path`, `physics/blood_splat_merge_fast_path`,
  `physics/convex_pieces_match_plain_scan`, `physics/shape_polygon_cache`).

## Tactical entry tests (tag `entry`)

`tests/ai/entry_*_test.gd` pin down `docs/tactical-entry.md` (E1 to E9; each header names its behaviour): staging and
the approach, the stack's slots, the pie, the crossing, the corners, the ready barrier and the radio, the solo entry
and a joining ally, clearing, covering the doorways on and rear security. Scripted-Von tests on the Terrace house (`Maps.house(s, false)`, bare
rooms so the geometry is clean), through `tests/_ai/entry_probe.gd` (`const Entry := preload(...)`): `rules(s, door)`
(SEARCH > ENTER > that doorway, engage in a fight), `npc` (an invader that walks; `cadence` offsets its decide timer),
`target`, `guard_rules(s, picks)` (a plain order that is not ENTER: for the E9 tests, with `asked(t, prefix)` to check the
order was really the one scripted and `check_entered(t, samples, id, door)` for "it went in by entry"), the test's own
doorway frame (`BACK`, `FRONT`, `HALL_LIVING`, `KITCHEN_LIVING`, and the doorways on that a team covers once it holds the
kitchen or living room, `KITCHEN_HALL`, `LIVING_KITCHEN`, with `out`, `outward`, `lateral`, `in_funnel`, `in_room`,
`beside_door`, `corners`, `faces_through`), a per-frame sampler (`watch`, then `path_of`, `pos_at`, `first_stop_in_room`,
`funnel_entries`, `first_in_funnel`, `longest_pause_in_funnel`, `time_facing_through`) and the radio (`calls(t, step, id)`, `first_call_time`;
callouts carry `entry_step`). The brain is read through `debug_entry()` and `debug_room_zones()`.

- Two invaders that claim a doorway on the same frame settle their slots by instance id: the first actor declared
  gets slot 1 on a tie.
- From beside a door you can see the opposite door-wall corner through the gap, so what the pie leaves hidden is
  geometry, not a rule: assert that hidden corners are on the door's wall, not that both are.
- A defender meant to be unseen from outside has to be behind the jamb from every spot the entrant visits (stack,
  arc, the walk there), e.g. tucked against the door's wall well along from it.

## Investigation tests (tag `investigate`)

`tests/ai/*investigate*` and `defender_stays_in_house_von` pin down how gunfire heard outside or inside the house is worded for Von
and answered (issue #40: defenders leaving the house). The shared helper is `tests/_ai/investigate_probe.gd` (`const Probe :=
preload(...)`): `world(s, kind)` (the terrace house, one NPC in the hall, radio and trespass hostility off, Von left to the caller),
`gunfire(at)` (a hit event nobody known fired, heard from `Probe.OUTSIDE` / `Probe.INSIDE`), `levels` / `asked_about_investigating`.
Scripted ones (`investigate_outside_lead_offers_stay`, `investigate_lone_lead_is_asked`) check the wiring. The three `*_von` tests
(`requires_von`, `--include-von --require-von`) check what a real Von decides: the defender stays in, still investigates gunfire inside,
and an invader still investigates the same gunfire outside. After rewording any of what Von reads about leads, run them with
`tools/von_probe.py` (its `investigate_outside_lead_*` scenarios).

`defenders_stay_in_house_quiet` (scripted) and `defenders_stay_in_house_quiet_von` (real Von, invaders outside as at the start of a match)
watch every defender of a generated house (`tests/_ai/house_probe.gd`: `spawn`, `watch`, whose failure message carries each
defender's trail and what Von was last asked) and sweep with `--seed=N`. `move_stops_on_arrival` gives
the scripted Von a real server's reply time by raising `DecisionStub.latency_frames` in `run` (`von_script` registered it, so it is restored after the test).

## Flanking tests (tag `flank`)

`tests/ai/flank_*_test.gd` pin down how the AI weighs and takes the sides of a target: frame geometry, route
safety, ally and radio claims, shot and cover wording, territory, and the walk itself. They are
scripted-Von tests (no server); `tools/run_tests.sh flank` runs them. What they assert is written in
`docs/flanking-behavior.md` (behaviours F, B1 to B9, C); each test header names the behaviour. A test that
asserts a behaviour the AI does not show yet is written first, left red and tagged `gap`
(`tools/run_tests.sh gap`); none are open now.

- **Realistic maps** (`tests/_ai/flank_maps.gd`, `const Maps := preload(...)`): `Maps.house(s)`,
  `Maps.spine(s)` and `Maps.warehouse(s)` lay out rooms, doorways, corridors and cover with
  `TestSetup.layout`, and expose landmark consts (doors, wall and room points). Call the map first, then
  `Flank.rules(s)`. Flank points sit 220 px from the target and snap to the navmesh, so a room-sized map
  gives some sides behind walls; choose positions from a `Flank.dump(brain)` of the situation.
- **Shared helper** `tests/_ai/flank_probe.gd` (`const Flank := preload(...)`; not a test): `rules`,
  `target`, `npc`, `ally`, `radio`, `settle`, and the reads below.
- **Observe through the controller's public reads.** `debug_zones()` lists every flank side the snapshot
  weighed *including those the planner then dropped*, with its `desc` and `tags` (`held`, `held_by`,
  `crosses`, `crosses_name`, `no_shot`, `heading`, `lane`, `clear_shot`, `cover`, `inside`,
  `route_exposed`, `ally_lane`);
  `debug_state()["decision"]["levels"]` holds what each level offered. So "dropped because X" is `zones`
  says X and `offered` lacks the id. `Flank.zones/offered/offered_sides/dump/level/side_of_act` wrap these;
  `Flank.side_of` is the test's own copy of the target-frame maths (left is the target's own left, so a
  west-facing target's left is south). With several hostiles known, `debug_zones()` mixes their sides:
  give `Flank.zones(brain, target_pos)` the target and make the NPC fight it with `Flank.prefer_target`
  (the nearest hostile is otherwise the first option and gets picked).
- **Hold the NPC and settle** (`Flank.npc` + `Flank.settle`): `speed` 0 and a 0.4 s commit and tactic
  cadence, so it re-decides from a fixed spot and `settle` waits for a finished walk. A walking test holds
  the NPC until `settle`, then sets `brain.max_commit_time` back to 6 and `npc.speed` to 150.
- **Set the target's frame before the first frame** (`Flank.target`): its `facing` and `aim_point` are
  props, because a puppet's `aim_point` defaults to the origin and turns it that way until `aim_at` runs.
  Give targets and allies a huge `max_health`; the NPCs shoot while they wait.
- **Radio claims** are real `callout` events posted with `Flank.radio` from an ally puppet the NPC cannot
  see (behind a wall, or far off). An ally it can see holds the side it stands on by name, without
  "(radio)". Two or more live invaders get different `max_commit_time` / `tactic_interval` /
  `decide_interval`, otherwise they decide on the same frame and claim the same side.
- **Route-safety rules decide which sides exist.** A route within `route_clearance` of a hostile is dropped,
  and in open ground the straight route to a rear point passes the target. Tests about other rules set
  `route_clearance` low (0 for the group tests, 40 for the ally lane) so only the rule under test acts, and
  say so in a comment.
- **An ally only counts if the NPC sees it.** The NPC weighs allies by sight (a 110° view cone toward its
  target, plus a 48 px bubble) or by radio, so a test about an ally's line of fire or side must put the ally
  within 55° of the NPC's line to the target, with no wall or pillar between. An ally outside it leaves
  `allies` empty and no rule fires. The lane rule also tests the NPC's *route*: a route that passes between an
  ally and the target is dropped, so place a held-side ally off the routes the test expects to be offered.
- **Not testable here: TTL lapse.** Memory ages in wall-clock ms (`Time.get_ticks_msec`), which a headless
  `--fixed-fps` run outruns, so a callout or contact never lapses in test time.
- **Flank point sampling** prefers any sampled point with a clear shot, so a "line blocked" scenario needs
  a barrier across the whole arc (a row of shelves), not one piece.

## Errors and warnings fail the test (`log_watch.gd`)

Godot 4.4 has no in-process logger hook (that arrives with `OS.add_logger` in 4.5). `LogWatch` tails
the engine log file (`debug/file_logging/log_path`) from an offset marked at runner start and parses
`ERROR:` / `SCRIPT ERROR:` / `USER ERROR:` / `WARNING:` / … headers with their `at:` lines.

- The runner polls it every physics frame and hands each entry to the open test (`TestContext.on_log`).
  An expected (`expect_log`) or allowed (`allowed_logs`, or the global `[von] ` launcher diagnostics)
  line passes; anything else is a failed check, `Logged error: … (at …)`, and ends the test.
- Teardown logs count too. Batch mode frees the world and polls again before taking the verdict;
  interactive mode re-renders the banner if a late error arrives.
- Lines logged while no test is open (for example a test script's parse error when the catalog loads
  it) are batch-level failures. The runner's own output never starts with an error header. A batch run owns a
  fresh log (`--log-file` + `--out`), so the watch starts at byte 0 and **start-up errors count too**.
- **Nothing escapes the process either.** The runner writes `log_end` (bytes judged, `LogWatch.consumed()`) into its
  report; `tools/run_tests.sh` then scans the log from there to the end with `tools/scan_godot_log.py` — whatever
  the engine writes while shutting down — and from byte 0 when no report exists (`--list`, a crash, a runner that
  never started), once per shard. Any hit prints `Logged outside any test` and fails the run. Godot's own
  end-of-process leak report ("ObjectDB instances leaked at exit", "resources still in use at exit") is a `NOTE`
  by default (`--strict-exit` fails it): runs that touch a character together with a reflectively read config
  holder such as `CharacterConfig` print it at exit whatever the test does. `tools/load_check.sh` applies the same
  gate to a plain headless start-up.
- **Headless or windowed.** The gate reads the log file, so it is the same either way: `tools/run_tests.sh --shots`
  runs the batch with a window, and the in-game runner (`-- --play …`, the browser) watches the default log
  (`debug/file_logging/enable_file_logging` is set in `project.godot`). In-game, a logged error or warning fails the
  open test and flips a verdict already shown; each verdict is also printed to the console, and the banner says so
  when the log cannot be read.
- **Tested by** `tools/test_log_gate.py` (`--headed` adds the windowed engine): the scanner on crafted logs,
  `run_tests.sh` around a fake Godot for every way a run can end, and the real engine through the probe
  `tests/_harness/log_gate_probe_test.gd` (set `GAME_TEST_PROBE=error|warning`) in batch and in-game;
  `log_watch_offsets_test.gd` covers the read positions. Run it after editing `log_watch.gd`, `test_runner.gd`,
  `run_tests.sh` or `scan_godot_log.py`. The same file tests the lint: `lint_report.py` on crafted logs,
  `run_tests.sh` stopping on a lint failure, and the real engine through `tools/lint.sh` (the project is clean; a probe
  script's warnings are found). Run it after editing `tools/lint*` too.

## Behaviour switches (`test_switches.gd`)

One data table. A row maps a name to existing knobs:

- `actor: { child, props }` sets those props to `on` on that child of every actor, before it
  enters the tree;
- `world: { node, props }` sets props on a world node;
- `static: [[Script, prop]]` sets that `static var` to `on`;
- `[Script, prop, off_value]` is for a non-bool knob: on keeps its tuning, off sets `off_value`.

Statics are restored after every test (`TestWorld.restore`). Current switches:

| Switch | What it controls |
|---|---|
| `ai.vision` | Whether NPCs can see. |
| `ai.callouts` | Team radio callouts, sent and heard. |
| `ai.pursuit` | Whether NPCs chase hostiles. |
| `ai.territory` | Defender confinement to the house. |
| `ai.hostile_on_sight` | Hostility toward anyone seen. |
| `ai.hostile_on_trespass` | Hostility toward anyone inside the house. |
| `ai.hostile_on_attack` | Hostility toward an attacker. |
| `ai.posture` | NPCs crouch while fighting in place (`GoalController.posture_enabled`). |
| `ai.entry` | Tactical entry (`GoalController.entry_enabled`; on in the invader preset). |
| `ai.entry_guard` | The entry guard (`GoalController.entry_guard`, on by default; needs `ai.entry`): any walk into an uncleared room goes in by entry. |
| `nav.rebake` | `NavUpdater.enabled`. |
| `audio.sound` | `SoundConfig.enabled`: shots, impacts, footsteps and reloads make `sound` events and voices. |
| `physics.blood` | `BloodConfig.enabled`. |
| `physics.footprints` | `BloodConfig.footprints_enabled`. |
| `physics.smear` | `BloodConfig.smear_enabled`. |
| `physics.debris` | `PhysicsConfig.debris_enabled`. |
| `physics.hit_particles` | `PhysicsConfig.hit_particles_enabled`. |
| `projectile.flyover` | `BallisticsConfig.cover_flyover_scale`, 0 when off. A test that needs a chosen outcome instead pins `BallisticsConfig.bullet_height` (0–100) with `set_static`. |

To add a switch, add a row. When the behaviour has no knob yet, add a master `static var` to that
domain's config holder, guarded at its one spawn point (the way `BloodConfig.enabled` gates
`BloodWound.record`).

## Files

| File | Role |
|---|---|
| `game_test.gd` (`GameTest`) | Base class. |
| `test_setup.gd` (`TestSetup`) | The declarative builder. |
| `test_context.gd` (`TestContext`, an **Object**) | Waits, lookup, event log, assertions, verdict (`conclude`: PASS / FAIL / TIMEOUT / SKIPPED, and GAP for a `gap`-tagged test that failed as expected). The runner frees it at close, which discards any test coroutine still parked on it. |
| `test_world.gd` | Builds a TestSetup into a sub-tree: statics and switches first, then the house, layout or arena, objects, nav plus updater, two physics frames (walls solid, navmesh live), then a wait (real time, at most `NAV_SYNC_MS`) until the shared nav map, and the Navigation domain's steering map, answer with this world's regions, actors (controller injected before `_ready` — `rooms` and the house's `openings` — positioned before they join the tree so one never overlaps origin furniture for a frame), then world switches. `build` is a coroutine. Also `restore()` and `set_overlay()`. |
| `arena_builder.gd` | The walled arena via `FloorFactory` / `WallFactory` + `WorldGen.wall_style()`, annotated with `WorldGen.annotate_layout`. |
| `layout_builder.gd` | A hand-laid layout: per-room floors and walls, doorways cut with `WallFactory.openings_for`, annotated with `WorldGen.annotate_layout` like a house. |
| `scripted_controller.gd` | The puppet controller. |
| `test_switches.gd` | The switch table. |
| (AI) `decision_stub.gd` | `DecisionStub`: the scripted-Von statics a TestSetup turns on (restored after each test); `DecisionBudget.per_frame` (`decision_budget.gd`) is set with `set_static` the same way. |
| `log_watch.gd` | The log tail (`begin(from_start)`, `poll`, `consumed`). |
| `test_catalog.gd` | `discover(root, domains, ids)`, `describe(path)` (descriptor dicts), `matches(entry, text)`, and the CLI selection helpers `csv()` / `shard()`. |
| `test_runner.gd` / `.tscn` | Interactive and batch modes, one `TestWorld` child per test, a lazily created `DecisionServerLauncher` kept for the session, real-time pacing for Von tests, the JSON report. |
| `test_browser.gd` / `.tscn` | Hosts the UI browser window. Engine metas `test_selection` / `test_results` / `test_filter` survive the round trip through a test. |

## Gotchas

- **Von tests are paced in real time.** Batch runs use `--fixed-fps 60`, so the sim outruns the wall
  clock and game-time timers (HTTP timeouts, the launcher's probe interval) fire early. While a `requires_von` test is open the runner sleeps each frame to
  1/60 s, because `Engine.max_fps` is not honoured under `--fixed-fps` headless. A cold Von start
  takes about 5 s.
- A test that ends mid-wait (a failure or timeout) leaves its coroutine parked. Godot may report
  "ObjectDB instances leaked" at process exit for it. That happens after the last log poll and is
  harmless.
- An NPC thinks on its first tick, so the world must be live before actors enter: `TestWorld.build` waits
  two physics frames after the walls and navmesh are made (otherwise an NPC sees through room walls and
  plans on an empty navmesh), then until the navigation map's closest point to a room's centre belongs to the
  new region. The map's iteration is built on a worker thread: under load (parallel shards) its id and region list
  update before queries do, and an NPC that snapped a point onto the empty map walked to the origin. That wait is
  in real time, so the test clock is stopped while the world builds (`_building` in the runner).
- The defender preset is `hostile_on_trespass`, and an arena counts as its house. Turn
  `ai.hostile_on_trespass` off to test a reaction to something else.
