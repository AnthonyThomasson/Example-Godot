class_name GameTest extends RefCounted

## Testing domain: the base class every game test extends (`tests/<domain>/<name>_test.gd`). A test
## is three steps the runner calls in order:
##   describe()          — static facts about the test (name, tags, timeout, needs Von, …),
##   configure(setup)    — fill a TestSetup: the world, who/what is in it, which behaviours are on,
##   run(t)              — a coroutine that drives the scene and asserts through the TestContext.
## Any engine error or warning logged while it runs fails it (see log_watch.gd).

## Facts about the test. Every key is optional:
##   name: String          — shown in the browser (default: the file name, humanized)
##   domain: String        — group in the browser (default: the folder under tests/)
##   description: String   — longer text for the browser's details pane
##   tags: Array[String]   — extra search terms
##   timeout: float        — sim seconds before the test is stopped as TIMEOUT (default 10)
##   requires_von: bool    — needs a live Von decision server; SKIPPED without one (default false)
##   (sandboxes — `res://sandboxes/*_sandbox.gd`, same base class — are played by hand: no assertions, no timeout, never in a batch run)
##   internal: bool        — a harness self-test: hidden from the browser and normal runs, run by
##                           `tools/run_tests.sh --self-test` (default false)
##   fail_on_errors: bool  — a logged error fails the test (default true)
##   fail_on_warnings: bool — a logged warning fails the test (default true)
##   allowed_logs: Array[String] — regexes for logged lines this test accepts
func describe() -> Dictionary:
	return {}


## Declare the test's world and configuration on `setup` (data only; the runner builds it).
func configure(_setup: TestSetup) -> void:
	pass


## Drive the scene and assert. Awaits through `t` (seconds / frames / until); returning ends the test.
func run(_t: TestContext) -> void:
	pass
