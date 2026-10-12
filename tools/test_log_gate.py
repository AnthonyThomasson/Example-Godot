#!/usr/bin/env python3
"""Tests for the gate that fails a test run on any engine error or warning.

  python3 tools/test_log_gate.py            scanner + wrapper (fake Godot) + the real engine, headless
  python3 tools/test_log_gate.py --headed   also the real engine WITH a window (batch --shots and the in-game runner)

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
# Stands in for Godot: writes the engine log and runner report that $FAKE_SCENARIO describes.
log=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log-file) log="$2"; shift ;;
    --out=*) out="${1#--out=}" ;;
    --shard=*) shard="${1#--shard=}" ;;
  esac
  shift
done
head='Godot Engine v4.4'
judged='ERROR: a test provoked this (the runner already failed that test)'
echo "$head" > "$log"
report() { printf '{"results": [], "stray_logs": [], "log_end": %s}' "$(wc -c < "$log" | tr -d ' ')" > "$out/report.json"; }
echo "0 passed, 0 failed, 0 timed out, 0 skipped"
case "$FAKE_SCENARIO" in
  clean) report ;;
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

    def run_wrapper(self, scenario, *args):
        env = dict(os.environ, GODOT=str(self.fake), FAKE_SCENARIO=scenario, TMPDIR=str(self.tmp))
        r = subprocess.run(["bash", str(RUN), *args], cwd=ROOT, env=env, capture_output=True, text=True)
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

    def test_one_failing_shard_fails_the_whole_run(self):
        self.assertEqual(self.run_wrapper("shard1_error", "--jobs=2")[0], 1)
        self.assertEqual(self.run_wrapper("clean", "--jobs=2")[0], 0)


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
