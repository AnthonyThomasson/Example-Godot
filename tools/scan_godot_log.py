#!/usr/bin/env python3
"""Fail when a Godot log holds an error or warning.

  python3 tools/scan_godot_log.py LOG [--from=BYTES] [--strict-exit]

Reads LOG (written by `godot --log-file LOG`) from byte BYTES (default 0) to the end and prints every error / warning
entry; exit 1 when there is one, 0 when the part scanned is clean. tools/run_tests.sh scans what the engine wrote
after the test runner stopped judging the log (`log_end` in its report) and the whole log when the runner never got
that far; tools/load_check.sh scans a plain headless start-up.

The header list mirrors scenes/testing/log_watch.gd, which does the same job inside the running game.

One class of output is reported as a NOTE and does not fail the scan unless --strict-exit is given: Godot's own
end-of-process leak report ("ObjectDB instances leaked at exit", "resources still in use at exit", "RID
allocations ... leaked at exit", the SelfList `p_elem->_root != this` line printed beside it). The engine prints it
when the process tears down with script resources still referenced; a run that touches a character together with
a reflectively read config holder (e.g. `CharacterConfig`) shows it, whatever the test checks.
"""
import re
import sys

HEADERS = ["USER SCRIPT ERROR:", "SCRIPT ERROR:", "SHADER ERROR:", "USER ERROR:", "ERROR:",
           "USER SCRIPT WARNING:", "SCRIPT WARNING:", "SHADER WARNING:", "USER WARNING:", "WARNING:"]
ALLOWED = ["[von] "]  # the Von launcher's diagnostics (log_watch.gd GLOBAL_ALLOWED)
EXIT_NOISE = [
    r"ObjectDB instances leaked at exit",
    r"\d+ resources still in use at exit",
    r"\d+ RID allocations of type .* were leaked at exit",
    r'Condition "p_elem->_root != this" is true',
]
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def entries(text: str):
    """Yield (header, message, location) for each error/warning entry in `text`."""
    lines = [ANSI.sub("", l.rstrip("\r")) for l in text.split("\n")]
    i = 0
    while i < len(lines):
        line = lines[i]
        header = next((h for h in HEADERS if line.startswith(h)), None)
        if header:
            msg = line[len(header):].strip()
            loc = ""
            if i + 1 < len(lines) and lines[i + 1].strip().startswith("at:"):
                loc = lines[i + 1].strip()[3:].strip()
                i += 1
            yield header, msg, loc
        i += 1


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        return 2
    start = 0
    strict = "--strict-exit" in sys.argv
    for a in sys.argv[1:]:
        if a.startswith("--from="):
            start = int(a.split("=", 1)[1])
    try:
        data = open(args[0], "rb").read()
    except OSError:
        print(f"Logged outside any test: engine log {args[0]} was not written")
        return 1
    text = data[start:].decode("utf-8", errors="replace")
    bad, noise = [], []
    for header, msg, loc in entries(text):
        full = f"{msg} {loc}"
        if any(a in full for a in ALLOWED):
            continue
        item = f"        ✗ {header.rstrip(':').lower()}: {msg}{' (' + loc + ')' if loc else ''}"
        if not strict and any(re.search(p, msg + " " + loc) for p in EXIT_NOISE):
            noise.append(item)
        else:
            bad.append(item)
    if noise:
        print(f"NOTE  engine shutdown leak report ({len(noise)} line(s); fails only with --strict-exit)")
    if bad:
        print(f"Logged outside any test ({len(bad)}):")
        print("\n".join(bad))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
