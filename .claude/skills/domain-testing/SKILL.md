---
name: domain-testing
description: Deep implementation detail for the Testing domain (scenes/testing/ + tests/) — game tests that declare a world (arena, hand-laid room layout or generated house), the actors and objects in it and which behaviours are on, run it, and assert what happened; plus the in-game test browser/runner and the headless CLI runner (tools/run_tests.sh). Use when writing or debugging a test, adding a behaviour switch, running the suite, or editing scenes/testing/. Any engine error/warning during a test fails it. Complements the `architecture` skill (interface 13).
---

# Testing domain (`scenes/testing/`, cases in `tests/`)

A second composition root beside `main.gd`. It builds a test's world **only through the published
interfaces** (WorldGen + its catalogue lookups, the Objects factories, NavBuilder, the character scenes
and controller contract, EventBus and character signals) and never reaches into domain internals.

## Running tests

- **CLI:** `tools/run_tests.sh [filter words] [--include-von]` runs
  `godot --headless --fixed-fps 60 res://scenes/testing/test_runner.tscn -- --run-tests …`. A fresh checkout
  (no `.godot/` class cache) is imported first, since without it every script fails to parse. It prints one
  line per test (`PASS/FAIL/TIMEOUT/SKIPPED  <id>  (<sim s> sim, <ms> ms)`, failed checks indented with ✗), then a
  summary, and writes `report.json`. Exit code 1 means a test failed or timed out, or an
  error/warning was logged outside any test. Filter words are word prefixes over id, name, domain,
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
  `--shard=I/N` (longest `timeout` first onto the lightest shard, so they finish together; Von tests all stay in shard 0), merges their output into one
  combined total and one `--failed` report. `auto` = cores, at most 4. Not used with `--list`/`--self-test`
  (the `_a`/`_b` restore pairs need one process in id order). Perf tests budget wall-clock ms about 4x
  their baseline, so heavy CPU contention is the thing to suspect if one trips only under `--jobs`.
  `--fail-fast` stops after the first FAIL/TIMEOUT (per shard).
- **Output:** `--summary` prints only non-passing tests and the totals; every run reports wall-clock ms
  per test (`wall_ms` in the report) and ends with a `Slowest:` line. `--verbose`, `--json` as before.
- **Other flags:** `--repeat=N` (each test N times; names `FLAKY` / `FAILING` ones), `--seed=N` (every
  `house()` uses that seed), and, in the wrapper only, `--changed` (see below). Options take the
  `--name=value` form.
- **`--changed`:** the wrapper maps each changed file (`git diff HEAD` plus untracked) to a domain and
  runs those domains plus the ones that compose them (its `affected()` table, from the architecture
  dependency graph) in **one** process; `main.gd`, root scenes, `project.godot`, worldgen, art and general
  run everything, and `scenes/testing/` / the Von stub add `--self-test`.
- **Which command?**

  | Situation | Command |
  |---|---|
  | One test | `tools/run_tests.sh --id=<domain>/<name>` |
  | Just saw failures, fixed something | `tools/run_tests.sh --failed` |
  | Finished an edit | `tools/run_tests.sh --changed --summary` |
  | Before committing / big change | `tools/run_tests.sh --jobs=auto --summary` |
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
  offers Rerun and Back/Escape. The in-game overlay toggle bar works on the test's NPCs.
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
  always unpaused on a new test, Back and exit. The overlay bar works on the test's actors; its **Nav holes**
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

- **`describe()`** (all optional): `name`, `domain`, `description`, `tags`, `timeout` (sim s, default
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
    and is deterministic; `von_down()` makes every decision fail (the hold-steady fallback). Read what was
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
  (straight line, no pathing), `walk(dir)`, `set_run(on)` (holds run while moving), `stop()`, `select_slot(n)`, `punch()`, `shoot()` (one click), `hold_fire(on)` (hold the trigger: an automatic gun fires at its rate; a semi-auto one is unaffected), `reload()`,
  `interact(object, id)` (refusals land in `failed_interactions`), `end_interaction()`. Actions run on
  the character's next frame, and the character derives `facing` from the aim one frame later, so
  aim, wait a moment, then fire.
- Make randomness deterministic where the assertion depends on it (e.g. `projectile.flyover` off,
  since a character is partial cover).

## Performance stress tests (tag `perf`)

Regression guards for speed and runaway object counts. They are ordinary tests in the domain they
load (`tests/ai/npc_crowd_stress`, `navigation/bake_and_path_stress`, `objects/furniture_pile_stress`,
`physics/crowd_deaths_stress`, `physics/hit_overload_stress`, `projectile/bullet_barrage_stress`,
`worldgen/generate_houses_stress`), so `--changed` runs them with their domain and
`tools/run_tests.sh perf` runs just them. The shared helper is `tests/_perf/perf_probe.gd`
(`const Perf := preload(...)`; not a test).

- **Measured:** wall-clock ms per frame (`Perf.frame_stats` -> avg / p95 / max; headless `--fixed-fps`
  outruns the clock, so frame-to-frame wall time is the CPU cost; rendering is not covered), one-shot ms
  (`Perf.time_ms`), and exact counts (`Perf.nodes()`, `Despawner.count()`, dent / blood-pool caps).
- **Budgets** are `const`s at the top of each test, about 4x the measured baseline (stated in the comment
  above them). `Perf.within` prints `PERF <label> <value> (budget <limit>)`, traces it, and fails the
  check with the value. Counts are asserted tightly; times loosely, so only real regressions trip them.
- **Re-baselining:** run `tools/run_tests.sh perf --repeat=5 --verbose`, read the `PERF` lines, set each budget to
  about 4x the worst observed value, and update the baseline comment. A deliberate cost increase is a
  budget change in the same commit.
- **Gotchas:** a lambda captures ints by value (count into an Array); `nav.rebake` is off in tests that
  shove or shoot furniture into overlaps (re-baking overlapping holes logs a nav sync error; the nav
  test covers re-baking); world-gen's first run in a process is
  slower (cold caches), so its budget covers the cold case.

## Flanking tests (tag `flank`)

`tests/ai/flank_*_test.gd` pin down how the AI weighs and takes the sides of a target: frame geometry, route
safety, ally and radio claims, shot and cover wording, territory, and the walk itself. They are
scripted-Von tests (no server); `tools/run_tests.sh flank` runs them. What they assert is written in
`docs/flanking-behavior.md` (behaviours F, B1 to B9, C); each test header names the behaviour. A test that
asserts a behaviour the AI does not show yet is red and tagged `gap` (`tools/run_tests.sh gap`).

- **Realistic maps** (`tests/_ai/flank_maps.gd`, `const Maps := preload(...)`): `Maps.house(s)`,
  `Maps.spine(s)` and `Maps.warehouse(s)` lay out rooms, doorways, corridors and cover with
  `TestSetup.layout`, and expose landmark consts (doors, wall and room points). Call the map first, then
  `Flank.rules(s)`. Flank points sit 220 px from the target and snap to the navmesh, so a room-sized map
  gives some sides behind walls; choose positions from a `Flank.dump(brain)` of the situation.
- **Shared helper** `tests/_ai/flank_probe.gd` (`const Flank := preload(...)`; not a test): `rules`,
  `target`, `npc`, `ally`, `radio`, `settle`, and the reads below.
- **Observe through the controller's public reads.** `debug_zones()` lists every flank side the snapshot
  weighed *including those the planner then dropped*, with its `desc` and `tags` (`held`, `held_by`,
  `crosses`, `crosses_name`, `clear_shot`, `cover`, `inside`, `route_exposed`, `ally_lane`);
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
  it) are batch-level failures. The runner's own output never starts with an error header.

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
| `nav.rebake` | `NavUpdater.enabled`. |
| `physics.blood` | `BloodConfig.enabled`. |
| `physics.footprints` | `BloodConfig.footprints_enabled`. |
| `physics.smear` | `BloodConfig.smear_enabled`. |
| `physics.debris` | `PhysicsConfig.debris_enabled`. |
| `physics.wall_collider_deform` | `PhysicsConfig.deform_update_collider`. |
| `projectile.flyover` | `BallisticsConfig.cover_flyover_scale`, 0 when off. |

To add a switch, add a row. When the behaviour has no knob yet, add a master `static var` to that
domain's config holder, guarded at its one spawn point (the way `BloodConfig.enabled` gates
`BloodWound.record`).

## Files

| File | Role |
|---|---|
| `game_test.gd` (`GameTest`) | Base class. |
| `test_setup.gd` (`TestSetup`) | The declarative builder. |
| `test_context.gd` (`TestContext`, an **Object**) | Waits, lookup, event log, assertions, verdict (`conclude`). The runner frees it at close, which discards any test coroutine still parked on it. |
| `test_world.gd` | Builds a TestSetup into a sub-tree: statics and switches first, then the house, layout or arena, objects, nav plus updater, two physics frames (walls solid, navmesh live), actors (controller injected before `_ready`), then world switches. `build` is a coroutine. Also `restore()` and `set_overlay()`. |
| `arena_builder.gd` | The walled arena via `FloorFactory` / `WallFactory` + `WorldGen.wall_style()`. |
| `layout_builder.gd` | A hand-laid layout: per-room floors and walls, doorways cut with `WallFactory.openings_for`, `rooms` / `openings` metas like a house. |
| `scripted_controller.gd` | The puppet controller. |
| `test_switches.gd` | The switch table. |
| (AI) `decision_stub.gd` | `DecisionStub`: the scripted-Von statics a TestSetup turns on (restored after each test). |
| `log_watch.gd` | The log tail. |
| `test_catalog.gd` | `discover(root, domains, ids)`, `describe(path)` (descriptor dicts), `matches(entry, text)`, and the CLI selection helpers `csv()` / `shard()`. |
| `test_runner.gd` / `.tscn` | Interactive and batch modes, one `TestWorld` child per test, a lazily created `DecisionServerLauncher` kept for the session, real-time pacing for Von tests, the JSON report. |
| `test_browser.gd` / `.tscn` | Hosts the UI browser window. Engine metas `test_selection` / `test_results` / `test_filter` survive the round trip through a test. |

## Gotchas

- **Von tests are paced in real time.** Batch runs use `--fixed-fps 60`, so the sim outruns the wall
  clock and game-time timers (HTTP timeouts, the launcher's probe interval) fire early; that once
  flooded the server with probes. While a `requires_von` test is open the runner sleeps each frame to
  1/60 s, because `Engine.max_fps` is not honoured under `--fixed-fps` headless. A cold Von start
  takes about 5 s.
- A test that ends mid-wait (a failure or timeout) leaves its coroutine parked. Godot may report
  "ObjectDB instances leaked" at process exit for it. That happens after the last log poll and is
  harmless.
- An NPC thinks on its first tick, so the world must be live before actors enter: `TestWorld.build` waits
  two physics frames after the walls and navmesh are made (otherwise an NPC sees through room walls and
  plans on an empty navmesh).
- The defender preset is `hostile_on_trespass`, and an arena counts as its house. Turn
  `ai.hostile_on_trespass` off to test a reaction to something else.
