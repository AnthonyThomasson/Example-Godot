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
#   tools/run_tests.sh --skip-domain=perf leave out the tests of exactly that domain (comma list allowed); wins over
#                                         every other selection, --changed's included. The pre-commit hook skips perf:
#                                         its frame-time budgets fail on a loaded machine, so they are a separate run.
#   tools/run_tests.sh --failed           only the tests that FAILED / TIMED OUT in the previous run
#                                         of this checkout (its report is kept in $TMPDIR)
#   tools/run_tests.sh --changed          tests for what uncommitted changes can affect: each changed
#                                         scenes/<domain>/ plus the domains that compose it (see
#                                         `affected` below), in ONE run; main.gd, root scenes,
#                                         project.godot, worldgen, art and general run everything;
#                                         testing adds --self-test. An edited tests/<d>/[<topic>/]<name>_test.gd
#                                         runs just that test; tests/_ai, _audio, _perf, _vehicle their users.
#   tools/run_tests.sh --list [words]     list matching tests (id, flags, tags, name) and exit
#   tools/run_tests.sh --include-von ai   also run tests that need the Von decision server
#   tools/run_tests.sh --require-von ai   Von tests FAIL instead of skipping when no server is live
#   tools/run_tests.sh gap                the tests tagged `gap`: specs the code does not meet yet, written first and
#                                         left red; their failure is reported as GAP and does not fail the run, and one
#                                         that passes FAILs ("drop the gap tag")
#   tools/run_tests.sh --self-test        the harness's own tests (tests/_harness, hidden from normal runs)
# Speed
#   --jobs=N|auto   split the run over N parallel godot processes (auto = cores, at most 6). Without it, a run of the
#                   whole suite uses auto and a selection (words, --id, --domain, --failed, --repeat) one process. The
#                   tests are dealt out to balance the shards by the wall-clock ms measured in earlier runs (kept in
#                   $TMPDIR, falling back to the declared timeout); Von tests all stay in shard 0. One combined
#                   summary and slowest list is printed; exit 1 if any shard failed. Not used with --list/--self-test.
#   --fail-fast     stop after the first FAIL / TIMEOUT (per shard when sharded)
# Output
#   --summary       print only the non-passing tests and the totals (best for an agent or a hook)
#   --verbose       also print the game's log of what happens (shots, punches, Von decisions, PERF
#                   numbers); a run is quiet by default
#   --json          also print the full results as one `JSON: {...}` line
#   --shots         windowed run (not headless) that saves a PNG of each failed test
#   --windowed      windowed run with vsync off, in one process: a perf test's frame times then include the render
#                   (headless measures the CPU only) without being held to the display's refresh
# Other
#   --repeat=5      run each match 5 times; names FLAKY / FAILING tests
#   --seed=42       pin every house() test to seed 42
#   --strict-exit   also fail on Godot's own end-of-process leak report (reported as a NOTE by default)
#   --no-lint       skip the GDScript lint that runs first (tools/lint.sh, ~5 s: unused variables, integer
#                   division, shadowed names ... the warnings of the editor's Debugger > Errors tab). Any warning
#                   fails the run before a single test starts. Not run for --list or --self-test, nor when
#                   the sources are unchanged since the last clean lint (fingerprint kept in $TMPDIR).
# Not here: --play <words> (play one test or sandbox in the runner) is the runner's own flag; this wrapper only runs
# batches, so it refuses --play and prints the command that launches the runner.
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

# Per-checkout state kept in $TMPDIR: the previous run's merged report (for --failed), the measured wall-clock
# ms per test (what --shard balances the parallel processes by) and the fingerprint of the last clean lint.
KEY=$(printf %s "$PWD" | shasum | cut -c1-8)
LAST="${TMPDIR:-/tmp}/example_godot_last_report_$KEY.json"
COSTS="${TMPDIR:-/tmp}/example_godot_costs_$KEY.json"
LINT_OK="${TMPDIR:-/tmp}/example_godot_lint_ok_$KEY.txt"

HEADLESS=--headless
NOVSYNC=
WINDOWED=0
STRICT=
JOBS=
CHANGED=0
LINT=1
SKIP=""   # --skip-domain=a,b, also forwarded to the runner
args=()
for a in "$@"; do
  case "$a" in
    --shots) HEADLESS=; args+=("$a") ;;
    --windowed) HEADLESS=; NOVSYNC=--disable-vsync; WINDOWED=1 ;;
    --play)
      echo "--play is the test runner's own flag; this wrapper only runs batches (and they never see sandboxes). Launch the runner:" >&2
      echo "  \"\$GODOT\" --path . res://scenes/testing/test_runner.tscn -- --play <words>" >&2
      exit 2 ;;
    --strict-exit) STRICT=--strict-exit ;;
    --jobs=*) JOBS="${a#--jobs=}" ;;
    --changed) CHANGED=1 ;;
    --no-lint) LINT=0 ;;
    --skip-domain=*) SKIP="${a#--skip-domain=}"; args+=("$a") ;;
    --failed)
      [[ -f "$LAST" ]] || { echo "No previous run of this checkout to take failures from." >&2; exit 2; }
      args+=("--failed=$LAST") ;;
    *) args+=("$a") ;;
  esac
done
# --jobs=N|auto is explicit; without it a run of the whole suite uses auto and a selection (words, --id,
# --domain, --failed, --repeat, --list ...) one process, since a process costs ~2 s to start and a few tests
# do not repay it. Resolved per run() call in `jobs_for`.
JOBS_EXPLICIT=0
[[ -n "$JOBS" ]] && JOBS_EXPLICIT=1
auto_jobs() {
  local cores
  cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 2)
  echo $(( cores < 6 ? cores : 6 ))
}
if [[ $JOBS_EXPLICIT -eq 1 ]]; then
  [[ "$JOBS" == "auto" ]] && JOBS=$(auto_jobs)
  [[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || { echo "--jobs wants a number or auto" >&2; exit 2; }
fi
# The number of processes for a run() with these arguments (the selection args it was called with + the global ones).
jobs_for() {
  local x ids n
  [[ $WINDOWED -eq 1 ]] && { echo 1; return; }  # one window, and no shard competing with what it measures
  if [[ $JOBS_EXPLICIT -eq 1 ]]; then
    # No more processes than there are tests when the selection is a list of ids.
    for x in "$@"; do
      case "$x" in --id=*) ids="${x#--id=}"; n=$(echo "$ids" | tr ',' '\n' | grep -c . || true)
                           if [[ $n -ge 1 && $n -lt $JOBS ]]; then echo "$n"; return; fi ;;
      esac
    done
    echo "$JOBS"; return
  fi
  for x in "$@"; do
    case "$x" in
      --*) case "$x" in --id=*|--domain=*|--failed=*|--shots|--list|--self-test|--repeat=*) echo 1; return ;; esac ;;
      *) echo 1; return ;;  # a filter word
    esac
  done
  auto_jobs
}

# Start one godot process writing its log/report/bundles to $1 (a fresh dir); extra args follow.
godot_run() {
  local out="$1"; shift
  "$GODOT" $HEADLESS $NOVSYNC --path . --fixed-fps 60 --log-file "$out/godot.log" \
    res://scenes/testing/test_runner.tscn -- --run-tests --out="$out" "$@"
}

# Merge the report.json of each dir given into $LAST (what --failed reads) and fold each test's wall-clock ms into
# $COSTS (what --shard balances the processes by: the mean of the old and the new measurement; a skip or a timeout
# says nothing about how long a test takes). With SLOWEST=1 it also prints the five slowest tests of the merged run.
save_reports() {
  python3 - "$LAST" "$COSTS" "${SLOWEST:-0}" "$@" <<'EOF'
import json, os, sys
last, costs_path, slowest = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
results, stray = [], []
for d in sys.argv[4:]:
    try:
        data = json.load(open(os.path.join(d, "report.json")))
    except Exception:
        continue
    results += data.get("results", [])
    stray += data.get("stray_logs", [])
if results or stray:
    json.dump({"results": results, "stray_logs": stray}, open(last, "w"))
fresh = {}
for r in results:
    if r.get("status") in ("PASS", "FAIL", "GAP") and r.get("wall_ms", 0) > 0:
        fresh.setdefault(r["id"], []).append(r["wall_ms"])
if fresh:
    try:
        costs = json.load(open(costs_path))
    except Exception:
        costs = {}
    for test_id, ms in fresh.items():
        mean = sum(ms) / len(ms)
        costs[test_id] = mean if test_id not in costs else (costs[test_id] + mean) / 2
    json.dump(costs, open(costs_path + ".tmp", "w"))
    os.replace(costs_path + ".tmp", costs_path)
if slowest and len(fresh) > 1:
    top = sorted(((sum(v) / len(v), k) for k, v in fresh.items()), reverse=True)[:5]
    print("Slowest: " + ", ".join("%s %d ms" % (k, ms) for ms, k in top))
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

# One run of the runner with the given selection args, split over several processes when asked (see jobs_for).
run() {
  local keep=1 sharded=0 listing=0 jobs x
  jobs=$(jobs_for "$@" ${args[@]+"${args[@]}"})
  [[ $jobs -gt 1 ]] && sharded=1
  for x in "$@" ${args[@]+"${args[@]}"}; do
    case "$x" in --list|--self-test|--shard=*) sharded=0 ;; esac
    case "$x" in --list|--self-test) keep=0 ;; esac
    case "$x" in --list) listing=1 ;; esac
  done
  local out
  if [[ $sharded -eq 0 ]]; then
    out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
    local code=0
    godot_run "$out" "$@" ${args[@]+"${args[@]}"} || code=$?
    [[ $keep -eq 1 ]] && save_reports "$out"
    scan_log "$out" $listing || code=1
    return $code
  fi

  # Every shard reads the same costs snapshot (the file is only rewritten once they have all finished), so they
  # all compute the same split.
  local costs_args=()
  [[ -f "$COSTS" ]] && costs_args=("--costs=$COSTS")
  local dirs=() pids=() i
  for ((i = 0; i < jobs; i++)); do
    out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
    dirs+=("$out")
    godot_run "$out" "$@" ${args[@]+"${args[@]}"} ${costs_args[@]+"${costs_args[@]}"} --shard="$i/$jobs" >"$out/stdout.txt" 2>&1 &
    pids+=($!)
  done
  local status=0 pid
  for pid in "${pids[@]}"; do wait "$pid" || status=1; done
  for ((i = 0; i < jobs; i++)); do scan_log "${dirs[$i]}" 0 >>"${dirs[$i]}/stdout.txt" 2>&1 || status=1; done
  # Per-shard output without the repeated banners, totals and partial slowest lists, then one combined
  # slowest list (not with --summary, like the runner) and one combined total.
  for ((i = 0; i < jobs; i++)); do
    grep -Ev '^(Godot Engine|Godot [0-9]|Running [0-9]+ test|[0-9]+ passed, |Report: |Slowest: |$)' "${dirs[$i]}/stdout.txt" || true
  done
  local files=() show_slowest=1
  for out in "${dirs[@]}"; do files+=("$out/stdout.txt"); done
  for x in "$@" ${args[@]+"${args[@]}"}; do [[ "$x" == "--summary" ]] && show_slowest=0; done
  SLOWEST=$show_slowest save_reports "${dirs[@]}"
  grep -h -E '^[0-9]+ passed, ' "${files[@]}" | sed -E 's/[^0-9]+/ /g' \
    | awk -v n="$jobs" '{p+=$1; f+=$2; t+=$3; s+=$4; g+=$5} END {printf "%d passed, %d failed, %d timed out, %d skipped, %d gap  (%d shards)\n", p, f, t, s, g, n}'
  return $status
}

# Which test domains a change to scenes/<domain>/ can break: the domain itself plus everything that
# composes it (from the architecture skill's dependency graph). "all" = the whole suite.
affected() {
  case "$1" in
    ai) echo ai perf ;;
    navigation) echo navigation ai perf ;;
    interaction) echo interaction character ai ;;
    items) echo items projectile character ai perf ;;
    projectile) echo projectile physics objects character items ai perf ;;
    physics) echo physics objects projectile character items ai perf ;;
    objects) echo objects physics projectile character items interaction navigation ai perf ;;
    character) echo character items interaction projectile physics objects ai perf ;;
    # The character composes the vehicle's CharacterVehicleUse; the camera (general) and Sound (audio) read the vehicle.
    vehicle) echo vehicle character items interaction projectile physics objects ai perf audio general ;;
    ui) echo ui ;;
    # audio: the Sound autoload runs in every test; lighting: every test world is lit (WorldLighting).
    worldgen|art|general|testing|audio|lighting) echo all ;;
    *) echo all ;;  # anything unknown is treated as risky
  esac
}

# The lint comes first: it takes seconds, and a script the analyzer complains about is not worth a test run.
for x in ${args[@]+"${args[@]}"}; do
  case "$x" in --list|--self-test) LINT=0 ;; esac
done
# The same sources lint the same: the fingerprint of the last clean lint (HEAD plus every uncommitted change,
# the way tools/stop_hook_checks.sh fingerprints) is kept in $LINT_OK, and a run on an identical tree skips the
# ~4 s. Any edit, new file or new commit changes it, so the lint still runs before every first test run.
lint_fingerprint() {
  { git rev-parse HEAD; git diff HEAD; git ls-files --others --exclude-standard | while read -r f; do echo "$f"; shasum "$f"; done; } \
    | shasum | cut -d' ' -f1
}
if [[ $LINT -eq 1 ]]; then
  fingerprint=$(lint_fingerprint)
  if [[ -f "$LINT_OK" && "$(cat "$LINT_OK")" == "$fingerprint" ]]; then
    echo "lint skipped: the sources are unchanged since the last clean lint" >&2
  else
    lint_out=$("$(dirname "$0")/lint.sh" 2>&1) || { echo "$lint_out"; echo "GDScript lint failed: no tests were run (--no-lint skips it)." >&2; exit 1; }
    echo "$fingerprint" > "$LINT_OK"
  fi
fi

if [[ $CHANGED -eq 1 ]]; then
  # GAME_TEST_CHANGED_FILES (newline-separated paths) stands in for git's view of the changes: tools/test_log_gate.py
  # uses it to test the mapping below without crafting a working tree.
  if [[ -n "${GAME_TEST_CHANGED_FILES:-}" ]]; then
    files="$GAME_TEST_CHANGED_FILES"
  else
    files=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u )
  fi
  domains=""   # domains a changed scene can break, with the ones that compose it (see `affected`)
  exact=""     # domains whose own tests a changed test helper feeds, and nothing beyond them
  ids=""       # test ids of changed test files: an edited test can only change its own result
  perf=0       # the shared perf helper changed: every test of the perf domain
  self_test=0
  for f in $files; do
    case "$f" in
      scenes/testing/*|scenes/ai/decision/decision_stub.gd|scenes/ai/decision/decision_client.gd) self_test=1 ;;
    esac
    case "$f" in
      tests/_harness/*) self_test=1 ;;
      tests/_ai/*) exact="$exact ai" ;;
      tests/_audio/*) exact="$exact audio" ;;
      tests/_lighting/*) exact="$exact lighting" ;;
      tests/_vehicle/*) exact="$exact vehicle audio general" ;;   # also feeds audio/vehicle_sounds and the general vehicle tests
      tests/_perf/*) perf=1 ;;
      tests/_*/*) domains="$domains all" ;;    # an unknown helper folder: assume the worst
      tests/*/*.uid) ;;                        # generated next to a script
      tests/*/*_test.gd) [[ -f "$f" ]] && { id="${f#tests/}"; ids="$ids ${id%_test.gd}"; } ;;
      tests/*/*) exact="$exact $(echo "$f" | cut -d/ -f2)" ;;   # some other file in a domain's test folder
      scenes/*/*) domains="$domains $(affected "$(echo "$f" | cut -d/ -f2)")" ;;
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
    for d in $domains $exact; do
      [[ -d "tests/$d" && ",$existing," != *",$d,"* ]] && existing="$existing,$d"
    done
    if [[ -n "$existing" ]]; then
      ran=1
      echo "== ${existing#,} =="
      run "--domain=${existing#,}" || status=1
    fi
    # Changed test files whose domain is not already running above.
    only_ids=""
    for id in $ids; do
      [[ ",$existing," == *",${id%%/*},"* ]] || only_ids="$only_ids,$id"
    done
    if [[ -n "$only_ids" ]]; then
      ran=1
      echo "== ${only_ids#,} =="
      run "--id=${only_ids#,}" || status=1
    fi
    if [[ $perf -eq 1 && ",$SKIP," != *",perf,"* ]]; then
      ran=1
      echo "== perf tests (tests/_perf changed) =="
      run --domain=perf || status=1
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
