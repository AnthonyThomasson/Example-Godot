#!/usr/bin/env bash
# Run the game tests headless (scenes/testing/test_runner.gd, batch mode) and exit non-zero on any
# failure, timeout, or engine error/warning logged ANYWHERE in the run: while a test is open (that test
# fails), between tests and at start-up (reported as "Logged outside any test"), and after the runner has
# finished judging (engine shutdown; tools/scan_godot_log.py reads that tail of each process's log).
#
# Selecting tests
#   tools/run_tests.sh                    every test (Von tests skipped)
#   tools/run_tests.sh projectile         only tests matching "projectile" (id, name, domain, tag;
#                                         every word must start a word of one of those)
#   tools/run_tests.sh --domain=ai        only the tests of exactly that domain; comma list allowed
#                                         (--domain=ai,navigation). No word-prefix matching.
#   tools/run_tests.sh --id=ai/foo_bar    exactly that test id (comma list allowed)
#   tools/run_tests.sh --failed           only the tests that FAILED / TIMED OUT in the previous run
#                                         of this checkout (its report is kept in $TMPDIR)
#   tools/run_tests.sh --changed          tests for what uncommitted changes can affect: each changed
#                                         scenes/<domain>/ plus the domains that compose it (see
#                                         `affected` below), in ONE run; main.gd, root scenes,
#                                         project.godot, worldgen, art and general run everything;
#                                         testing adds --self-test.
#   tools/run_tests.sh --list [words]     list matching tests (id, flags, tags, name) and exit
#   tools/run_tests.sh --include-von ai   also run tests that need the Von decision server
#   tools/run_tests.sh --require-von ai   Von tests FAIL instead of skipping when no server is live
#   tools/run_tests.sh --self-test        the harness's own tests (tests/_harness, hidden from normal runs)
# Speed
#   --jobs=N|auto   split the run over N parallel godot processes (auto = cores, at most 4). The
#                   tests are dealt out to balance the shards by timeout; Von tests all stay in shard 0. One combined
#                   summary is printed; exit 1 if any shard failed. Not used with --list/--self-test.
#   --fail-fast     stop after the first FAIL / TIMEOUT (per shard when sharded)
# Output
#   --summary       print only the non-passing tests and the totals (best for an agent or a hook)
#   --verbose       also print the game's log of what happens (shots, punches, Von decisions, PERF
#                   numbers); a run is quiet by default
#   --json          also print the full results as one `JSON: {...}` line
#   --shots         windowed run (not headless) that saves a PNG of each failed test
# Other
#   --repeat=5      run each match 5 times; names FLAKY / FAILING tests
#   --seed=42       pin every house() test to seed 42
#   --strict-exit   also fail on Godot's own end-of-process leak report (reported as a NOTE by default)
# Every run ends with a `Slowest:` line (wall-clock ms per test).
# A failed test prints its final actor state and a `bundle:` path to a JSON with its event log,
# state and traces. Each invocation gets its own engine log, report and bundles in a fresh temp dir
# (printed as `Report:` / `bundle:`), so concurrent runs and a running game never share files.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$( command -v godot || command -v godot4 \
  || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )}"
if [[ -z "$GODOT" ]]; then
  echo "Godot binary not found (set GODOT=/path/to/Godot)" >&2
  exit 2
fi

# A fresh checkout has no import cache (.godot/ is untracked): without the class cache every test script
# fails to parse and the runner hangs instead of failing, so import first.
if [[ ! -f .godot/global_script_class_cache.cfg ]]; then
  echo "importing the project (first run in this checkout)..." >&2
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

# The previous run's merged report, per checkout, for --failed.
LAST="${TMPDIR:-/tmp}/example_godot_last_report_$(printf %s "$PWD" | shasum | cut -c1-8).json"

HEADLESS=--headless
STRICT=
JOBS=1
CHANGED=0
args=()
for a in "$@"; do
  case "$a" in
    --shots) HEADLESS=; args+=("$a") ;;
    --strict-exit) STRICT=--strict-exit ;;
    --jobs=*) JOBS="${a#--jobs=}" ;;
    --changed) CHANGED=1 ;;
    --failed)
      [[ -f "$LAST" ]] || { echo "No previous run of this checkout to take failures from." >&2; exit 2; }
      args+=("--failed=$LAST") ;;
    *) args+=("$a") ;;
  esac
done
if [[ "$JOBS" == "auto" ]]; then
  cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)
  JOBS=$(( cores < 4 ? cores : 4 ))
fi
[[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || { echo "--jobs wants a number or auto" >&2; exit 2; }

# Start one godot process writing its log/report/bundles to $1 (a fresh dir); extra args follow.
godot_run() {
  local out="$1"; shift
  "$GODOT" $HEADLESS --path . --fixed-fps 60 --log-file "$out/godot.log" \
    res://scenes/testing/test_runner.tscn -- --run-tests --out="$out" "$@"
}

# Merge the report.json of each dir given into $LAST (what --failed reads).
save_reports() {
  python3 - "$LAST" "$@" <<'EOF'
import json, os, sys
results, stray = [], []
for d in sys.argv[2:]:
    try:
        data = json.load(open(os.path.join(d, "report.json")))
    except Exception:
        continue
    results += data.get("results", [])
    stray += data.get("stray_logs", [])
if results or stray:
    json.dump({"results": results, "stray_logs": stray}, open(sys.argv[1], "w"))
EOF
}

# Check the engine log of the process that wrote into dir $1 for errors and warnings the runner did not
# judge: from the byte offset it reports as `log_end` (shutdown), or from the start when it wrote no report
# (--list, a crash, a start-up failure). Prints what it finds; returns non-zero on any.
scan_log() {
  local dir="$1" listing="$2" from=0 bad=0
  if [[ -f "$dir/report.json" ]]; then
    from=$(python3 -c 'import json,sys; print(int(json.load(open(sys.argv[1])).get("log_end", 0)))' "$dir/report.json" 2>/dev/null || echo 0)
  elif [[ "$listing" -eq 0 ]]; then
    echo "Logged outside any test: the runner wrote no report (it crashed or stopped early) in $dir"
    bad=1
  fi
  python3 "$(dirname "$0")/scan_godot_log.py" "$dir/godot.log" --from="$from" $STRICT || bad=1
  return $bad
}

# One run of the runner with the given selection args, split over $JOBS processes when asked.
run() {
  local keep=1 sharded=0 listing=0
  [[ $JOBS -gt 1 ]] && sharded=1
  for x in "$@" ${args[@]+"${args[@]}"}; do
    case "$x" in --list|--self-test|--play|--shard=*) sharded=0 ;; esac
    case "$x" in --list|--self-test) keep=0 ;; esac
    case "$x" in --list) listing=1 ;; esac
  done
  local out
  if [[ $sharded -eq 0 ]]; then
    out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
    local code=0
    godot_run "$out" "$@" ${args[@]+"${args[@]}"} || code=$?
    [[ $keep -eq 1 ]] && save_reports "$out"
    [[ " $* ${args[*]-} " == *" --play "* ]] || scan_log "$out" $listing || code=1
    return $code
  fi

  local dirs=() pids=() i
  for ((i = 0; i < JOBS; i++)); do
    out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
    dirs+=("$out")
    godot_run "$out" "$@" ${args[@]+"${args[@]}"} --shard="$i/$JOBS" >"$out/stdout.txt" 2>&1 &
    pids+=($!)
  done
  local status=0 pid
  for pid in "${pids[@]}"; do wait "$pid" || status=1; done
  for ((i = 0; i < JOBS; i++)); do scan_log "${dirs[$i]}" 0 >>"${dirs[$i]}/stdout.txt" 2>&1 || status=1; done
  # Per-shard output without the repeated banners and totals, then one combined total.
  for ((i = 0; i < JOBS; i++)); do
    grep -Ev '^(Godot Engine|Godot [0-9]|Running [0-9]+ test|[0-9]+ passed, |Report: |$)' "${dirs[$i]}/stdout.txt" || true
  done
  local files=()
  for out in "${dirs[@]}"; do files+=("$out/stdout.txt"); done
  grep -h -E '^[0-9]+ passed, ' "${files[@]}" | sed -E 's/[^0-9]+/ /g' \
    | awk -v n="$JOBS" '{p+=$1; f+=$2; t+=$3; s+=$4} END {printf "%d passed, %d failed, %d timed out, %d skipped  (%d shards)\n", p, f, t, s, n}'
  save_reports "${dirs[@]}"
  return $status
}

# Which test domains a change to scenes/<domain>/ can break: the domain itself plus everything that
# composes it (from the architecture skill's dependency graph). "all" = the whole suite.
affected() {
  case "$1" in
    ai) echo ai ;;
    navigation) echo navigation ai ;;
    interaction) echo interaction character ai ;;
    items) echo items projectile character ai ;;
    projectile) echo projectile physics objects character items ai ;;
    physics) echo physics objects projectile character items ai ;;
    objects) echo objects physics projectile character items interaction navigation ai ;;
    character) echo character items interaction projectile physics objects ai ;;
    ui) echo ui ;;
    worldgen|art|general|testing|audio) echo all ;;  # audio: the Sound autoload runs in every test
    *) echo all ;;  # anything unknown is treated as risky
  esac
}

if [[ $CHANGED -eq 1 ]]; then
  files=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u )
  domains=""
  self_test=0
  for f in $files; do
    case "$f" in
      scenes/testing/*|scenes/ai/decision/decision_stub.gd|scenes/ai/decision/decision_client.gd) self_test=1 ;;
    esac
    case "$f" in
      scenes/*/*|tests/*/*) d=$(echo "$f" | cut -d/ -f2); [[ "$d" == "_harness" ]] && { self_test=1; continue; }
                            domains="$domains $(affected "$d")" ;;
      scenes/*|project.godot) domains="$domains all" ;;   # main.gd, root scenes, autoload wiring
    esac
  done
  domains=$(echo $domains | tr ' ' '\n' | sort -u | tr '\n' ' ')
  status=0
  ran=0
  if [[ " $domains " == *" all "* ]]; then
    ran=1
    echo "== all tests (a changed file can affect every domain) =="
    run || status=1
  else
    existing=""
    for d in $domains; do [[ -d "tests/$d" ]] && existing="$existing,$d"; done
    if [[ -n "$existing" ]]; then
      ran=1
      echo "== ${existing#,} =="
      run "--domain=${existing#,}" || status=1
    fi
  fi
  if [[ $self_test -eq 1 ]]; then
    ran=1
    echo "== harness self-tests =="
    run --self-test || status=1
  fi
  [[ $ran -eq 1 ]] || echo "No changed file maps to any tests (affected: ${domains:-none})."
  exit $status
fi

run
