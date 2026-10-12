extends GameTest

## Harness probe for the "an engine error or warning fails the test" gate (tools/test_log_gate.py). It passes
## unless the environment variable GAME_TEST_PROBE is `error` or `warning`, in which case it logs that on purpose
## and does NOT declare it, so the run must report FAIL: in batch (`tools/run_tests.sh --self-test`) and in the
## in-game runner (`-- --play log gate probe`), headless or windowed.


func describe() -> Dictionary:
	return { "name": "Log gate probe", "tags": ["harness", "log"], "internal": true, "timeout": 4.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.seconds(0.1)
	match OS.get_environment("GAME_TEST_PROBE"):
		"error":
			push_error("gate probe error")
		"warning":
			push_warning("gate probe warning")
	await t.seconds(0.5)
	t.check(true, "reached the end")
