---
name: domain-testing
description: Deep implementation detail for the Testing domain (scenes/testing/ + tests/) — game tests that declare a world (arena or generated house), the actors and objects in it and which behaviours are on, run it, and assert what happened; plus the in-game test browser/runner and the headless CLI runner (tools/run_tests.sh). Use when writing or debugging a test, adding a behaviour switch, running the suite, or editing scenes/testing/. Any engine error/warning during a test fails it. Complements the `architecture` skill (interface 13).
---

# Testing domain (`scenes/testing/`, cases in `tests/`)

A second composition root beside `main.gd`. It builds a test's world **only through the published
interfaces** (WorldGen + its catalogue lookups, the Objects factories, NavBuilder, the character scenes
and controller contract, EventBus and character signals) and never reaches into domain internals.

## Running tests

- **CLI:** `tools/run_tests.sh [filter words] [--include-von]` runs
  `godot --headless --fixed-fps 60 res://scenes/testing/test_runner.tscn -- --run-tests …`. It prints one
  line per test (`PASS/FAIL/TIMEOUT/SKIPPED  <id>  (<sim s>)`, failed checks indented with ✗), then a
  summary, and writes `report.json`. Exit code 1 means a test failed or timed out, or an
  error/warning was logged outside any test. Filter words are word prefixes over id, name, domain,
  description and tags (`ai` matches the ai domain, not "chair"). Manual sandboxes are always skipped.
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
- **Other flags:** `--list [words]` (id, von/manual flags, tags; runs nothing), `--repeat=N` (each test
  N times; names `FLAKY` / `FAILING` ones), `--seed=N` (every `house()` uses that seed), `--json` (one
  `JSON: {…}` line with all results), and, in the wrapper only, `--changed` (runs `tests/<d>/` for each
  `scenes/<d>/` or `tests/<d>/` with uncommitted changes). Options take the `--name=value` form.
- **`--self-test`:** runs the harness's own tests (`tests/_harness/`, `internal: true` in `describe()`;
  hidden from the browser and normal runs): verdict rules, LogWatch really seeing engine logs, and the
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
  The browser's **Run all** button spawns a separate headless run of the whole suite, Von tests included
  (`--include-von`; they skip if no server comes up) (its own
  `user://test_runs/<n>/` dir as above), shows elapsed time, then folds `report.json` into the marks and
  the status line (failure bundles are under that dir).

## Writing a test

One file `tests/<domain>/<name>_test.gd` that `extends GameTest`. Id = `<domain>/<name>`.

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
  10), `requires_von`, `manual` (a sandbox to play: no assertions or timeout, skipped in batch),
  `fail_on_errors` / `fail_on_warnings` (default true), `allowed_logs` (regexes).
- **`configure(s: TestSetup)`** is data only, and the browser also calls it to list the switches.
  - World: `arena(rect, { floor, walls, thickness })` (a walled room in the house style, with the same
    `rooms` meta a house has) or `house(seed, plan := "", entrance := Vector2.ZERO)`. Default is an
    800×500 arena.
  - Objects: `object(id, catalogue_key_or_definition, pos, opts)`. Objects are placed under the
    house/arena root before the nav bake, so they are carved.
  - Actors: `actor(id, kind, pos, props)`. Kind is `puppet` (scripted), `player` (human-driven),
    `defender`, `invader`, or a scene path. `props` are set on the character before `_ready` (for
    example `max_health`, `start_slot`: 1 unarmed / 2 fists / 3 pistol / 4 key, `faction`). Use
    `set_props(id, "GoalController", {...})` for a child's exports. NPCs get `rooms` injected, as Main
    does.
  - Behaviour: `switch(name, on)` (table below) and `set_static(ConfigClass, prop, value)`.
  - Scripted Von: `von_script([{ pick: id, question: substring? }, …])` replaces the server with those
    picks (first rule whose id is offered; else the first offered option), so an AI test needs no server
    and is deterministic; `von_down()` makes every decision fail (the hold-steady fallback). Read what was
    asked with `t.von_requests()` (`{ state, question, options, pick }`). Ids are the decision tree's node
    ids (`combat`, `flank`, `engage`, …) and option ids. Keep `requires_von` tests for judging Von itself.
  - Presentation: `show_overlays(["show_vision", …])` and `camera_follow([ids])` (default frames all
    actors).
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
    (blood pools, debris, projectiles, dropped items).
  - `t.trace(name, value)` samples a number over time (a distance, a health) for the failure output.
  - Assertions: `check(cond, msg)` (soft), `require(cond, msg)` (ends the test; follow it with
    `if not …: return`), `expect_eq`, `expect_near`, `expect_log(pattern, count)`, `skip(why)`.
    A non-manual test that asserts nothing fails.
- Puppet (`scripted_controller.gd`): `aim_at(node_or_point)`, `walk_to(point)` + `has_arrived()`
  (straight line, no pathing), `walk(dir)`, `stop()`, `select_slot(n)`, `punch()`, `shoot()`,
  `interact(object, id)` (refusals land in `failed_interactions`), `end_interaction()`. Actions run on
  the character's next frame, and the character derives `facing` from the aim one frame later, so
  aim, wait a moment, then fire.
- Make randomness deterministic where the assertion depends on it (e.g. `projectile.flyover` off,
  since a character is partial cover).

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
| `physics.debris` | `PhysicsConfig.debris_enabled`. |
| `physics.wall_collider_deform` | `PhysicsConfig.deform_update_collider`. |
| `projectile.flyover` | `BallisticsConfig.cover_flyover_scale`, 0 when off. |

To add a switch, add a row. When the behaviour has no knob yet, add a master `static var` to that
domain's config holder, guarded at its one spawn point (the way `BloodConfig.enabled` gates
`Physics.spawn_blood`).

## Files

| File | Role |
|---|---|
| `game_test.gd` (`GameTest`) | Base class. |
| `test_setup.gd` (`TestSetup`) | The declarative builder. |
| `test_context.gd` (`TestContext`, an **Object**) | Waits, lookup, event log, assertions, verdict (`conclude`). The runner frees it at close, which discards any test coroutine still parked on it. |
| `test_world.gd` | Builds a TestSetup into a sub-tree: statics and switches first, then the house or arena, objects, nav plus updater, actors (controller injected before `_ready`), then world switches. Also `restore()` and `set_overlay()`. |
| `arena_builder.gd` | The walled arena via `FloorFactory` / `WallFactory` + `WorldGen.wall_style()`. |
| `scripted_controller.gd` | The puppet controller. |
| `test_switches.gd` | The switch table. |
| (AI) `decision_stub.gd` | `DecisionStub`: the scripted-Von statics a TestSetup turns on (restored after each test). |
| `log_watch.gd` | The log tail. |
| `test_catalog.gd` | `discover()`, `describe(path)` (descriptor dicts) and `matches(entry, text)`. |
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
- The defender preset is `hostile_on_trespass`, and an arena counts as its house. Turn
  `ai.hostile_on_trespass` off to test a reaction to something else.
