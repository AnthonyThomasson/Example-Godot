#!/usr/bin/env python3
"""Tests for the gate that fails a test run on any engine error or warning.

  python3 tools/test_log_gate.py            scanner + wrapper (fake Godot) + the real engine, headless
  python3 tools/test_log_gate.py --headed   also the real engine WITH a window (batch --shots and the in-game runner)

(The GDScript lint that runs first has its own tests at the end: lint_report.py on crafted logs, run_tests.sh
aborting on a lint failure, and the real engine through tools/lint.sh.)

Three layers, because the gate has three parts:
  1. tools/scan_godot_log.py on crafted logs (what counts as an error, the shutdown leak NOTE, --from offsets).
  2. tools/run_tests.sh against a fake `godot` that writes the log / report we choose, so every way a run can end
     (error after the runner stopped judging, no report, a shard failing, --list) is checked without an engine.
  3. The real engine: tests/_harness/log_gate_probe_test.gd logs an error / warning on purpose (GAME_TEST_PROBE) and
     the run must FAIL in batch and in the in-game runner (`-- --play`), headless and (with --headed) windowed.
Layer 3 is skipped when no Godot binary is found.
"""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN = ROOT / "tools" / "scan_godot_log.py"
RUN = ROOT / "tools" / "run_tests.sh"
HEADED = "--headed" in sys.argv


def godot_binary():
    for name in ("godot", "godot4"):
        p = shutil.which(name)
        if p:
            return p
    for p in sorted(Path("/Applications").glob("Godot*.app/Contents/MacOS/Godot")):
        return str(p)
    return os.environ.get("GODOT")


def scan(text: str, *flags: str):
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
        f.write(text)
    try:
        r = subprocess.run([sys.executable, "-I", str(SCAN), f.name, *flags], capture_output=True, text=True)
    finally:
        os.unlink(f.name)
    return r.returncode, r.stdout


class ScannerTests(unittest.TestCase):
    def test_clean_log_passes(self):
        self.assertEqual(scan("Godot Engine v4.4\nsome print\n")[0], 0)

    def test_every_error_and_warning_header_fails(self):
        for line in ("ERROR: x", "WARNING: x", "SCRIPT ERROR: Parse Error: x", "USER SCRIPT ERROR: x",
                     "USER ERROR: x", "SHADER ERROR: x", "USER WARNING: x", "SCRIPT WARNING: x"):
            code, out = scan(line + "\n   at: f (a.gd:1)\n")
            self.assertEqual(code, 1, line)
            self.assertIn("Logged outside any test", out)

    def test_colour_codes_do_not_hide_an_error(self):
        self.assertEqual(scan("\x1b[1;31mERROR:\x1b[0;91m boom\n")[0], 1)

    def test_von_launcher_diagnostics_are_allowed(self):
        self.assertEqual(scan("WARNING: [von] server not found\n")[0], 0)

    def test_from_offset_skips_what_was_already_judged(self):
        head = "ERROR: judged by the runner\n"
        self.assertEqual(scan(head + "all quiet\n", f"--from={len(head)}")[0], 0)
        self.assertEqual(scan(head + "ERROR: after\n", f"--from={len(head)}")[0], 1)

    def test_missing_log_fails(self):
        r = subprocess.run([sys.executable, "-I", str(SCAN), "/nonexistent/godot.log"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)

    LEAK = ("ERROR: Condition \"p_elem->_root != this\" is true.\n   at: remove (./core/templates/self_list.h:80)\n"
            "ERROR: 12 RID allocations of type 'X' were leaked at exit.\n"
            "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).\n"
            "ERROR: 76 resources still in use at exit (run with --verbose for details).\n")

    def test_engine_shutdown_leak_report_is_a_note_unless_strict(self):
        code, out = scan(self.LEAK)
        self.assertEqual(code, 0)
        self.assertIn("NOTE", out)
        self.assertEqual(scan(self.LEAK, "--strict-exit")[0], 1)

    def test_a_real_error_next_to_the_leak_report_still_fails(self):
        self.assertEqual(scan(self.LEAK + "ERROR: something real\n")[0], 1)


FAKE_GODOT = r"""#!/usr/bin/env bash
# Stands in for Godot: writes the engine log and runner report that $FAKE_SCENARIO describes; started on the
# lint scene it prints the lint protocol with (FAKE_LINT=dirty) or without a warning instead.
for a in "$@"; do
  if [ "$a" = "res://tools/lint_scripts.tscn" ]; then
    echo "LINT-PASS2"; echo "LINT> res://scenes/x.gd"
    [ "$FAKE_LINT" = "dirty" ] && echo "ERROR: 'The local variable \"a\" is declared but never used in the block.'"
    echo "LINT-DONE 1"; exit 0
  fi
done
log=""; out=""; costs=""; selection=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log-file) log="$2"; shift ;;
    --out=*) out="${1#--out=}" ;;
    --shard=*) shard="${1#--shard=}" ;;
    --costs=*) costs="${1#--costs=}" ;;
    --id=*|--domain=*|--skip-domain=*) selection="$selection $1" ;;
  esac
  shift
done
head='Godot Engine v4.4'
judged='ERROR: a test provoked this (the runner already failed that test)'
echo "$head" > "$log"
report() { printf '{"results": [], "stray_logs": [], "log_end": %s}' "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"; }
timed() {
  printf '{"results": [{"id": "a/x", "status": "PASS", "wall_ms": 120}, {"id": "a/z", "status": "PASS", "wall_ms": 80}, {"id": "a/s", "status": "SKIPPED", "wall_ms": 5}], "stray_logs": [], "log_end": %s}' \
    "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"
  echo "Slowest: a/x 120 ms, a/z 80 ms"
}
[ -n "$costs" ] && echo "costs-arg $costs"
[ -n "$selection" ] && echo "selection:$selection"
echo "0 passed, 0 failed, 0 timed out, 0 skipped"
case "$FAKE_SCENARIO" in
  clean) report ;;
  timed) timed ;;
  judged_error) echo "$judged" >> "$log"; report ;;
  shutdown_error) report; echo "ERROR: engine complained while quitting" >> "$log" ;;
  shutdown_warning) report; echo "WARNING: engine muttered while quitting" >> "$log" ;;
  shutdown_leak) report; printf 'WARNING: ObjectDB instances leaked at exit\nERROR: 3 resources still in use at exit\n' >> "$log" ;;
  no_report) echo "SCRIPT ERROR: Parse Error: broken script" >> "$log" ;;
  no_report_clean) ;;
  listing_error) echo "ERROR: while listing" >> "$log" ;;
  listing_clean) ;;
  shard1_error) report; [ "$shard" = "1/2" ] && echo "ERROR: only shard 1" >> "$log" ;;
esac
exit 0
"""


class WrapperTests(unittest.TestCase):
    """tools/run_tests.sh around a fake Godot: how a run can end, and whether the wrapper fails it."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="log_gate_"))
        cls.fake = cls.tmp / "fakegodot"
        cls.fake.write_text(FAKE_GODOT)
        cls.fake.chmod(cls.fake.stat().st_mode | stat.S_IEXEC)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_wrapper(self, scenario, *args, lint=None, state=None):
        """`lint` = None skips the lint (these tests are about the log gate); "clean" / "dirty" runs it on the fake.
        A lint run keeps its state (the fingerprint of the last clean lint) in `state`, a fresh directory unless the
        caller passes one, so one test's clean lint never makes the next test skip its lint."""
        if lint and state is None:
            state = Path(tempfile.mkdtemp(dir=self.tmp))
        env = dict(os.environ, GODOT=str(self.fake), FAKE_SCENARIO=scenario, FAKE_LINT=lint or "",
                   TMPDIR=str(state or self.tmp))
        flags = list(args) + ([] if lint else ["--no-lint"])
        r = subprocess.run(["bash", str(RUN), *flags], cwd=ROOT, env=env, capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    def test_clean_run_passes(self):
        self.assertEqual(self.run_wrapper("clean")[0], 0)

    def test_error_the_runner_already_judged_does_not_fail_twice(self):
        self.assertEqual(self.run_wrapper("judged_error")[0], 0)

    def test_error_logged_while_the_engine_shuts_down_fails(self):
        code, out = self.run_wrapper("shutdown_error")
        self.assertEqual(code, 1)
        self.assertIn("Logged outside any test", out)
        self.assertIn("engine complained while quitting", out)

    def test_warning_logged_while_the_engine_shuts_down_fails(self):
        self.assertEqual(self.run_wrapper("shutdown_warning")[0], 1)

    def test_engine_leak_report_is_a_note_and_strict_exit_fails_it(self):
        code, out = self.run_wrapper("shutdown_leak")
        self.assertEqual(code, 0)
        self.assertIn("NOTE", out)
        self.assertEqual(self.run_wrapper("shutdown_leak", "--strict-exit")[0], 1)

    def test_run_that_wrote_no_report_fails_and_shows_why(self):
        code, out = self.run_wrapper("no_report")
        self.assertEqual(code, 1)
        self.assertIn("wrote no report", out)
        self.assertIn("broken script", out)
        self.assertEqual(self.run_wrapper("no_report_clean")[0], 1)

    def test_list_run_is_scanned_from_the_start(self):
        self.assertEqual(self.run_wrapper("listing_error", "--list")[0], 1)
        self.assertEqual(self.run_wrapper("listing_clean", "--list")[0], 0)

    def test_a_lint_warning_fails_the_run_before_any_test_starts(self):
        code, out = self.run_wrapper("clean", lint="dirty")
        self.assertEqual(code, 1)
        self.assertIn("declared but never used", out)
        self.assertIn("no tests were run", out)
        self.assertNotIn("passed,", out)

    def test_a_clean_lint_lets_the_tests_run(self):
        code, out = self.run_wrapper("clean", lint="clean")
        self.assertEqual(code, 0)
        self.assertIn("passed,", out)

    def test_a_clean_lint_is_not_repeated_on_an_unchanged_tree_but_any_change_runs_it_again(self):
        state = Path(tempfile.mkdtemp(dir=self.tmp))
        self.assertEqual(self.run_wrapper("clean", lint="clean", state=state)[0], 0)
        # Same sources: the lint is skipped, so a lint that would now fail does not stop the run.
        code, out = self.run_wrapper("clean", lint="dirty", state=state)
        self.assertEqual(code, 0)
        self.assertIn("lint skipped", out)
        # A new untracked file changes the fingerprint: the lint runs again and fails.
        probe = ROOT / "zz_lint_skip_probe.tmp"
        probe.write_text("changed")
        try:
            code, out = self.run_wrapper("clean", lint="dirty", state=state)
        finally:
            probe.unlink()
        self.assertEqual(code, 1)
        self.assertIn("no tests were run", out)
        # The failed lint recorded nothing, and with the probe gone the tree is the one the clean lint saw: skipped again.
        self.assertEqual(self.run_wrapper("clean", lint="dirty", state=state)[0], 0)

    def test_no_lint_flag_and_listing_skip_the_lint(self):
        self.assertEqual(self.run_wrapper("clean", "--no-lint", lint="dirty")[0], 0)
        self.assertEqual(self.run_wrapper("listing_clean", "--list", lint="dirty")[0], 0)

    def test_one_failing_shard_fails_the_whole_run(self):
        self.assertEqual(self.run_wrapper("shard1_error", "--jobs=2")[0], 1)
        self.assertEqual(self.run_wrapper("clean", "--jobs=2")[0], 0)

    def test_measured_times_are_kept_and_the_next_sharded_run_balances_by_them(self):
        state = Path(tempfile.mkdtemp(dir=self.tmp))
        code, out = self.run_wrapper("timed", "--jobs=2", state=state)
        self.assertEqual(code, 0)
        self.assertNotIn("costs-arg", out)  # nothing was measured yet
        costs = json.loads(next(state.glob("example_godot_costs_*.json")).read_text())
        self.assertEqual(costs, {"a/x": 120, "a/z": 80})  # the skipped test says nothing about how long a test takes
        code, out = self.run_wrapper("timed", "--jobs=2", state=state)
        self.assertEqual(out.count("costs-arg"), 2)  # every shard gets the same file
        self.assertIn(str(next(state.glob("example_godot_costs_*.json"))), out)

    def test_a_sharded_run_prints_one_combined_slowest_list(self):
        out = self.run_wrapper("timed", "--jobs=2")[1]
        self.assertEqual(out.count("Slowest:"), 1)
        self.assertIn("Slowest: a/x 120 ms, a/z 80 ms", out)
        self.assertNotIn("Slowest:", self.run_wrapper("timed", "--jobs=2", "--summary")[1])

    @staticmethod
    def shards(out):
        """How many processes a run was split over: the wrapper's combined total says so, a single process says nothing."""
        m = re.search(r"\((\d+) shards\)", out)
        return int(m.group(1)) if m else 1

    def test_the_jobs_default_is_every_core_for_the_whole_suite_and_one_for_a_selection(self):
        self.assertGreater(self.shards(self.run_wrapper("clean")[1]), 1)
        self.assertEqual(self.shards(self.run_wrapper("clean", "--id=a/x")[1]), 1)
        self.assertEqual(self.shards(self.run_wrapper("clean", "--domain=ai")[1]), 1)
        self.assertEqual(self.shards(self.run_wrapper("clean", "pistol")[1]), 1)
        self.assertEqual(self.shards(self.run_wrapper("clean", "--jobs=3", "--id=a/x,b/y")[1]), 2)  # never more than the ids

    def changed(self, files, scenario="clean", *extra):
        """What `--changed` runs when git reports exactly `files` as changed: the selection lines the fake prints."""
        env = dict(os.environ, GODOT=str(self.fake), FAKE_SCENARIO=scenario, TMPDIR=str(self.tmp),
                   GAME_TEST_CHANGED_FILES="\n".join(files))
        r = subprocess.run(["bash", str(RUN), "--changed", "--no-lint", "--jobs=1", *extra], cwd=ROOT, env=env, capture_output=True, text=True)
        return r.returncode, [ln for ln in (r.stdout + r.stderr).splitlines() if ln.startswith(("selection:", "== "))]

    def test_changed_runs_only_an_edited_test_not_the_domains_that_compose_its_code(self):
        code, lines = self.changed(["tests/projectile/pistol_shot_wounds_test.gd"])
        self.assertEqual(code, 0)
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --id=projectile/pistol_shot_wounds"])

    def test_changed_maps_scene_edits_to_the_domains_that_compose_them_and_helpers_to_their_users(self):
        _, lines = self.changed(["scenes/ai/behavior/behavior.gd"])
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=ai,perf"])
        _, lines = self.changed(["tests/_ai/flank_probe.gd"])
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=ai"])
        _, lines = self.changed(["tests/_perf/perf_probe.gd"])
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=perf"])

    def test_skip_domain_reaches_the_runner_and_stops_the_perf_helper_run(self):
        _, lines = self.changed(["scenes/ai/behavior/behavior.gd"], "clean", "--skip-domain=perf")
        self.assertEqual([l for l in lines if l.startswith("selection:")], ["selection: --domain=ai,perf --skip-domain=perf"])
        code, lines = self.changed(["tests/_perf/perf_probe.gd"], "clean", "--skip-domain=perf")
        self.assertEqual(code, 0)
        self.assertEqual([l for l in lines if l.startswith("selection:")], [])

    def test_changed_does_not_repeat_a_test_whose_domain_already_runs(self):
        _, lines = self.changed(["scenes/ai/behavior/behavior.gd", "tests/ai/goal_names_the_gun_test.gd",
                                 "tests/audio/bank_test.gd", "tests/audio/bank_test.gd.uid"])
        self.assertEqual([l for l in lines if l.startswith("selection:")],
                         ["selection: --domain=ai,perf", "selection: --id=audio/bank"])


class LintReportTests(unittest.TestCase):
    """tools/lint_report.py on crafted logs of the lint scene."""

    def report(self, text, *flags):
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
            f.write(text)
        try:
            env = {k: v for k, v in os.environ.items() if k != "GODOT"}  # no engine: lines stay candidates
            r = subprocess.run([sys.executable, "-I", str(ROOT / "tools" / "lint_report.py"), f.name, *flags],
                               capture_output=True, text=True, env=env)
        finally:
            os.unlink(f.name)
        return r.returncode, r.stdout

    CLEAN = "Godot Engine\nLINT-PASS2\nLINT> res://a.gd\nLINT> res://b.gd\nLINT-DONE 2\nERROR: leaked at exit\n"

    def test_clean_run_passes_and_ignores_what_the_engine_prints_at_exit(self):
        self.assertEqual(self.report(self.CLEAN)[0], 0)

    def test_quiet_prints_nothing_when_clean(self):
        self.assertEqual(self.report(self.CLEAN, "--quiet"), (0, ""))

    def test_a_warning_is_attributed_to_the_script_printed_before_it(self):
        code, out = self.report("LINT-PASS2\nLINT> res://a.gd\nLINT> res://b.gd\n\x1b[1;31mERROR: 'Integer division, decimal part will be discarded.'\nLINT-DONE 2\n")
        self.assertEqual(code, 1)
        self.assertIn("res://b.gd  (1)", out)
        self.assertNotIn("res://a.gd", out)

    def test_a_parse_error_fails(self):
        code, out = self.report("LINT-PASS2\nLINT> res://a.gd\nSCRIPT ERROR: Parse Error: broken\nLINT-DONE 1\n")
        self.assertEqual(code, 1)
        self.assertIn("broken", out)

    def test_a_lint_that_never_finished_fails(self):
        self.assertEqual(self.report("LINT-PASS2\nLINT> res://a.gd\n")[0], 1)


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class LintEngineTests(unittest.TestCase):
    """The real engine: the project lints clean, and a script with warnings is caught with its exact lines."""

    PROBE = ROOT / "tests" / "_harness" / "zz_lint_probe.gd"

    def lint(self, *args):
        env = dict(os.environ, GODOT=godot_binary())
        r = subprocess.run(["bash", str(ROOT / "tools" / "lint.sh"), *args], cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
        return r.returncode, r.stdout + r.stderr

    def test_the_project_is_clean(self):
        code, out = self.lint()
        self.assertEqual(code, 0, out)

    def test_warnings_are_found_per_file_with_the_division_pinpointed(self):
        self.PROBE.write_text("extends RefCounted\n\n\nfunc f(wrap: bool) -> int:\n\tvar unused := 1\n\treturn 5 / 2\n")
        try:
            code, out = self.lint("tests/_harness/zz_lint_probe.gd")
        finally:
            self.PROBE.unlink()
        self.assertEqual(code, 1, out)
        self.assertIn("res://tests/_harness/zz_lint_probe.gd  (4)", out)
        self.assertIn("declared but never used", out)
        self.assertIn("same name as a built-in function", out)
        self.assertIn("[line:col 6:11]", out)


@unittest.skipUnless(godot_binary(), "no Godot binary (set GODOT=/path/to/Godot)")
class EngineTests(unittest.TestCase):
    """The real engine: an error or warning logged during a test must fail it, in batch and in the in-game runner."""

    PROBE = "_harness/log_gate_probe"

    def batch(self, probe, headed):
        env = dict(os.environ, GAME_TEST_PROBE=probe, GODOT=godot_binary())
        args = ["bash", str(RUN), "--self-test", f"--id={self.PROBE}", "--summary"] + (["--shots"] if headed else [])
        r = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
        return r.returncode, r.stdout + r.stderr

    def in_game(self, probe, headed):
        """The interactive runner (`-- --play`), which prints each verdict; it is stopped by --quit-after."""
        # No --log-file: a person runs the game with the default log (project setting debug/file_logging), which the
        # in-game runner follows; only a batch run started with --out is told where its log went.
        cmd = [godot_binary()] + ([] if headed else ["--headless"]) + [
            "--path", str(ROOT), "--fixed-fps", "60", "--quit-after", "420",
            "res://scenes/testing/test_runner.tscn", "--", "--play", "log", "gate", "probe"]
        r = subprocess.run(cmd, cwd=ROOT, env=dict(os.environ, GAME_TEST_PROBE=probe), capture_output=True, text=True, timeout=300)
        return r.stdout + "\n" + r.stderr

    def check_mode(self, headed):
        code, out = self.batch("", headed)
        self.assertEqual(code, 0, "no probe: the run passes\n" + out)
        for probe in ("error", "warning"):
            code, out = self.batch(probe, headed)
            self.assertEqual(code, 1, f"a logged {probe} fails the batch run\n" + out)
            self.assertIn(f"Logged {probe}: gate probe {probe}", out)
        out = self.in_game("", headed)
        self.assertRegex(out, r"PASS\s+_harness/log_gate_probe", "in-game, no probe: PASS\n" + out)
        for probe in ("error", "warning"):
            out = self.in_game(probe, headed)
            self.assertRegex(out, r"FAIL\s+_harness/log_gate_probe", f"in-game, a logged {probe} fails the test\n" + out)
            self.assertIn(f"Logged {probe}: gate probe {probe}", out)

    def test_headless(self):
        self.check_mode(False)

    @unittest.skipUnless(HEADED, "pass --headed to run the windowed engine")
    def test_headed(self):
        self.check_mode(True)


if __name__ == "__main__":
    sys.argv = [a for a in sys.argv if a != "--headed"]
    unittest.main(verbosity=2)
