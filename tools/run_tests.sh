#!/usr/bin/env bash
# Run the game tests headless (scenes/testing/test_runner.gd, batch mode) and exit non-zero on any
# failure, timeout, or engine error/warning logged during the run.
#
#   tools/run_tests.sh                    every test (Von tests skipped)
#   tools/run_tests.sh projectile         only tests matching "projectile" (id, name, domain, tag)
#   tools/run_tests.sh --include-von ai   also run tests that need the Von decision server
#   tools/run_tests.sh --require-von ai   Von tests FAIL instead of skipping when no server is live
#   tools/run_tests.sh --list [words]     list matching tests (id, flags, tags, name) and exit
#   tools/run_tests.sh --repeat=5 words   run each match 5 times; names FLAKY / FAILING tests
#   tools/run_tests.sh --seed=42 words    pin every house() test to seed 42
#   tools/run_tests.sh --json words       also print the full results as one `JSON: {...}` line
#   tools/run_tests.sh --self-test       the harness's own tests (tests/_harness, hidden from normal runs)
#   tools/run_tests.sh --shots words      windowed run (not headless) that saves a PNG of each failed test
#   tools/run_tests.sh --changed          tests for what uncommitted changes can affect: each changed
#                                         scenes/<domain>/ plus the domains that compose it (see
#                                         `affected` below); main.gd, root scenes, project.godot, worldgen,
#                                         art and general run everything; testing adds --self-test.
#                                         Other flags pass through.
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

HEADLESS=--headless
for a in "$@"; do [[ "$a" == "--shots" ]] && HEADLESS=; done

run() {
  local out
  out=$(mktemp -d "${TMPDIR:-/tmp}/game_tests.XXXXXX")
  "$GODOT" $HEADLESS --path . --fixed-fps 60 --log-file "$out/godot.log" \
    res://scenes/testing/test_runner.tscn -- --run-tests --out="$out" "$@"
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
    worldgen|art|general|testing) echo all ;;
    *) echo all ;;  # anything unknown is treated as risky
  esac
}

if [[ "${1:-}" == "--changed" ]]; then
  shift
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
    run "$@" || status=1
  else
    for d in $domains; do
      [[ -d "tests/$d" ]] || continue
      ran=1
      echo "== $d =="
      run "$@" "$d" || status=1
    done
  fi
  if [[ $self_test -eq 1 ]]; then
    ran=1
    echo "== harness self-tests =="
    run "$@" --self-test || status=1
  fi
  [[ $ran -eq 1 ]] || echo "No changed file maps to any tests (affected: ${domains:-none})."
  exit $status
fi

run "$@"
